import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/portfolio.dart';
import '../state/app_scope.dart';
import '../state/app_state.dart';
import 'analytics_page.dart';
import 'import_page.dart';
import 'position_detail.dart';
import 'position_form.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'trade_card.dart';
import 'txn_form.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static void newTrade(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const PositionFormPage()));

  static void openSettings(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const SettingsPage()));

  static void openAnalytics(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const AnalyticsPage()));

  static void openImport(BuildContext context) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const ImportPage()));

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final views = state.filteredViews;
    final wide = isWide(context);

    void refresh() {
      state.load().then((_) => state.refreshQuotes());
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => newTrade(context),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): refresh,
        const SingleActivator(LogicalKeyboardKey.f5): refresh,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): state.toggleCompact,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            state.setFilter(PositionFilter.open),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            state.setFilter(PositionFilter.closed),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            state.setFilter(PositionFilter.all),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            openSettings(context),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            openImport(context),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
            openAnalytics(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Portfolio'),
            actions: [
              if (state.refreshingQuotes || state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(
                  tooltip: 'Aktualisieren (Strg+R)',
                  icon: const Icon(Icons.refresh),
                  onPressed: refresh,
                ),
              IconButton(
                tooltip: state.compact ? 'Normale Ansicht (Strg+K)' : 'Kompakte Ansicht (Strg+K)',
                icon: Icon(state.compact ? Icons.view_agenda_outlined : Icons.view_headline),
                onPressed: state.toggleCompact,
              ),
              IconButton(
                tooltip: 'Auswertung (Strg+A)',
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => openAnalytics(context),
              ),
              IconButton(
                tooltip: 'PDF-Import (Strg+I)',
                icon: const Icon(Icons.file_upload_outlined),
                onPressed: () => openImport(context),
              ),
              IconButton(
                tooltip: 'Einstellungen',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => openSettings(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => newTrade(context),
            icon: const Icon(Icons.add),
            label: Text(wide ? 'Neuer Trade (Strg+N)' : 'Trade'),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await state.load();
              await state.refreshQuotes();
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _Header(state: state)),
                if (views.isEmpty && !state.loading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _Empty(filter: state.filter),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    sliver: wide
                        ? _gridRows(context, state, views)
                        : SliverList.separated(
                            itemCount: views.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _swipeable(ctx, state, views[i]),
                          ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Raster für breite Fenster: gleich hohe Cards pro Zeile, Höhe richtet
  /// sich nach dem Inhalt (keine festen Höhen → kein Überlauf).
  Widget _gridRows(BuildContext context, AppState state, List<PositionView> views) {
    final width = MediaQuery.sizeOf(context).width - 32;
    final maxExtent = state.compact ? 360.0 : 440.0;
    final cols = (width / maxExtent).ceil().clamp(1, 6);
    final rows = (views.length / cols).ceil();
    return SliverList.separated(
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, r) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: 12),
              Expanded(
                child: r * cols + c < views.length
                    ? _card(ctx, state, views[r * cols + c])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, AppState state, PositionView v) => TradeCard(
        view: v,
        compact: state.compact,
        quoteError: state.quoteErrors[v.id],
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => PositionDetailPage(positionId: v.id))),
      );

  /// iOS-Geste: nach links wischen = Verkaufen, nach rechts = Nachkaufen.
  Widget _swipeable(BuildContext context, AppState state, PositionView v) {
    final card = _card(context, state, v);
    if (!v.isOpen) return card;
    final pnl = context.pnl;
    Widget bg(Alignment a, Color c, String label, IconData icon) => Container(
          alignment: a,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
          ]),
        );
    return Dismissible(
      key: ValueKey('swipe-${v.id}'),
      background: bg(Alignment.centerLeft, pnl.gain, 'Nachkaufen', Icons.add),
      secondaryBackground:
          bg(Alignment.centerRight, pnl.loss, 'Verkaufen', Icons.logout),
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        final side =
            dir == DismissDirection.startToEnd ? TxnSide.buy : TxnSide.sell;
        await showTxnForm(context, v, side);
        return false; // Card bleibt stehen, Liste aktualisiert sich selbst.
      },
      child: card,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;
    final s = PortfolioSummary.of(state.views);
    final c = Theme.of(context).colorScheme;

    final notices = <String>[
      if (state.offline)
        'Offline – Stand ${fmtDateTime(state.cacheSavedAt)}, nur Lesen.'
      else if (state.error != null)
        state.error!,
      if (state.fxError != null) state.fxError!,
      if (s.missingPrices > 0)
        '${s.missingPrices} offene Position(en) ohne Kurs – nicht im Gesamtwert enthalten.',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(fmtEur(s.valueEur), style: t.headlineMedium),
          const SizedBox(height: 2),
          Wrap(spacing: 16, runSpacing: 4, children: [
            Text('Unrealisiert ${fmtEur(s.unrealizedEur, signed: true)}',
                style: t.bodySmall?.copyWith(color: pnl.of(s.unrealizedEur))),
            Text('Realisiert ${fmtEur(s.realizedEur, signed: true)}',
                style: t.bodySmall?.copyWith(color: pnl.of(s.realizedEur))),
            if (state.lastQuoteRefresh != null)
              Text('Kurse ${fmtDateTime(state.lastQuoteRefresh)}', style: t.bodySmall),
          ]),
          for (final n in notices)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: c.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(n, style: t.bodySmall),
              ),
            ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SegmentedButton<PositionFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PositionFilter.open, label: Text('Offen')),
                  ButtonSegment(value: PositionFilter.closed, label: Text('Geschlossen')),
                  ButtonSegment(value: PositionFilter.all, label: Text('Alle')),
                ],
                selected: {state.filter},
                onSelectionChanged: (sel) {
                  HapticFeedback.selectionClick();
                  state.setFilter(sel.first);
                },
              ),
              const SizedBox(width: 12),
              for (final cls in AssetClass.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cls.label),
                    selected: state.classFilter.contains(cls),
                    onSelected: (_) => state.toggleClass(cls),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});
  final PositionFilter filter;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            filter == PositionFilter.closed
                ? 'Noch keine geschlossenen Trades'
                : 'Noch keine offenen Positionen',
            style: t.titleMedium,
          ),
          const SizedBox(height: 6),
          Text('Lege deinen ersten Trade über „+“ an.', style: t.bodySmall),
        ]),
      ),
    );
  }
}
