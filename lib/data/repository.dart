import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/fx.dart';
import '../core/models.dart';

class PortfolioData {
  const PortfolioData({
    required this.positions,
    required this.txns,
    required this.snapshots,
  });

  final List<Position> positions;
  final List<Txn> txns;
  final Map<String, List<PricePoint>> snapshots;
}

/// Zugriff auf Supabase. Supabase ist die einzige "Wahrheit"; lokal wird nur
/// ein Lese-Cache gehalten, damit die App offline die letzten Daten zeigt.
class Repository {
  Repository(this._db);
  final SupabaseClient _db;

  static const _cacheKey = 'cache_v1';
  static const snapshotInterval = Duration(minutes: 15);
  static const snapshotDays = 30;

  Future<PortfolioData> loadAll() async {
    final since = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: snapshotDays))
        .toIso8601String();
    final results = await Future.wait([
      _db.from('positions').select().order('created_at'),
      _db.from('transactions').select().order('executed_at'),
      _db
          .from('price_snapshots')
          .select('position_id, price, at')
          .gte('at', since)
          .order('at')
          .limit(5000),
    ]);
    final snaps = <String, List<PricePoint>>{};
    for (final r in results[2]) {
      snaps.putIfAbsent(r['position_id'] as String, () => []).add(PricePoint(
            DateTime.parse(r['at'] as String),
            (r['price'] as num).toDouble(),
          ));
    }
    return PortfolioData(
      positions: [for (final r in results[0]) Position.fromRow(r)],
      txns: [for (final r in results[1]) Txn.fromRow(r)],
      snapshots: snaps,
    );
  }

  Future<Position> insertPosition(Position p) async {
    final row = await _db.from('positions').insert(p.toRow()).select().single();
    return Position.fromRow(row);
  }

  Future<Position> updatePosition(Position p) async {
    final row = await _db
        .from('positions')
        .update(p.toRow()..remove('id'))
        .eq('id', p.id)
        .select()
        .single();
    return Position.fromRow(row);
  }

  Future<void> deletePosition(String id) =>
      _db.from('positions').delete().eq('id', id);

  Future<Txn> insertTxn(Txn t) async {
    final row = await _db.from('transactions').insert(t.toRow()).select().single();
    return Txn.fromRow(row);
  }

  Future<void> deleteTxn(String id) =>
      _db.from('transactions').delete().eq('id', id);

  Future<void> insertSnapshots(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await _db.from('price_snapshots').insert(rows);
  }

  // --- Lokaler Lese-Cache --------------------------------------------------

  Future<void> writeCache({
    required List<Position> positions,
    required List<Txn> txns,
    required Map<String, Quote> quotes,
    required FxTable fx,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          'positions': [for (final p in positions) p.toCache()],
          'txns': [
            for (final t in txns) {...t.toRow(), 'id': t.id}
          ],
          'quotes': quotes.map((k, v) => MapEntry(k, v.toCache())),
          'fx': fx.toCache(),
        }),
      );
    } catch (_) {
      // Cache ist Komfort – Fehler dürfen die App nicht stören.
    }
  }

  Future<CachedState?> readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return CachedState(
        savedAt: DateTime.parse(m['savedAt'] as String),
        positions: [
          for (final r in (m['positions'] as List).cast<Map<String, dynamic>>())
            Position.fromRow(r)
        ],
        txns: [
          for (final r in (m['txns'] as List).cast<Map<String, dynamic>>())
            Txn.fromRow(r)
        ],
        quotes: (m['quotes'] as Map<String, dynamic>).map((k, v) =>
            MapEntry(k, Quote.fromCache(v as Map<String, dynamic>))),
        fx: FxTable.fromCache(m['fx'] as Map<String, dynamic>),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
    } catch (_) {}
  }
}

class CachedState {
  const CachedState({
    required this.savedAt,
    required this.positions,
    required this.txns,
    required this.quotes,
    required this.fx,
  });

  final DateTime savedAt;
  final List<Position> positions;
  final List<Txn> txns;
  final Map<String, Quote> quotes;
  final FxTable fx;
}
