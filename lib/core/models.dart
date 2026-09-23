// Datenmodelle. Bewusst ohne Flutter-Abhängigkeit, damit sie in reinen
// Dart-Tests geprüft werden können.

enum AssetClass {
  stock('Aktie'),
  etf('ETF'),
  derivative('Derivat'),
  crypto('Krypto');

  const AssetClass(this.label);
  final String label;

  static AssetClass parse(String v) =>
      AssetClass.values.firstWhere((e) => e.name == v, orElse: () => stock);
}

enum DerivativeType {
  call('Call (Optionsschein)'),
  put('Put (Optionsschein)'),
  koLong('Knock-out Long'),
  koShort('Knock-out Short'),
  factorLong('Faktor Long'),
  factorShort('Faktor Short'),
  other('Sonstiges');

  const DerivativeType(this.label);
  final String label;

  static DerivativeType? parse(String? v) {
    if (v == null) return null;
    for (final e in DerivativeType.values) {
      if (e.name == v) return e;
    }
    return null;
  }
}

enum PriceSource {
  ls('Lang & Schwarz'),
  onvista('onvista'),
  coingecko('CoinGecko'),
  manual('Manuell');

  const PriceSource(this.label);
  final String label;

  static PriceSource parse(String? v) =>
      PriceSource.values.firstWhere((e) => e.name == v, orElse: () => manual);
}

enum TxnSide {
  buy('Kauf'),
  sell('Verkauf');

  const TxnSide(this.label);
  final String label;

  static TxnSide parse(String v) => v == 'sell' ? sell : buy;
}

double? _num(Object? v) => v == null ? null : (v as num).toDouble();
double? _numOrString(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);

class Position {
  const Position({
    required this.id,
    required this.assetClass,
    required this.name,
    this.isin,
    this.symbol,
    this.currency = 'EUR',
    this.priceSource = PriceSource.manual,
    this.sourceRef,
    this.manualPrice,
    this.manualPriceAt,
    this.stopLoss,
    this.takeProfit,
    this.alertUpPct,
    this.alertDownPct,
    this.alertsEnabled = true,
    this.derivativeType,
    this.underlying,
    this.strike,
    this.barrier,
    this.expiry,
    this.ratio,
    this.issuer,
    this.notes,
    this.createdAt,
  });

  final String id;
  final AssetClass assetClass;
  final String name;
  final String? isin;

  /// Bei Krypto: CoinGecko-ID (z. B. "bitcoin"), sonst optionales Kürzel.
  final String? symbol;

  /// Handelswährung der Transaktionen (ISO-Code).
  final String currency;
  final PriceSource priceSource;

  /// Quellen-ID: LS-instrumentId oder onvista "TYP/ID".
  final String? sourceRef;
  final double? manualPrice;
  final DateTime? manualPriceAt;
  final double? stopLoss;
  final double? takeProfit;

  /// Meldung, wenn der unrealisierte Gewinn diesen Prozentwert erreicht (z. B. 10).
  final double? alertUpPct;

  /// Meldung, wenn der unrealisierte Verlust diesen Prozentwert erreicht (z. B. 5).
  final double? alertDownPct;
  final bool alertsEnabled;

  final DerivativeType? derivativeType;
  final String? underlying;
  final double? strike;
  final double? barrier;
  final DateTime? expiry;
  final double? ratio;
  final String? issuer;
  final String? notes;
  final DateTime? createdAt;

  factory Position.fromRow(Map<String, dynamic> r) => Position(
        id: r['id'] as String,
        assetClass: AssetClass.parse(r['asset_class'] as String),
        name: r['name'] as String,
        isin: r['isin'] as String?,
        symbol: r['symbol'] as String?,
        currency: (r['currency'] as String?) ?? 'EUR',
        priceSource: PriceSource.parse(r['price_source'] as String?),
        sourceRef: r['source_ref'] as String?,
        manualPrice: _numOrString(r['manual_price']),
        manualPriceAt: _date(r['manual_price_at']),
        stopLoss: _numOrString(r['stop_loss']),
        takeProfit: _numOrString(r['take_profit']),
        alertUpPct: _numOrString(r['alert_up_pct']),
        alertDownPct: _numOrString(r['alert_down_pct']),
        alertsEnabled: (r['alerts_enabled'] as bool?) ?? true,
        derivativeType: DerivativeType.parse(r['derivative_type'] as String?),
        underlying: r['underlying'] as String?,
        strike: _numOrString(r['strike']),
        barrier: _numOrString(r['barrier']),
        expiry: _date(r['expiry']),
        ratio: _numOrString(r['ratio']),
        issuer: r['issuer'] as String?,
        notes: r['notes'] as String?,
        createdAt: _date(r['created_at']),
      );

