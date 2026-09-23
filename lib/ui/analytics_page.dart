import 'package:flutter/material.dart';

import '../core/analytics.dart';
import '../core/format.dart';
import '../state/app_scope.dart';
import 'theme.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = Analytics.of(state.views);
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
          child: Text(s.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        );

    final maxValue = a.byClass.fold<double>(
        0, (m, c) => c.valueEur > m ? c.valueEur : m);

    return Scaffold(
      appBar: AppBar(title: const Text('Auswertung')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text(fmtEur(a.summary.valueEur), style: t.headlineMedium),
              Text(
                'Unrealisiert ${fmtEur(a.summary.unrealizedEur, signed: true)} · '
                'Realisiert ${fmtEur(a.summary.realizedEur, signed: true)}',
                style: t.bodySmall?.copyWith(color: pnl.of(a.summary.unrealizedEur)),
              ),
              label('Nach Anlageklasse'),
              if (a.byClass.isEmpty)
                Text('Noch keine Positionen.', style: t.bodySmall)
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        for (final c in a.byClass)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      '${c.assetClass.label}'
                                      '${c.openCount > 0 ? ' · ${c.openCount} offen' : ''}',
                                      style: t.bodyMedium,
                                    ),
                                  ),
                                  Text(fmtEur(c.valueEur), style: t.bodyMedium),
                                ]),
                                const SizedBox(height: 6),
                                _Bar(
                                  fraction: maxValue > 0 ? c.valueEur / maxValue : 0,
                                  color: pnl.of(c.unrealizedEur),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Unrealisiert ${fmtEur(c.unrealizedEur, signed: true)} '
                                  '(${fmtPct(c.unrealizedPct)}) · '
                                  'Realisiert ${fmtEur(c.realizedEur, signed: true)}',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              label('Geschlossene Trades'),
              _Facts(rows: [
                ('Abgeschlossene Verkäufe', '${a.trades.closedCount}'),
                ('Gewinne / Verluste', '${a.trades.wins} / ${a.trades.losses}'),
                ('Trefferquote', fmtRate(a.trades.winRate)),
                ('Ergebnis gesamt', fmtEur(a.trades.netEur, signed: true)),
                ('Summe Gewinne', fmtEur(a.trades.grossProfit)),
                ('Summe Verluste',
                    fmtEur(a.trades.grossLoss == 0 ? 0 : -a.trades.grossLoss)),
                (
                  'Gewinn-/Verlustverhältnis',
                  a.trades.profitFactor == null
                      ? '–'
                      : a.trades.profitFactor!.toStringAsFixed(2)
                ),
                (
                  'Bester Trade',
                  a.trades.wins == 0 ? '–' : fmtEur(a.trades.bestEur, signed: true)
                ),
                (
                  'Schlechtester Trade',
                  a.trades.losses == 0 ? '–' : fmtEur(a.trades.worstEur, signed: true)
                ),
                ('Ø Gewinn', fmtEur(a.trades.avgWin)),
                ('Ø Verlust', fmtEur(a.trades.avgLoss == null ? null : -a.trades.avgLoss!)),
              ]),
              label('Haltedauer'),
              _Facts(rows: [
                ('Ø gesamt', _days(a.trades.avgHoldingDays)),
                ('Ø bei Gewinnen', _days(a.trades.avgWinnerHoldingDays)),
                ('Ø bei Verlusten', _days(a.trades.avgLoserHoldingDays)),
              ]),
              label('Kosten'),
              _Facts(rows: [
                ('Gebühren gesamt', fmtEur(a.feesEur)),
                ('Steuern gesamt', fmtEur(a.taxesEur)),
                ('Realisiert nach Steuern',
                    fmtEur(a.summary.realizedEur - a.taxesEur, signed: true)),
              ]),
              const SizedBox(height: 24),
              Text(
                'Alle Werte beziehen sich auf deine erfassten Trades und sind '
                'ohne Gewähr. Maßgeblich bleiben die Abrechnungen deines Brokers. '
                'Keine Anlageberatung.',
                style: t.bodySmall?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _days(double d) {
    if (d <= 0) return '–';
    if (d < 1) return '${(d * 24).toStringAsFixed(1)} Std.';
    return '${d.toStringAsFixed(d < 10 ? 1 : 0)} Tage';
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: fraction.clamp(0, 1),
          minHeight: 6,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: t.bodySmall),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(v, style: t.bodyMedium, textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
