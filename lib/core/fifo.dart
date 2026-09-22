import 'models.dart';

/// Toleranz für Stückzahl-Vergleiche (Krypto hat bis zu 8 Nachkommastellen).
const double qtyEpsilon = 1e-9;

class LedgerException implements Exception {
  LedgerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Ein noch (teilweise) offener Kauf-Posten.
class Lot {
  Lot({
    required this.quantity,
    required this.unitPrice,
    required this.unitFee,
    required this.fxRate,
    required this.openedAt,
  });

  double quantity;
  final double unitPrice;
  final double unitFee;
  final double fxRate;
  final DateTime openedAt;

  /// Einstand je Stück in EUR inkl. anteiliger Kaufgebühr.
  double get unitCostEur => (unitPrice + unitFee) / fxRate;
}

/// Ein durch Verkauf geschlossener Teil eines Lots (Basis für Analytics).
class ClosedSlice {
  const ClosedSlice({
    required this.quantity,
    required this.openedAt,
    required this.closedAt,
    required this.costEur,
    required this.proceedsEur,
  });

  final double quantity;
  final DateTime openedAt;
  final DateTime closedAt;
  final double costEur;

  /// Erlös nach anteiliger Verkaufsgebühr, vor Steuern.
  final double proceedsEur;

  double get pnlEur => proceedsEur - costEur;
  Duration get holding => closedAt.difference(openedAt);
}

class LedgerResult {
  const LedgerResult({
    required this.openLots,
    required this.closed,
    required this.realizedEur,
    required this.feesEur,
    required this.taxesEur,
    required this.boughtQty,
    required this.firstBuyAt,
    required this.lastSellAt,
  });

  final List<Lot> openLots;
  final List<ClosedSlice> closed;

  /// Realisierter Gewinn/Verlust in EUR nach Gebühren, vor Steuern.
  final double realizedEur;
  final double feesEur;
  final double taxesEur;
  final double boughtQty;
  final DateTime? firstBuyAt;
  final DateTime? lastSellAt;

  double get openQty => openLots.fold(0.0, (s, l) => s + l.quantity);

  /// Einstand der offenen Stücke in EUR inkl. Kaufgebühren.
  double get openCostEur =>
      openLots.fold(0.0, (s, l) => s + l.quantity * l.unitCostEur);

  /// Durchschnittlicher Einstandskurs der offenen Stücke in
  /// Positionswährung (ohne Gebühren) – so wie der Broker ihn anzeigt.
  double? get avgOpenPrice {
    final q = openQty;
    if (q <= qtyEpsilon) return null;
    return openLots.fold(0.0, (s, l) => s + l.quantity * l.unitPrice) / q;
  }

  double get closedCostEur => closed.fold(0.0, (s, c) => s + c.costEur);

  bool get isClosed => openQty <= qtyEpsilon && closed.isNotEmpty;

  /// Realisiert nach Steuern.
  double get realizedNetEur => realizedEur - taxesEur;
}

/// Verrechnet alle Transaktionen einer Position nach FIFO.
///
/// Wirft [LedgerException], wenn mehr verkauft als gehalten wird.
LedgerResult computeLedger(Iterable<Txn> txns) {
  final sorted = txns.toList()
    ..sort((a, b) {
      final c = a.executedAt.compareTo(b.executedAt);
      if (c != 0) return c;
      // Am selben Zeitpunkt zuerst Käufe verbuchen.
      return a.side.index.compareTo(b.side.index);
    });

  final lots = <Lot>[];
  final closed = <ClosedSlice>[];
  var realized = 0.0;
  var fees = 0.0;
  var taxes = 0.0;
  var bought = 0.0;
  DateTime? firstBuy;
  DateTime? lastSell;

  for (final t in sorted) {
    if (t.quantity <= 0) {
      throw LedgerException('Stückzahl muss größer als 0 sein.');
    }
    if (t.fxRate <= 0) {
      throw LedgerException('Wechselkurs muss größer als 0 sein.');
    }
    fees += t.fees / t.fxRate;
    taxes += t.taxes / t.fxRate;

    if (t.side == TxnSide.buy) {
      lots.add(Lot(
        quantity: t.quantity,
        unitPrice: t.price,
        unitFee: t.fees / t.quantity,
        fxRate: t.fxRate,
        openedAt: t.executedAt,
      ));
      bought += t.quantity;
      firstBuy ??= t.executedAt;
      continue;
    }

    final available = lots.fold(0.0, (s, l) => s + l.quantity);
    if (t.quantity > available + qtyEpsilon) {
      throw LedgerException(
        'Verkauf von ${t.quantity} Stück, aber nur $available im Bestand.',
      );
    }

    final unitProceedsEur = (t.price - t.fees / t.quantity) / t.fxRate;
    var remaining = t.quantity;
    while (remaining > qtyEpsilon && lots.isNotEmpty) {
      final lot = lots.first;
      final take = remaining < lot.quantity ? remaining : lot.quantity;
      final slice = ClosedSlice(
        quantity: take,
        openedAt: lot.openedAt,
        closedAt: t.executedAt,
        costEur: take * lot.unitCostEur,
        proceedsEur: take * unitProceedsEur,
      );
      closed.add(slice);
      realized += slice.pnlEur;
      lot.quantity -= take;
      remaining -= take;
      if (lot.quantity <= qtyEpsilon) lots.removeAt(0);
    }
    lastSell = t.executedAt;
  }

  return LedgerResult(
    openLots: lots,
    closed: closed,
    realizedEur: realized,
    feesEur: fees,
    taxesEur: taxes,
    boughtQty: bought,
    firstBuyAt: firstBuy,
    lastSellAt: lastSell,
  );
}
