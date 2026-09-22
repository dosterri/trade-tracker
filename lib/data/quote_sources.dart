import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/fx.dart';
import '../core/models.dart';

/// Hinweis: Lang & Schwarz und onvista sind inoffizielle Website-Schnittstellen.
/// Sie können sich jederzeit ändern. Jede Quelle fällt deshalb sauber aus
/// (Exception), und die App zeigt dann den manuellen Kurs bzw. einen Hinweis.

class QuoteException implements Exception {
  QuoteException(this.message);
  final String message;
  @override
  String toString() => message;
}

class InstrumentHit {
  const InstrumentHit({
    required this.source,
    required this.ref,
    required this.name,
    this.isin,
    this.category,
    this.symbol,
  });

  final PriceSource source;
  final String ref;
  final String name;
  final String? isin;
  final String? category;
  final String? symbol;
}

const _timeout = Duration(seconds: 12);

Future<String> _get(http.Client c, Uri uri, {Map<String, String>? headers}) async {
  final res = await c.get(uri, headers: {
    'Accept': 'application/json',
    ...?headers,
  }).timeout(_timeout);
  if (res.statusCode != 200) {
    throw QuoteException('${uri.host}: HTTP ${res.statusCode}');
  }
  return utf8.decode(res.bodyBytes);
}

List<PricePoint> _series(Object? data) => [
      for (final p in (data as List? ?? const []))
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
          PricePoint(
            DateTime.fromMillisecondsSinceEpoch((p[0] as num).toInt(), isUtc: true),
            (p[1] as num).toDouble(),
          ),
    ];

/// Reduziert lange Kursreihen gleichmäßig auf höchstens [max] Punkte
/// (erster und letzter Punkt bleiben erhalten) – genug für eine Sparkline.
List<PricePoint> downsample(List<PricePoint> pts, [int max = 120]) {
  if (pts.length <= max) return pts;
  final step = (pts.length - 1) / (max - 1);
  return [for (var i = 0; i < max; i++) pts[(i * step).round()]];
}

// ---------------------------------------------------------------------------
// Lang & Schwarz Exchange (Aktien, ETFs) – Kurse wie bei Trade Republic.
// ---------------------------------------------------------------------------

class LsSource {
  LsSource(this._client);
  final http.Client _client;
  static const _host = 'www.ls-tc.de';

  Future<List<InstrumentHit>> search(String query) async {
    final body = await _get(_client, Uri.https(_host,
        '/_rpc/json/.lstc/instrument/search/main', {'q': query, 'localeId': '2'}));
    return parseSearch(body);
  }

  Future<Quote> fetch(String instrumentId) async {
    Uri chart(String series) => Uri.https(
        _host, '/_rpc/json/instrument/chart/dataForInstrument', {
      'instrumentId': instrumentId,
      'marketId': '1',
      'quotetype': 'mid',
      'series': series,
      'localeId': '2',
    });
    var points = parseChart(await _get(_client, chart('intraday')), 'intraday');
    if (points.length < 2) {
      // Vor Handelsbeginn / am Wochenende: Tagesschlusskurse.
      final hist = parseChart(await _get(_client, chart('history')), 'history');
      points = hist.length > 30 ? hist.sublist(hist.length - 30) : hist;
    }
    if (points.isEmpty) throw QuoteException('Lang & Schwarz: keine Kurse');
    return Quote(
      price: points.last.price,
      currency: 'EUR',
      at: points.last.at,
      source: PriceSource.ls,
      history: downsample(points),
    );
  }

  static List<InstrumentHit> parseSearch(String body) {
    final list = jsonDecode(body) as List;
    return [
      for (final e in list.cast<Map<String, dynamic>>())
        InstrumentHit(
          source: PriceSource.ls,
          ref: '${e['instrumentId'] ?? e['id']}',
          name: (e['displayname'] as String? ?? '').trim(),
          isin: e['isin'] as String?,
          category: e['categoryName'] as String?,
        ),
    ];
  }

  static List<PricePoint> parseChart(String body, String series) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final s = (m['series'] as Map<String, dynamic>?)?[series];
    if (s is! Map<String, dynamic>) return const [];
    return _series(s['data']);
  }
}

// ---------------------------------------------------------------------------
// onvista (Derivate, Fallback für alles mit ISIN). Nur Snapshot, kein Verlauf.
// ---------------------------------------------------------------------------

class OnvistaSource {
  OnvistaSource(this._client);
  final http.Client _client;
  static const _host = 'api.onvista.de';

  Future<List<InstrumentHit>> search(String query) async {
    final body = await _get(_client,
        Uri.https(_host, '/api/v1/instruments/query', {'searchValue': query}));
    return parseSearch(body);
  }

  /// [ref] hat die Form "ENTITYTYPE/ID", z. B. "BOND/336330339".
  Future<Quote> fetch(String ref, {bool preferBid = false}) async {
    final parts = ref.split('/');
    if (parts.length != 2) throw QuoteException('onvista: ungültige Referenz');
    final body = await _get(_client,
        Uri.https(_host, '/api/v1/instruments/${parts[0]}/${parts[1]}/snapshot'));
    return parseSnapshot(body, preferBid: preferBid);
  }

