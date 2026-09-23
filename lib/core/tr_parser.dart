import 'models.dart';

/// Liest Trade-Republic-Abrechnungen aus dem Text einer PDF-Datei.
///
/// Bewusst ohne Flutter-Abhängigkeit: Die Textextraktion passiert in der App
/// (pdfrx/pdfium), hier wird nur noch der Text ausgewertet – so ist alles
/// testbar.
///
/// Wichtig: Je nach Textextraktion stehen Beschriftung und Wert in derselben
/// Zeile ("Abwicklungspauschale -1,00 EUR") oder untereinander. Der Parser
/// normalisiert beides auf eine Zeile und kommt so mit beiden Varianten klar.

enum TrDocType {
  settlement('Wertpapierabrechnung'),
  costInfo('Kosteninformation'),
  dividend('Dividende/Ausschüttung'),
  unknown('Unbekanntes Dokument');

  const TrDocType(this.label);
  final String label;
}

class TrItem {
  const TrItem({
    required this.name,
    required this.isin,
    required this.quantity,
    required this.price,
    required this.amount,
    this.currency = 'EUR',
  });

  final String name;
  final String isin;
  final double quantity;
  final double price;

  /// Bruttobetrag der Position (Stückzahl × Kurs).
  final double amount;
  final String currency;
}

class TrDocument {
  const TrDocument({
    required this.type,
    this.side,
    this.executedAt,
    this.items = const [],
    this.fees = 0,
    this.taxes = 0,
    this.total,
    this.orderId,
    this.executionId,
    this.warnings = const [],
  });

  final TrDocType type;
  final TxnSide? side;
  final DateTime? executedAt;
  final List<TrItem> items;

  /// Gebühren gesamt (positiv), z. B. Abwicklungspauschale.
  final double fees;

  /// Einbehaltene Steuern gesamt (positiv).
  final double taxes;

  /// Abrechnungsbetrag laut Dokument (zur Kontrolle).
  final double? total;
  final String? orderId;
  final String? executionId;
  final List<String> warnings;

  /// Kennzeichen zum Erkennen doppelter Importe.
  String? get externalRef {
    if (items.isEmpty || side == null) return null;
    final base = executionId ?? orderId;
    if (base == null) return null;
    return 'tr:$base:${side!.name}:${items.first.isin}';
  }

  bool get isImportable =>
      type == TrDocType.settlement &&
      side != null &&
      items.isNotEmpty &&
      executedAt != null;
}

// --- Zahlen ----------------------------------------------------------------

/// Geldbetrag: "1.234,56 EUR", "-1,00 €", "438,24". Ohne Komma nur mit Währung,
/// damit Depotnummern und Jahreszahlen nicht als Beträge gelesen werden.
final _moneyRe = RegExp(
  r'(-?\d{1,3}(?:\.\d{3})*,\d+)\s*(EUR|USD|CHF|GBP|€|€)?'
  r'|(-?\d{1,3}(?:\.\d{3})*)\s*(EUR|USD|CHF|GBP|€|€)',
);

class _Money {
  const _Money(this.value, this.currency);
  final double value;
  final String? currency;
}

double _german(String s) =>
    double.parse(s.replaceAll('.', '').replaceAll(',', '.'));

List<_Money> _moneyIn(String line) {
  final out = <_Money>[];
  for (final m in _moneyRe.allMatches(line)) {
    final raw = m.group(1) ?? m.group(3);
    if (raw == null) continue;
    final cur = m.group(2) ?? m.group(4);
    out.add(_Money(
      _german(raw),
      cur == null ? null : (cur == '€' || cur == '€' ? 'EUR' : cur),
    ));
  }
  return out;
}

/// Ganze Zeile ist nur ein Betrag → gehört zur Beschriftung darüber.
bool _isOnlyMoney(String line) {
  final s = line.trim();
  if (s.isEmpty) return false;
  final m = _moneyRe.firstMatch(s);
  if (m == null || m.start != 0 || m.end != s.length) return false;
  return s.contains(',') || RegExp(r'[€EURUSDCHFGBP€]').hasMatch(s);
}

