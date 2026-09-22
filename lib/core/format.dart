import 'package:intl/intl.dart';

const _locale = 'de_DE';

final NumberFormat _eur =
    NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: 2);
final NumberFormat _pct = NumberFormat.decimalPatternDigits(
    locale: _locale, decimalDigits: 2);
final DateFormat _date = DateFormat('dd.MM.yyyy', _locale);
final DateFormat _dateTime = DateFormat('dd.MM. HH:mm', _locale);

String fmtEur(double? v, {bool signed = false}) {
  if (v == null) return '–';
  final s = _eur.format(v);
  return signed && v > 0 ? '+$s' : s;
}

String fmtPct(double? ratio) {
  if (ratio == null) return '–';
  final v = ratio * 100;
  return '${v > 0 ? '+' : ''}${_pct.format(v)} %';
}

/// Stückpreis: kleine Werte (Derivate, Krypto) mit mehr Nachkommastellen.
String fmtPrice(double? v, [String currency = 'EUR']) {
  if (v == null) return '–';
  final abs = v.abs();
  final digits = abs >= 100 ? 2 : (abs >= 1 ? 3 : (abs >= 0.01 ? 4 : 6));
  final f = NumberFormat.decimalPatternDigits(
      locale: _locale, decimalDigits: digits);
  return '${f.format(v)} ${currency == 'EUR' ? '€' : currency}';
}

/// Geldbetrag mit 2 Nachkommastellen in beliebiger Währung (z. B. Gebühren).
String fmtMoney(double? v, [String currency = 'EUR']) {
  if (v == null) return '–';
  if (currency == 'EUR') return fmtEur(v);
  return '${_pct.format(v)} $currency';
}

String fmtQty(double v) {
  final f = NumberFormat('#,##0.########', _locale);
  return f.format(v);
}

String fmtDate(DateTime? d) => d == null ? '–' : _date.format(d.toLocal());
String fmtDateTime(DateTime? d) =>
    d == null ? '–' : _dateTime.format(d.toLocal());

/// Liest Zahlen tolerant: "1.234,56", "1234.56", "1 234,5", "-0,5".
/// Gibt null zurück, wenn keine gültige Zahl erkennbar ist.
double? parseNum(String? input) {
  if (input == null) return null;
  var s = input.trim().replaceAll(RegExp(r'[\s €]'), '');
  if (s.isEmpty) return null;
  final hasComma = s.contains(',');
  final hasDot = s.contains('.');
  if (hasComma && hasDot) {
    // Das zuletzt vorkommende Zeichen ist das Dezimaltrennzeichen.
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    s = s.replaceAll(',', '.');
  } else if (hasDot && RegExp(r'^-?\d{1,3}(\.\d{3}){2,}$').hasMatch(s)) {
    // "1.234.567" → Tausendertrennung. Ein einzelner Punkt ("1.234") bleibt
    // bewusst ein Dezimalpunkt, weil Derivatekurse oft so aussehen.
    s = s.replaceAll('.', '');
  }
  if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) return null;
  return double.tryParse(s);
}
