import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/portfolio.dart';
import 'sparkline.dart';
import 'theme.dart';

class TradeCard extends StatelessWidget {
  const TradeCard({
    super.key,
    required this.view,
    required this.onTap,
    this.compact = false,
    this.quoteError,
  });

  final PositionView view;
  final VoidCallback onTap;
  final bool compact;
  final String? quoteError;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;
    final p = view.position;
    final pnlEur = view.cardPnlEur;
    final color = pnl.of(pnlEur);
    final avg = view.ledger.avgOpenPrice;
    final sameCcy = view.priceCurrency == p.currency;

    final header = Row(
      children: [
        Expanded(
          child: Text(p.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
        ),
        const SizedBox(width: 8),
        _Tag(p.assetClass.label),
      ],
    );

    final badges = <Widget>[
      if (view.ledgerError != null) _Badge('Bestandsfehler', pnl.loss),
      if (view.stopLossHit) _Badge('Stop-Loss erreicht', pnl.loss),
      if (view.takeProfitHit) _Badge('Take-Profit erreicht', pnl.gain),
      if (view.isOpen && view.origin == PriceOrigin.none)
        _Badge('Kein Kurs', pnl.neutral),
      if (view.isOpen && view.origin == PriceOrigin.manualFallback)
        _Badge('Quelle gestört – manueller Kurs', pnl.neutral),
      if (view.isOpen && view.origin == PriceOrigin.manual)
        _Badge('Manueller Kurs', pnl.neutral),
      if (view.isOpen && view.origin != PriceOrigin.none && view.isStale)
        _Badge('Kurs veraltet', pnl.neutral),
      if (quoteError != null && view.isOpen && view.origin != PriceOrigin.live)
        Tooltip(message: quoteError!, child: _Badge('Abruf fehlgeschlagen', pnl.loss)),
    ];

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (view.isOpen)
          Text('${fmtQty(view.openQty)} Stk · Einstand ${fmtPrice(avg, p.currency)}',
              style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)
        else
          Text(
              view.isClosed
                  ? 'Geschlossen ${fmtDate(view.ledger.lastSellAt)}'
                  : 'Keine Transaktionen',
              style: t.bodySmall),
        const SizedBox(height: 2),
        if (view.isOpen)
          Text('Aktuell ${fmtPrice(view.price, view.priceCurrency)}',
              style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(view.isOpen ? fmtEur(view.valueEur) : fmtEur(view.realizedEur, signed: true),
            style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          '${fmtEur(pnlEur, signed: true)}  ${fmtPct(view.cardPnlPct)}',
          style: t.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: compact ? 10 : 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              header,
              SizedBox(height: compact ? 4 : 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [Expanded(child: left), const SizedBox(width: 8), right],
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: badges),
              ],
              if (!compact && view.isOpen) ...[
                const SizedBox(height: 10),
                Sparkline(
                  points: view.history,
                  color: _trendColor(context),
                  baseline: sameCcy ? avg : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _trendColor(BuildContext context) {
    final h = view.history;
    if (h.length < 2) return context.pnl.neutral;
    return context.pnl.of(h.last.price - h.first.price);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      );
}

/// Kleine Hilfe: Label der Positionsart inkl. Derivatetyp.
String positionSubtitle(Position p) {
  final parts = <String>[p.assetClass.label];
  if (p.derivativeType != null) parts.add(p.derivativeType!.label);
  if (p.underlying != null && p.underlying!.isNotEmpty) parts.add(p.underlying!);
  if (p.isin != null) parts.add(p.isin!);
  return parts.join(' · ');
}