  static List<InstrumentHit> parseSearch(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final e in (m['list'] as List? ?? const []).cast<Map<String, dynamic>>())
        if (e['entityType'] != null && e['entityValue'] != null)
          InstrumentHit(
            source: PriceSource.onvista,
            ref: '${e['entityType']}/${e['entityValue']}',
            name: (e['name'] as String? ?? '').trim(),
            isin: e['isin'] as String?,
            category: e['entityType'] as String?,
            symbol: e['symbol'] as String?,
          ),
    ];
  }

  /// Bei Derivaten zählt der Geldkurs (Bid): Zu diesem Kurs kann man verkaufen.
  static Quote parseSnapshot(String body, {bool preferBid = false}) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final q = m['quote'] as Map<String, dynamic>?;
    if (q == null) throw QuoteException('onvista: kein Kurs');
    final bid = (q['bid'] as num?)?.toDouble();
    final last = (q['last'] as num?)?.toDouble();
    final useBid = preferBid && bid != null && bid > 0;
    final price = useBid ? bid : last;
    if (price == null) throw QuoteException('onvista: kein Kurs');
    final atRaw = (useBid ? q['datetimeBid'] : null) ?? q['datetimeLast'];
    return Quote(
      price: price,
      currency: (q['isoCurrency'] as String?) ?? 'EUR',
      at: DateTime.tryParse(atRaw as String? ?? '') ?? DateTime.now(),
      source: PriceSource.onvista,
    );
  }
}

// ---------------------------------------------------------------------------
// CoinGecko (Krypto, direkt in EUR).
// ---------------------------------------------------------------------------

class CoinGeckoSource {
  CoinGeckoSource(this._client, {this.demoKey = ''});
  final http.Client _client;
  final String demoKey;
  static const _host = 'api.coingecko.com';

  Map<String, String> get _headers =>
      demoKey.isEmpty ? const {} : {'x-cg-demo-api-key': demoKey};

  Future<List<InstrumentHit>> search(String query) async {
    final body = await _get(
        _client, Uri.https(_host, '/api/v3/search', {'query': query}),
        headers: _headers);
    return parseSearch(body);
  }

  Future<Quote> fetch(String coinId) async {
    final body = await _get(
        _client,
        Uri.https(_host, '/api/v3/coins/$coinId/market_chart',
            {'vs_currency': 'eur', 'days': '1'}),
        headers: _headers);
    return parseMarketChart(body);
  }

  static List<InstrumentHit> parseSearch(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    return [
      for (final c in (m['coins'] as List? ?? const []).cast<Map<String, dynamic>>())
        InstrumentHit(
          source: PriceSource.coingecko,
          ref: c['id'] as String,
          name: c['name'] as String? ?? c['id'] as String,
          symbol: (c['symbol'] as String?)?.toUpperCase(),
          category: 'Krypto',
        ),
    ];
  }

  static Quote parseMarketChart(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final points = _series(m['prices']);
    if (points.isEmpty) throw QuoteException('CoinGecko: keine Kurse');
    return Quote(
      price: points.last.price,
      currency: 'EUR',
      at: points.last.at,
      source: PriceSource.coingecko,
      history: downsample(points),
    );
  }
}

// ---------------------------------------------------------------------------
// Frankfurter (EZB-Referenzkurse).
// ---------------------------------------------------------------------------

class FrankfurterSource {
  FrankfurterSource(this._client);
  final http.Client _client;
  static const _host = 'api.frankfurter.dev';

  Future<FxTable> latest() async =>
      FxTable.fromFrankfurter(await _get(_client,
          Uri.https(_host, '/v1/latest', {'base': 'EUR'})));

  /// EZB-Kurs (Einheiten [currency] je EUR) am [day] bzw. letzten Handelstag davor.
  Future<double> rateOn(DateTime day, String currency) async {
    final d = '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final t = FxTable.fromFrankfurter(await _get(_client,
        Uri.https(_host, '/v1/$d', {'base': 'EUR', 'symbols': currency})));
    final r = t.rate(currency);
    if (r == null) throw QuoteException('Kein EZB-Kurs für $currency');
    return r;
  }
}

// ---------------------------------------------------------------------------

class QuoteService {
  QuoteService({http.Client? client, String coinGeckoKey = ''})
      : _client = client ?? http.Client() {
    ls = LsSource(_client);
    onvista = OnvistaSource(_client);
    coingecko = CoinGeckoSource(_client, demoKey: coinGeckoKey);
    fx = FrankfurterSource(_client);
  }

  final http.Client _client;
  late final LsSource ls;
  late final OnvistaSource onvista;
  late final CoinGeckoSource coingecko;
  late final FrankfurterSource fx;

  /// Holt den Kurs gemäß Quelle der Position. Manuelle Positionen → null.
  Future<Quote?> quoteFor(Position p) async {
    final ref = p.sourceRef;
    switch (p.priceSource) {
      case PriceSource.manual:
        return null;
      case PriceSource.ls:
        if (ref == null) throw QuoteException('Keine LS-ID hinterlegt');
        return ls.fetch(ref);
      case PriceSource.onvista:
        if (ref == null) throw QuoteException('Keine onvista-ID hinterlegt');
        return onvista.fetch(ref,
            preferBid: p.assetClass == AssetClass.derivative);
      case PriceSource.coingecko:
        final id = ref ?? p.symbol;
        if (id == null) throw QuoteException('Keine CoinGecko-ID hinterlegt');
        return coingecko.fetch(id);
    }
  }

  /// Sucht per ISIN/Name: erst LS, dann onvista (bzw. CoinGecko bei Krypto).
  Future<List<InstrumentHit>> search(String query, AssetClass cls) async {
    if (cls == AssetClass.crypto) return coingecko.search(query);
    final hits = <InstrumentHit>[];
    final errors = <String>[];
    // Derivate: onvista zuerst (liefert Geldkurs), sonst LS zuerst.
    final order = cls == AssetClass.derivative
        ? [onvista.search, ls.search]
        : [ls.search, onvista.search];
    for (final s in order) {
      try {
        hits.addAll(await s(query));
      } catch (e) {
        errors.add('$e');
      }
    }
    if (hits.isEmpty && errors.isNotEmpty) {
      throw QuoteException(errors.join('; '));
    }
    return hits;
  }
}
