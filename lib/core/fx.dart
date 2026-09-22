import 'dart:convert';

/// Wechselkurse mit Basis EUR: [perEur] = Einheiten Fremdwährung je 1 EUR.
class FxTable {
  FxTable(Map<String, double> perEur, {this.date})
      : perEur = {...perEur, 'EUR': 1.0};

  final Map<String, double> perEur;
  final DateTime? date;

  static final FxTable eurOnly = FxTable(const {});

  bool supports(String currency) => perEur.containsKey(currency.toUpperCase());

  /// Einheiten [currency] je 1 EUR, oder null falls unbekannt.
  double? rate(String currency) => perEur[currency.toUpperCase()];

  /// Rechnet [amount] in [currency] nach EUR um; null wenn Kurs fehlt.
  double? toEur(double amount, String currency) {
    final r = rate(currency);
    if (r == null || r <= 0) return null;
    return amount / r;
  }

  /// Parst eine Frankfurter-Antwort (`/v1/latest?base=EUR`).
  factory FxTable.fromFrankfurter(String body) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    if ((m['base'] as String?)?.toUpperCase() != 'EUR') {
      throw const FormatException('Basiswährung ist nicht EUR');
    }
    final rates = (m['rates'] as Map<String, dynamic>)
        .map((k, v) => MapEntry(k.toUpperCase(), (v as num).toDouble()));
    return FxTable(rates, date: DateTime.tryParse(m['date'] as String? ?? ''));
  }

  Map<String, dynamic> toCache() =>
      {'date': date?.toIso8601String(), 'rates': perEur};

  factory FxTable.fromCache(Map<String, dynamic> m) => FxTable(
        (m['rates'] as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        date: DateTime.tryParse(m['date'] as String? ?? ''),
      );
}