/// Stückzahl: "0,638839 Stk." oder englisch "0.638839 Stk."
double? _quantity(String raw) {
  final s = raw.trim();
  if (s.contains(',')) return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
  return double.tryParse(s);
}

DateTime? _date(String d, [String? time]) {
  final m = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(d.trim());
  if (m == null) return null;
  final t = time == null ? null : RegExp(r'(\d{1,2}):(\d{2})').firstMatch(time);
  return DateTime(
    int.parse(m.group(3)!),
    int.parse(m.group(2)!),
    int.parse(m.group(1)!),
    t == null ? 12 : int.parse(t.group(1)!),
    t == null ? 0 : int.parse(t.group(2)!),
  );
}

const _feeLabels = [
  'abwicklungspauschale',
  'abwicklungskostenpauschale',
  'fremdkostenpauschale',
  'handelsplatzgebühr',
  'provision',
  'gebühr',
];

const _taxLabels = [
  'kapitalertragsteuer',
  'kirchensteuer',
  'solidaritätszuschlag',
  'quellensteuer',
];

/// Führt Beschriftungszeile und darunter stehenden Betrag zusammen, damit
/// beide Textvarianten gleich aussehen.
List<String> _normalize(String text) {
  final raw = [
    for (final l in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n'))
      l.trim(),
  ]..removeWhere((l) => l.isEmpty);

  final out = <String>[];
  for (var i = 0; i < raw.length; i++) {
    var line = raw[i];
    if (!_isOnlyMoney(line)) {
      while (i + 1 < raw.length && _isOnlyMoney(raw[i + 1])) {
        line = '$line ${raw[i + 1]}';
        i++;
      }
    }
    out.add(line);
  }
  return out;
}

TrDocument parseTradeRepublicPdf(String text) {
  final lines = _normalize(text);
  final joined = lines.join('\n');
  final lower = joined.toLowerCase();
  final warnings = <String>[];

  TrDocType type;
  if (lower.contains('wertpapierabrechnung')) {
    type = TrDocType.settlement;
  } else if (lower.contains('kosteninformation')) {
    type = TrDocType.costInfo;
  } else if (lower.contains('dividende') || lower.contains('ausschüttung')) {
    type = TrDocType.dividend;
  } else {
    type = TrDocType.unknown;
  }

  // "… Verkauf am 14.09.2026, um 16:03 Uhr …"
  TxnSide? side;
  DateTime? executedAt;
  final order = RegExp(
    r'(Kauf|Verkauf|Sparplanausführung)[^\n]*?am (\d{2}\.\d{2}\.\d{4})(?:,? um (\d{1,2}:\d{2}))?',
    caseSensitive: false,
  ).firstMatch(joined);
  if (order != null) {
    side = order.group(1)!.toLowerCase() == 'verkauf' ? TxnSide.sell : TxnSide.buy;
    executedAt = _date(order.group(2)!, order.group(3));
  } else if (lower.contains('wertpapierverkauf') || lower.contains('verkauf')) {
    side = TxnSide.sell;
  } else if (lower.contains('wertpapierkauf') || lower.contains('kauf')) {
    side = TxnSide.buy;
  }

  /// Wert hinter einer Beschriftung – gleiche Zeile oder Zeile darunter.
  String? after(String label) {
    final re = RegExp('^$label\\s+(.+)\$', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      final m = re.firstMatch(lines[i]);
      if (m != null) return m.group(1)!.trim();
      if (lines[i].toLowerCase() == label && i + 1 < lines.length) {
        return lines[i + 1];
      }
    }
    return null;
  }

  executedAt ??= _date(after('datum') ?? '');
  final orderId = after('auftrag')?.split(RegExp(r'\s')).first;
  final executionId = after('ausführung')?.split(RegExp(r'\s')).first;

  // --- Positionen
  final items = <TrItem>[];
  final isinRe = RegExp(r'ISIN:\s*([A-Z]{2}[A-Z0-9]{9}\d)');
  final qtyRe = RegExp(r'(-?[\d.,]+)\s*(?:Stk\.|Stück|St\.)');

  for (var i = 0; i < lines.length; i++) {
    final isinMatch = isinRe.firstMatch(lines[i]);
    if (isinMatch == null) continue;
    final isin = isinMatch.group(1)!;

    final before = lines[i].substring(0, isinMatch.start).trim();
    final name = before.isNotEmpty
        ? before
        : (i > 0 ? lines[i - 1] : '');

    double? qty, price, amount;
    String currency = 'EUR';
    // Zeile mit der ISIN und die nächsten Zeilen nach Zahlen absuchen.
    for (var j = i; j < lines.length && j < i + 6; j++) {
      final part = j == i ? lines[j].substring(isinMatch.end) : lines[j];
      if (j > i && isinRe.hasMatch(part)) break; // nächste Position
      final q = qtyRe.firstMatch(part);
      if (q != null && qty == null) qty = _quantity(q.group(1)!);
      for (final m in _moneyIn(q == null ? part : part.substring(q.end))) {
        currency = m.currency ?? currency;
        if (price == null) {
          price = m.value; // erster Betrag: Stückkurs
          continue;
        }
        amount ??= m.value; // zweiter Betrag: Gesamtbetrag der Position
      }
      if (qty != null && amount != null) break;
    }

    if (qty == null || qty <= 0) {
      warnings.add('Stückzahl für $isin nicht gefunden.');
      continue;
    }
    // Kosteninformationen nennen nur den Gesamtbetrag, keinen Stückkurs.
    if (amount == null && price != null) {
      amount = price;
      price = price / qty;
    }
    if (price == null) {
      warnings.add('Kurs für $isin nicht gefunden.');
      continue;
    }
    items.add(TrItem(
      name: name,
      isin: isin,
      quantity: qty,
      price: price,
      amount: amount ?? qty * price,
      currency: currency,
    ));
  }

  // --- Gebühren und Steuern: nur der Abschnitt ABRECHNUNG, sonst zählt die
  //     Steuerberechnung auf Seite 2 doppelt.
  var fees = 0.0, taxes = 0.0;
  double? total;

  void scan(int from, int to, {bool withTaxes = true}) {
    for (var i = from; i < to && i < lines.length; i++) {
      final line = lines[i];
      final money = _moneyIn(line);
      if (money.isEmpty) continue;
      final label = line.substring(0, _moneyRe.firstMatch(line)!.start).toLowerCase();
      final value = money.first.value;
      if (_feeLabels.any(label.contains)) fees += value.abs();
      if (withTaxes && _taxLabels.any(label.contains)) taxes += value.abs();
      if (label.trim() == 'gesamt') total ??= value.abs();
    }
  }

  final start = lines.indexWhere((l) => l.toUpperCase().startsWith('ABRECHNUNG'));
  if (start >= 0) {
    var end = lines.indexWhere((l) => l.toUpperCase().startsWith('BUCHUNG'), start + 1);
    if (end < 0) end = lines.length;
    total = null;
    scan(start, end);
  } else if (type == TrDocType.costInfo) {
    // Kosteninformation: nur der obere Kostenblock, nicht die Aufteilung.
    final costStart = lines.indexWhere((l) => l.toUpperCase().startsWith('KOSTEN DES'));
    var costEnd = lines.indexWhere(
        (l) => l.toUpperCase().startsWith('AUFTEILUNG'), costStart + 1);
    if (costEnd < 0) costEnd = lines.length;
    if (costStart >= 0) scan(costStart, costEnd, withTaxes: false);
  }

  if (type == TrDocType.settlement && items.isEmpty) {
    warnings.add('Keine Position gefunden – unbekannter Dokumentaufbau.');
  }
  if (type == TrDocType.costInfo) {
    warnings.add('Kosteninformation: enthält keine Ausführung, nur die '
        'voraussichtlichen Kosten.');
  }
  if (type == TrDocType.dividend) {
    warnings.add('Dividendenabrechnungen werden noch nicht importiert.');
  }

  return TrDocument(
    type: type,
    side: side,
    executedAt: executedAt,
    items: items,
    fees: fees,
    taxes: taxes,
    total: total,
    orderId: orderId,
    executionId: executionId,
    warnings: warnings,
  );
}
