import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/core/tr_parser.dart';

// Die Testdaten sind anonymisierte Textauszüge echter Trade-Republic-PDFs
// (Name, Adresse, IBAN und Depotnummer ersetzt). Originale gehören nicht ins Repo.
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  // Zwei Textvarianten desselben PDFs: pdfium (in der App) schreibt
  // Beschriftung und Wert in eine Zeile, andere Extraktoren untereinander.
  for (final (variante, datei) in [
    ('Werte untereinander', 'tr_wertpapierabrechnung_verkauf.txt'),
    ('Werte in einer Zeile (pdfium)', 'tr_pdfium_abrechnung_verkauf.txt'),
  ]) {
  group('Wertpapierabrechnung Verkauf – $variante', () {
    late TrDocument doc;

    setUpAll(() {
      doc = parseTradeRepublicPdf(fixture(datei));
    });

    test('Dokumenttyp und Richtung', () {
      expect(doc.type, TrDocType.settlement);
      expect(doc.side, TxnSide.sell);
      expect(doc.isImportable, isTrue);
    });

    test('Ausführungszeitpunkt inkl. Uhrzeit', () {
      expect(doc.executedAt, DateTime(2026, 9, 14, 16, 3));
    });

    test('Position mit ISIN, Stückzahl und Kurs', () {
      final item = doc.items.single;
      expect(item.isin, 'IE00BKVD2N49');
      expect(item.name, 'Seagate Technology');
      expect(item.quantity, closeTo(0.638839, 1e-9));
      expect(item.price, 686.00);
      expect(item.amount, 438.24);
      expect(item.currency, 'EUR');
    });

    test('Gebühren und Steuern – Steuerseite zählt nicht doppelt', () {
      expect(doc.fees, closeTo(1.00, 1e-9));
      // 76,66 + 6,13 + 4,21 = 87,00 (nur aus dem Abschnitt ABRECHNUNG)
      expect(doc.taxes, closeTo(87.00, 1e-9));
      expect(doc.total, closeTo(350.24, 1e-9));
    });

    test('Kontrolle: Betrag − Gebühren − Steuern ergibt die Gutschrift', () {
      final net = doc.items.single.amount - doc.fees - doc.taxes;
      expect(net, closeTo(doc.total!, 0.01));
    });

    test('Kennzeichen gegen doppelten Import', () {
      expect(doc.orderId, '50f2-21f6');
      expect(doc.executionId, 'e096-725b');
      expect(doc.externalRef, 'tr:e096-725b:sell:IE00BKVD2N49');
    });

    test('keine Warnungen', () {
      expect(doc.warnings, isEmpty);
    });
  });
  }

  for (final (variante, datei) in [
    ('Werte untereinander', 'tr_kosteninformation_verkauf.txt'),
    ('pdfium', 'tr_pdfium_kosteninformation.txt'),
  ]) {
  group('Kosteninformation – $variante', () {
    late TrDocument doc;

    setUpAll(() {
      doc = parseTradeRepublicPdf(fixture(datei));
    });

    test('wird erkannt und nicht als Ausführung importiert', () {
      expect(doc.type, TrDocType.costInfo);
      expect(doc.isImportable, isFalse);
      expect(doc.warnings, isNotEmpty);
    });

    test('liest trotzdem Wertpapier und Stückzahl', () {
      expect(doc.items.single.isin, 'IE00BKVD2N49');
      expect(doc.items.single.quantity, closeTo(0.638839, 1e-9));
      expect(doc.side, TxnSide.sell);
      expect(doc.fees, closeTo(1.00, 1e-9));
    });
  });
  }

  group('Robustheit', () {
    test('leerer Text → unbekannt statt Absturz', () {
      final doc = parseTradeRepublicPdf('');
      expect(doc.type, TrDocType.unknown);
      expect(doc.isImportable, isFalse);
      expect(doc.items, isEmpty);
    });

    test('fremdes PDF wird nicht importiert', () {
      final doc = parseTradeRepublicPdf('Rechnung Nr. 5\nBetrag 20,00 EUR');
      expect(doc.type, TrDocType.unknown);
      expect(doc.isImportable, isFalse);
    });

    test('Kauf mit Tausenderpunkt und mehreren Positionen', () {
      const text = '''
WERTPAPIERABRECHNUNG
ÜBERSICHT
Market-Order Kauf am 03.02.2026, um 09:15 Uhr mit Bestpreis
AUFTRAG
aaaa-1111
AUSFÜHRUNG
bbbb-2222
POSITION
ANZAHL
PREIS
BETRAG
SAP SE
ISIN: DE0007164600
10 Stk.
182,50 EUR
1.825,00 EUR
Allianz SE
ISIN: DE0008404005
2 Stk.
350,00 EUR
700,00 EUR
GESAMT
2.525,00 EUR
ABRECHNUNG
POSITION
BETRAG
Fremdkostenpauschale
-1,00 EUR
GESAMT
-2.526,00 EUR
BUCHUNG
''';
      final doc = parseTradeRepublicPdf(text);
      expect(doc.side, TxnSide.buy);
      expect(doc.executedAt, DateTime(2026, 2, 3, 9, 15));
      expect(doc.items.length, 2);
      expect(doc.items.first.price, 182.50);
      expect(doc.items.first.amount, 1825.00);
      expect(doc.items.last.isin, 'DE0008404005');
      expect(doc.fees, closeTo(1.00, 1e-9));
      expect(doc.taxes, 0);
    });

    test('Dividende wird erkannt, aber nicht importiert', () {
      final doc = parseTradeRepublicPdf('DIVIDENDE\nSAP SE\nISIN: DE0007164600');
      expect(doc.type, TrDocType.dividend);
      expect(doc.isImportable, isFalse);
    });
  });
}
