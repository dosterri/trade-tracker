import 'fifo.dart';
import 'models.dart';
import 'portfolio.dart';

/// Auswertungen über alle Positionen – reine Logik, ohne Flutter.

class ClassStats {
  const ClassStats({
    required this.assetClass,
    required this.openCount,
    required this.valueEur,
    required this.unrealizedEur,
    required this.realizedEur,
    required this.investedEur,
  });

  final AssetClass assetClass;
  final int openCount;
  final double valueEur;
  final double unrealizedEur;
  final double realizedEur;

  /// Eingesetztes Kapital der offenen Positionen (Einstand inkl. Gebühren).
  final double investedEur;

  double get totalPnlEur => unrealizedEur + realizedEur;

  /// Rendite der offenen Positionen; null, wenn nichts investiert ist.
  double? get unrealizedPct =>
      investedEur > 0 ? unrealizedEur / investedEur : null;
}

class TradeStats {
  const TradeStats({
    required this.closedCount,
    required this.wins,
    required this.losses,
    required this.grossProfit,
    required this.grossLoss,
    required this.bestEur,
    required this.worstEur,
    required this.avgHoldingDays,
    required this.avgWinnerHoldingDays,
    required this.avgLoserHoldingDays,
  });

  final int closedCount;
  final int wins;
  final int losses;

  /// Summe aller Gewinne bzw. Verluste (beide positiv).
  final double grossProfit;
  final double grossLoss;
  final double bestEur;
  final double worstEur;
  final double avgHoldingDays;
  final double avgWinnerHoldingDays;
  final double avgLoserHoldingDays;

  double? get winRate => closedCount > 0 ? wins / closedCount : null;
  double get netEur => grossProfit - grossLoss;

  /// Verhältnis Gewinnsumme zu Verlustsumme; null, wenn es keine Verluste gibt.
  double? get profitFactor => grossLoss > 0 ? grossProfit / grossLoss : null;

  double? get avgWin => wins > 0 ? grossProfit / wins : null;
  double? get avgLoss => losses > 0 ? grossLoss / losses : null;
}

class Analytics {
  const Analytics({
    required this.byClass,
    required this.trades,
    required this.summary,
    required this.taxesEur,
    required this.feesEur,
  });

  final List<ClassStats> byClass;
  final TradeStats trades;
  final PortfolioSummary summary;
  final double taxesEur;
  final double feesEur;

  factory Analytics.of(Iterable<PositionView> views) {
    final open = <AssetClass, List<double>>{};
    final counts = <AssetClass, int>{};
    var fees = 0.0, taxes = 0.0;

    // [Wert, unrealisiert, realisiert, investiert] je Anlageklasse
    for (final v in views) {
      final c = v.position.assetClass;
      final acc = open.putIfAbsent(c, () => [0, 0, 0, 0]);
      fees += v.ledger.feesEur;
      taxes += v.ledger.taxesEur;
      acc[2] += v.realizedEur;
      if (!v.isOpen) continue;
      counts[c] = (counts[c] ?? 0) + 1;
      acc[3] += v.ledger.openCostEur;
      if (v.valueEur == null) continue;
      acc[0] += v.valueEur!;
      acc[1] += v.unrealizedEur ?? 0;
    }

    final byClass = [
      for (final c in AssetClass.values)
        if (open.containsKey(c))
          ClassStats(
            assetClass: c,
            openCount: counts[c] ?? 0,
            valueEur: open[c]![0],
            unrealizedEur: open[c]![1],
            realizedEur: open[c]![2],
            investedEur: open[c]![3],
          ),
    ];

    final slices = <ClosedSlice>[
      for (final v in views) ...v.ledger.closed,
    ];
    var wins = 0, losses = 0;
    var grossProfit = 0.0, grossLoss = 0.0;
    var best = 0.0, worst = 0.0;
    var days = 0.0, winnerDays = 0.0, loserDays = 0.0;

    for (final s in slices) {
      final pnl = s.pnlEur;
      final d = s.holding.inMinutes / (60 * 24);
      days += d;
      if (pnl >= 0) {
        wins++;
        grossProfit += pnl;
        winnerDays += d;
        if (pnl > best) best = pnl;
      } else {
        losses++;
        grossLoss += -pnl;
        loserDays += d;
        if (pnl < worst) worst = pnl;
      }
    }

    return Analytics(
      byClass: byClass,
      summary: PortfolioSummary.of(views),
      feesEur: fees,
      taxesEur: taxes,
      trades: TradeStats(
        closedCount: slices.length,
        wins: wins,
        losses: losses,
        grossProfit: grossProfit,
        grossLoss: grossLoss,
        bestEur: best,
        worstEur: worst,
        avgHoldingDays: slices.isEmpty ? 0 : days / slices.length,
        avgWinnerHoldingDays: wins == 0 ? 0 : winnerDays / wins,
        avgLoserHoldingDays: losses == 0 ? 0 : loserDays / losses,
      ),
    );
  }
}
