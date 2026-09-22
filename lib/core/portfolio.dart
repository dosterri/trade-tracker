import 'fifo.dart';
import 'fx.dart';
import 'models.dart';

/// Kurse gelten nach dieser Zeit als veraltet (Anzeige-Hinweis).
const Duration staleAfter = Duration(hours: 26);

enum PriceOrigin { live, manual, manualFallback, none }

/// Berechnete Sicht auf eine Position: Bestand, Bewertung und PnL in EUR.
class PositionView {
  PositionView._({
    required this.position,
    required this.txns,
    required this.ledger,
    required this.ledgerError,
    required this.price,
    required this.priceCurrency,
    required this.priceAt,
    required this.origin,
    required this.valueEur,
    required this.history,
  });

  final Position position;
  final List<Txn> txns;
  final LedgerResult ledger;
  final String? ledgerError;

  /// Aktueller Stückpreis in [priceCurrency].
  final double? price;
  final String priceCurrency;
  final DateTime? priceAt;
  final PriceOrigin origin;

  /// Marktwert der offenen Stücke in EUR (null, wenn Kurs/FX fehlt).
  final double? valueEur;
  final List<PricePoint> history;

  factory PositionView.build({
    required Position position,
    required List<Txn> txns,
    required Quote? quote,
    required FxTable fx,
    List<PricePoint> snapshots = const [],
  }) {
    LedgerResult ledger;
    String? error;
    try {
      ledger = computeLedger(txns);
    } on LedgerException catch (e) {
      error = e.message;
      ledger = computeLedger(const []);
    }

    double? price;
    String currency = position.currency;
    DateTime? at;
    var origin = PriceOrigin.none;
    var history = const <PricePoint>[];

    if (position.priceSource == PriceSource.manual) {
      if (position.manualPrice != null) {
        price = position.manualPrice;
        at = position.manualPriceAt;
        origin = PriceOrigin.manual;
      }
    } else if (quote != null) {
      price = quote.price;
      currency = quote.currency;
      at = quote.at;
      origin = PriceOrigin.live;
      history = quote.history;
    } else if (position.manualPrice != null) {
      price = position.manualPrice;
      at = position.manualPriceAt;
      origin = PriceOrigin.manualFallback;
    }

    // Quelle liefert keinen Verlauf (onvista, manuell) → eigene Snapshots.
    if (history.length < 2 && snapshots.length >= 2) history = snapshots;

    final qty = ledger.openQty;
    double? value;
    if (qty <= qtyEpsilon) {
      value = 0;
    } else if (price != null) {
      value = fx.toEur(qty * price, currency);
    }

    return PositionView._(
      position: position,
      txns: txns,
      ledger: ledger,
      ledgerError: error,
      price: price,
      priceCurrency: currency,
      priceAt: at,
      origin: origin,
      valueEur: value,
      history: history,
    );
  }

  String get id => position.id;
  bool get isClosed => ledger.isClosed;
  bool get isOpen => ledger.openQty > qtyEpsilon;
  double get openQty => ledger.openQty;

  /// Unrealisierter Gewinn/Verlust in EUR (offene Stücke).
  double? get unrealizedEur =>
      isOpen && valueEur != null ? valueEur! - ledger.openCostEur : null;

  double? get unrealizedPct {
    final u = unrealizedEur;
    final c = ledger.openCostEur;
    if (u == null || c <= 0) return null;
    return u / c;
  }

  double get realizedEur => ledger.realizedEur;

  double? get realizedPct {
    final c = ledger.closedCostEur;
    if (c <= 0 || ledger.closed.isEmpty) return null;
    return ledger.realizedEur / c;
  }

  /// PnL für die Card: offen → unrealisiert, geschlossen → realisiert.
  double? get cardPnlEur => isOpen ? unrealizedEur : realizedEur;
  double? get cardPnlPct => isOpen ? unrealizedPct : realizedPct;

  bool get isStale =>
      priceAt == null || DateTime.now().difference(priceAt!) > staleAfter;

  /// Stop-Loss erreicht/unterschritten (Kurs in Positionswährung).
  bool get stopLossHit {
    final sl = position.stopLoss;
    return isOpen && sl != null && price != null && _samePriceCcy && price! <= sl;
  }

  bool get takeProfitHit {
    final tp = position.takeProfit;
    return isOpen && tp != null && price != null && _samePriceCcy && price! >= tp;
  }

  bool get _samePriceCcy => priceCurrency == position.currency;
}

class PortfolioSummary {
  const PortfolioSummary({
    required this.valueEur,
    required this.unrealizedEur,
    required this.realizedEur,
    required this.taxesEur,
    required this.missingPrices,
  });

  final double valueEur;
  final double unrealizedEur;
  final double realizedEur;
  final double taxesEur;

  /// Anzahl offener Positionen ohne Bewertung.
  final int missingPrices;

  factory PortfolioSummary.of(Iterable<PositionView> views) {
    var value = 0.0, unreal = 0.0, real = 0.0, tax = 0.0;
    var missing = 0;
    for (final v in views) {
      real += v.realizedEur;
      tax += v.ledger.taxesEur;
      if (!v.isOpen) continue;
      if (v.valueEur == null) {
        missing++;
        continue;
      }
      value += v.valueEur!;
      unreal += v.unrealizedEur ?? 0;
    }
    return PortfolioSummary(
      valueEur: value,
      unrealizedEur: unreal,
      realizedEur: real,
      taxesEur: tax,
      missingPrices: missing,
    );
  }
}