  /// Spalten für insert/update. `id` wird nur mitgeschickt, wenn vorhanden.
  Map<String, dynamic> toRow() => {
        if (id.isNotEmpty) 'id': id,
        'asset_class': assetClass.name,
        'name': name,
        'isin': isin,
        'symbol': symbol,
        'currency': currency,
        'price_source': priceSource.name,
        'source_ref': sourceRef,
        'manual_price': manualPrice,
        'manual_price_at': manualPriceAt?.toUtc().toIso8601String(),
        'stop_loss': stopLoss,
        'take_profit': takeProfit,
        'alert_up_pct': alertUpPct,
        'alert_down_pct': alertDownPct,
        'alerts_enabled': alertsEnabled,
        'derivative_type': derivativeType?.name,
        'underlying': underlying,
        'strike': strike,
        'barrier': barrier,
        'expiry': expiry == null
            ? null
            : '${expiry!.year.toString().padLeft(4, '0')}-'
                '${expiry!.month.toString().padLeft(2, '0')}-'
                '${expiry!.day.toString().padLeft(2, '0')}',
        'ratio': ratio,
        'issuer': issuer,
        'notes': notes,
      };

  Map<String, dynamic> toCache() => {
        ...toRow(),
        'id': id,
        'created_at': createdAt?.toIso8601String(),
      };

  Position copyWith({
    double? manualPrice,
    DateTime? manualPriceAt,
  }) =>
      Position.fromRow({
        ...toCache(),
        'manual_price': manualPrice ?? this.manualPrice,
        'manual_price_at':
            (manualPriceAt ?? this.manualPriceAt)?.toIso8601String(),
      });
}

class Txn {
  const Txn({
    required this.id,
    required this.positionId,
    required this.side,
    required this.quantity,
    required this.price,
    required this.executedAt,
    this.fees = 0,
    this.taxes = 0,
    this.fxRate = 1,
  });

  final String id;
  final String positionId;
  final TxnSide side;
  final double quantity;

  /// Stückpreis in der Positionswährung.
  final double price;

  /// Gebühren gesamt in Positionswährung.
  final double fees;

  /// Steuern gesamt in Positionswährung (bei Erstattung negativ).
  final double taxes;

  /// Einheiten Positionswährung je 1 EUR (EZB-Notation, EUR = 1).
  final double fxRate;
  final DateTime executedAt;

  factory Txn.fromRow(Map<String, dynamic> r) => Txn(
        id: r['id'] as String,
        positionId: r['position_id'] as String,
        side: TxnSide.parse(r['side'] as String),
        quantity: _numOrString(r['quantity'])!,
        price: _numOrString(r['price'])!,
        fees: _numOrString(r['fees']) ?? 0,
        taxes: _numOrString(r['taxes']) ?? 0,
        fxRate: _numOrString(r['fx_rate']) ?? 1,
        executedAt: DateTime.parse(r['executed_at'] as String),
      );

  Map<String, dynamic> toRow() => {
        if (id.isNotEmpty) 'id': id,
        'position_id': positionId,
        'side': side.name,
        'quantity': quantity,
        'price': price,
        'fees': fees,
        'taxes': taxes,
        'fx_rate': fxRate,
        'executed_at': executedAt.toUtc().toIso8601String(),
      };
}

class PricePoint {
  const PricePoint(this.at, this.price);
  final DateTime at;
  final double price;
}

class Quote {
  const Quote({
    required this.price,
    required this.currency,
    required this.at,
    required this.source,
    this.history = const [],
  });

  final double price;
  final String currency;
  final DateTime at;
  final PriceSource source;
  final List<PricePoint> history;

  Map<String, dynamic> toCache() => {
        'price': price,
        'currency': currency,
        'at': at.toIso8601String(),
        'source': source.name,
        'history': [
          for (final p in history) [p.at.millisecondsSinceEpoch, p.price]
        ],
      };

  factory Quote.fromCache(Map<String, dynamic> m) => Quote(
        price: _num(m['price'])!,
        currency: m['currency'] as String,
        at: DateTime.parse(m['at'] as String),
        source: PriceSource.parse(m['source'] as String?),
        history: [
          for (final p in (m['history'] as List? ?? const []))
            PricePoint(
              DateTime.fromMillisecondsSinceEpoch((p as List)[0] as int),
              (p[1] as num).toDouble(),
            ),
        ],
      );
}
