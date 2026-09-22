import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/fifo.dart';
import '../core/fx.dart';
import '../core/models.dart';
import '../core/portfolio.dart';
import '../data/quote_sources.dart';
import '../data/repository.dart';

enum PositionFilter { open, closed, all }

class AppState extends ChangeNotifier {
  AppState({required this.repo, required this.quotes});

  final Repository repo;
  final QuoteService quotes;

  List<Position> _positions = [];
  List<Txn> _txns = [];
  Map<String, List<PricePoint>> _snapshots = {};
  final Map<String, Quote> _quotes = {};
  final Map<String, String> quoteErrors = {};
  final Map<String, DateTime> _lastSnapshotAt = {};
  FxTable fx = FxTable.eurOnly;
  String? fxError;

  bool loading = false;
  bool refreshingQuotes = false;
  bool offline = false;
  DateTime? cacheSavedAt;
  DateTime? lastQuoteRefresh;
  String? error;

  PositionFilter filter = PositionFilter.open;
  Set<AssetClass> classFilter = {};
  ThemeMode themeMode = ThemeMode.dark;
  bool compact = false;

  List<PositionView> _views = [];
  List<PositionView> get views => _views;

  Timer? _timer;

  // --- Einstellungen -------------------------------------------------------

  Future<void> loadSettings() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode = ThemeMode.values[p.getInt('themeMode') ?? ThemeMode.dark.index];
      compact = p.getBool('compact') ?? false;
    } catch (_) {}
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setInt('themeMode', m.index);
    } catch (_) {}
  }

  Future<void> toggleCompact() async {
    compact = !compact;
    notifyListeners();
    try {
      (await SharedPreferences.getInstance()).setBool('compact', compact);
    } catch (_) {}
  }

  void setFilter(PositionFilter f) {
    filter = f;
    notifyListeners();
  }

  void toggleClass(AssetClass c) {
    classFilter = {...classFilter};
    if (!classFilter.remove(c)) classFilter.add(c);
    notifyListeners();
  }

  // --- Laden ---------------------------------------------------------------

  Future<void> start() async {
    await load();
    unawaited(refreshQuotes());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!refreshingQuotes) refreshQuotes();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await repo.loadAll();
      _positions = data.positions;
      _txns = data.txns;
      _snapshots = {
        for (final e in data.snapshots.entries) e.key: [...e.value],
      };
      for (final e in data.snapshots.entries) {
        if (e.value.isNotEmpty) _lastSnapshotAt[e.key] = e.value.last.at;
      }
      offline = false;
      cacheSavedAt = null;
    } catch (e) {
      final cached = await repo.readCache();
      if (cached != null) {
        _positions = cached.positions;
        _txns = cached.txns;
        _quotes
          ..clear()
          ..addAll(cached.quotes);
        fx = cached.fx;
        offline = true;
        cacheSavedAt = cached.savedAt;
      }
      error = 'Daten konnten nicht geladen werden: $e';
    } finally {
      loading = false;
      _rebuild();
    }
  }

  Future<void> refreshQuotes() async {
    if (refreshingQuotes) return;
    refreshingQuotes = true;
    notifyListeners();

    try {
      fx = await quotes.fx.latest();
      fxError = null;
    } catch (e) {
      fxError = 'Wechselkurse nicht verfügbar: $e';
    }

    final open = _views.where((v) => v.isOpen).map((v) => v.position).toList();
    final snapshotRows = <Map<String, dynamic>>[];
    final now = DateTime.now();

    // Parallel, aber in kleinen Gruppen – schont die (inoffiziellen) Quellen.
    const batch = 4;
    for (var i = 0; i < open.length; i += batch) {
      final group = open.sublist(i, i + batch > open.length ? open.length : i + batch);
      await Future.wait(group.map((p) async {
        try {
          final q = await quotes.quoteFor(p);
          if (q == null) return;
          _quotes[p.id] = q;
          quoteErrors.remove(p.id);
          final last = _lastSnapshotAt[p.id];
          if (last == null ||
              now.difference(last) >= Repository.snapshotInterval) {
            _lastSnapshotAt[p.id] = now;
            snapshotRows.add({
              'position_id': p.id,
              'price': q.price,
              'currency': q.currency,
              'source': q.source.name,
            });
            _snapshots[p.id] = [...?_snapshots[p.id], PricePoint(now, q.price)];
          }
        } catch (e) {
          quoteErrors[p.id] = '$e';
        }
      }));
    }

    if (!offline) {
      try {
        await repo.insertSnapshots(snapshotRows);
      } catch (_) {
        // Snapshots sind nicht kritisch.
      }
    }
    lastQuoteRefresh = DateTime.now();
    refreshingQuotes = false;
    _rebuild();
    if (!offline) {
      unawaited(repo.writeCache(
          positions: _positions, txns: _txns, quotes: _quotes, fx: fx));
    }
  }

  Future<void> _refreshOne(Position p) async {
    try {
      final q = await quotes.quoteFor(p);
      if (q != null) _quotes[p.id] = q;
      quoteErrors.remove(p.id);
    } catch (e) {
      quoteErrors[p.id] = '$e';
    }
    _rebuild();
  }

  void _rebuild() {
    final byPos = <String, List<Txn>>{};
    for (final t in _txns) {
      byPos.putIfAbsent(t.positionId, () => []).add(t);
    }
    _views = [
      for (final p in _positions)
        PositionView.build(
          position: p,
          txns: byPos[p.id] ?? const [],
          quote: _quotes[p.id],
          fx: fx,
          snapshots: _snapshots[p.id] ?? const [],
        ),
    ];
    notifyListeners();
  }

  List<PositionView> get filteredViews {
    final list = _views.where((v) {
      if (classFilter.isNotEmpty && !classFilter.contains(v.position.assetClass)) {
        return false;
      }
      switch (filter) {
        case PositionFilter.open:
          return v.isOpen || v.txns.isEmpty;
        case PositionFilter.closed:
          return v.isClosed;
        case PositionFilter.all:
          return true;
      }
    }).toList();
    if (filter == PositionFilter.closed) {
      list.sort((a, b) => (b.ledger.lastSellAt ?? DateTime(0))
          .compareTo(a.ledger.lastSellAt ?? DateTime(0)));
    } else {
      list.sort((a, b) => (b.valueEur ?? 0).compareTo(a.valueEur ?? 0));
    }
    return list;
  }

  PositionView? viewById(String id) {
    for (final v in _views) {
      if (v.id == id) return v;
    }
    return null;
  }

  // --- Schreiben -----------------------------------------------------------

  void _ensureOnline() {
    if (offline) {
      throw StateError('Offline – Änderungen sind erst wieder online möglich.');
    }
  }

  /// Legt Position + ersten Kauf an. Schlägt der Kauf fehl, wird die Position
  /// wieder entfernt, damit keine leeren Positionen zurückbleiben.
  Future<Position> createPosition(Position p, Txn firstBuy) async {
    _ensureOnline();
    final created = await repo.insertPosition(p);
    try {
      final t = await repo.insertTxn(Txn(
        id: '',
        positionId: created.id,
        side: TxnSide.buy,
        quantity: firstBuy.quantity,
        price: firstBuy.price,
        fees: firstBuy.fees,
        taxes: firstBuy.taxes,
        fxRate: firstBuy.fxRate,
        executedAt: firstBuy.executedAt,
      ));
      _positions = [..._positions, created];
      _txns = [..._txns, t];
    } catch (e) {
      await repo.deletePosition(created.id);
      rethrow;
    }
    _rebuild();
    unawaited(_refreshOne(created));
    return created;
  }

  Future<void> updatePosition(Position p) async {
    _ensureOnline();
    final updated = await repo.updatePosition(p);
    _positions = [for (final x in _positions) x.id == p.id ? updated : x];
    _quotes.remove(p.id);
    _rebuild();
    unawaited(_refreshOne(updated));
  }

  Future<void> setManualPrice(Position p, double price) async {
    await updatePosition(p.copyWith(manualPrice: price, manualPriceAt: DateTime.now()));
  }

  Future<void> deletePosition(String id) async {
    _ensureOnline();
    await repo.deletePosition(id);
    _positions = _positions.where((p) => p.id != id).toList();
    _txns = _txns.where((t) => t.positionId != id).toList();
    _quotes.remove(id);
    _rebuild();
  }

  /// Prüft vor dem Speichern, ob der Bestand die Transaktion zulässt.
  String? validateTxn(Txn t) {
    final existing = _txns.where((x) => x.positionId == t.positionId);
    try {
      computeLedger([...existing, t]);
      return null;
    } on LedgerException catch (e) {
      return e.message;
    }
  }

  Future<void> addTxn(Txn t) async {
    _ensureOnline();
    final problem = validateTxn(t);
    if (problem != null) throw LedgerException(problem);
    final saved = await repo.insertTxn(t);
    _txns = [..._txns, saved];
    _rebuild();
  }

  Future<void> deleteTxn(Txn t) async {
    _ensureOnline();
    final remaining = _txns.where((x) => x.positionId == t.positionId && x.id != t.id);
    try {
      computeLedger(remaining);
    } on LedgerException {
      throw LedgerException(
          'Löschen nicht möglich: Danach würde mehr verkauft als gekauft sein.');
    }
    await repo.deleteTxn(t.id);
    _txns = _txns.where((x) => x.id != t.id).toList();
    _rebuild();
  }

  Future<void> signedOut() async {
    stop();
    _positions = [];
    _txns = [];
    _quotes.clear();
    _snapshots = {};
    await repo.clearCache();
    _rebuild();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
