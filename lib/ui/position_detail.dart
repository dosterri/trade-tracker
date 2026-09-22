import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/portfolio.dart';
import '../state/app_scope.dart';
import 'position_form.dart';
import 'sparkline.dart';
import 'theme.dart';
import 'trade_card.dart';
import 'txn_form.dart';
import 'widgets.dart';

class PositionDetailPage extends StatelessWidget {
  const PositionDetailPage({super.key, required this.positionId});
  final String positionId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final v = state.viewById(positionId);
    if (v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Position gelöscht')));
    }
    final p = v.position;
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;

    Future<void> manualPrice() async {
      final c = TextEditingController(text: numText(p.manualPrice ?? v.price));
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Kurs manuell setzen'),
          content: NumField(
              controller: c, label: 'Kurs je Stück', suffix: p.currency, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Übernehmen')),
          ],
        ),
      );
      final n = parseNum(c.text);
      c.dispose();
      if (ok != true || n == null || n < 0 || !context.mounted) return;
      try {
        await state.setManualPrice(p, n);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> delete() async {
      final ok = await confirm(context,
          title: 'Position löschen?',
          message: '„${p.name}“ und alle ${v.txns.length} Transaktionen werden '
              'endgültig gelöscht.');
      if (!ok || !context.mounted) return;
      try {
        await state.deletePosition(p.id);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    final sameCcy = v.priceCurrency == p.currency;
    final txns = [...v.txns]..sort((a, b) => b.executedAt.compareTo(a.executedAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Bearbeiten',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PositionFormPage(existing: p))),
          ),
          PopupMenuButton<String>(
            onSelected: (s) {
              if (s == 'manual') manualPrice();
              if (s == 'delete') delete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'manual', child: Text('Kurs manuell setzen')),
              PopupMenuItem(value: 'delete', child: Text('Position löschen')),
            ],
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              Text(positionSubtitle(p), style: t.bodySmall),
              const SizedBox(height: 12),
              Text(v.isOpen ? fmtEur(v.valueEur) : fmtEur(v.realizedEur, signed: true),
                  style: t.headlineMedium),
              Text(
                '${fmtEur(v.cardPnlEur, signed: true)}  ${fmtPct(v.cardPnlPct)}'
                '${v.isOpen ? '  unrealisiert' : '  realisiert'}',
                style: t.bodyMedium?.copyWith(color: pnl.of(v.cardPnlEur)),
              ),
              if (v.isOpen) ...[
                const SizedBox(height: 16),
                Sparkline(
                  points: v.history,
                  color: v.history.length < 2
                      ? pnl.neutral
                      : pnl.of(v.history.last.price - v.history.first.price),
                  height: 90,
                  baseline: sameCcy ? v.ledger.avgOpenPrice : null,
                ),
              ],
              if (v.ledgerError != null) ...[
                const SizedBox(height: 12),
                Text(v.ledgerError!, style: t.bodySmall?.copyWith(color: pnl.loss)),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => showTxnForm(context, v, TxnSide.buy),
                    child: const Text('Kaufen'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: v.isOpen ? () => showTxnForm(context, v, TxnSide.sell) : null,
                    child: const Text('Verkaufen'),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _Facts(view: v),
              const SizedBox(height: 24),
              Text('TRANSAKTIONEN', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final (i, x) in txns.indexed) ...[
                      if (i > 0) const Divider(),
                      _TxnTile(txn: x, currency: p.currency),
                    ],
                    if (txns.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(16), child: Text('Keine Transaktionen')),
                  ],
                ),
              ),
              if (p.notes != null) ...[
                const SizedBox(height: 24),
                Text('NOTIZ', style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
                const SizedBox(height: 8),
                Text(p.notes!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.view});
  final PositionView view;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final p = v.position;
    final l = v.ledger;
    final state = AppScope.of(context);
    final err = state.quoteErrors[p.id];

    final origin = switch (v.origin) {
      PriceOrigin.live => p.priceSource.label,
      PriceOrigin.manual => 'Manuell',
      PriceOrigin.manualFallback => 'Manuell (Quelle gestört)',
      PriceOrigin.none => 'Kein Kurs',
    };

    final rows = <(String, String)>[
      ('Bestand', '${fmtQty(v.openQty)} Stk'),
      ('Ø Einstand', fmtPrice(l.avgOpenPrice, p.currency)),
      ('Einstand gesamt', fmtEur(l.openCostEur)),
      ('Aktueller Kurs', fmtPrice(v.price, v.priceCurrency)),
      ('Kursstand', '${fmtDateTime(v.priceAt)} · $origin'),
      ('Realisiert (vor Steuern)', fmtEur(l.realizedEur, signed: true)),
      ('Steuern', fmtEur(l.taxesEur)),
      ('Gebühren', fmtEur(l.feesEur)),
      if (l.firstBuyAt != null) ('Erster Kauf', fmtDate(l.firstBuyAt)),
      if (p.stopLoss != null) ('Stop-Loss', fmtPrice(p.stopLoss, p.currency)),
      if (p.takeProfit != null) ('Take-Profit', fmtPrice(p.takeProfit, p.currency)),
      if (p.strike != null) ('Strike', fmtPrice(p.strike, p.currency)),
      if (p.barrier != null) ('Knock-out-Schwelle', fmtPrice(p.barrier, p.currency)),
      if (p.ratio != null) ('Bezugsverhältnis', fmtQty(p.ratio!)),
      if (p.expiry != null) ('Laufzeit bis', fmtDate(p.expiry)),
      if (p.issuer != null) ('Emittent', p.issuer!),
      if (p.currency != 'EUR')
        ('Wechselkurs', '${numText(state.fx.rate(p.currency))} ${p.currency}/EUR'),
      if (err != null) ('Letzter Abruffehler', err),
    ];

    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          children: [
            for (final (k, val) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(k, style: t.bodySmall),
                    const SizedBox(width: 16),
                    Expanded(
                        child: Text(val, style: t.bodyMedium, textAlign: TextAlign.right)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn, required this.currency});
  final Txn txn;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final x = txn;
    final extra = [
      if (x.fees != 0) 'Gebühr ${fmtMoney(x.fees, currency)}',
      if (x.taxes != 0) 'Steuer ${fmtMoney(x.taxes, currency)}',
      if (currency != 'EUR') 'FX ${numText(x.fxRate)}',
    ].join(' · ');
    return ListTile(
      dense: true,
      title: Text('${x.side.label} · ${fmtQty(x.quantity)} × ${fmtPrice(x.price, currency)}'),
      subtitle: Text([fmtDate(x.executedAt), if (extra.isNotEmpty) extra].join(' · '),
          style: t.bodySmall),
      trailing: IconButton(
        tooltip: 'Transaktion löschen',
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () async {
          final ok = await confirm(context,
              title: 'Transaktion löschen?',
              message: '${x.side.label} vom ${fmtDate(x.executedAt)} wird gelöscht.');
          if (!ok || !context.mounted) return;
          try {
            await AppScope.read(context).deleteTxn(x);
          } catch (e) {
            if (context.mounted) showError(context, e);
          }
        },
      ),
    );
  }
}
