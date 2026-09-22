import 'package:flutter_test/flutter_test.dart';
import 'package:trade_tracker/core/fifo.dart';
import 'package:trade_tracker/core/models.dart';

Txn buy(double qty, double price, String day, {double fees = 0, double fx = 1}) => Txn(
      id: 'b$day$qty',
      positionId: 'p',
      side: TxnSide.buy,
      quantity: qty,
      price: price,
      fees: fees,
      fxRate: fx,
      executedAt: DateTime.parse(day),
    );

Txn sell(double qty, double price, String day,
        {double fees = 0, double taxes = 0, double fx = 1}) =>
    Txn(
      id: 's$day$qty',
      positionId: 'p',
      side: TxnSide.sell,
      quantity: qty,
      price: price,
      fees: fees,
      taxes: taxes,
      fxRate: fx,
      executedAt: DateTime.parse(day),
    );

void main() {
  group('FIFO', () {
    test('einfacher Kauf und Verkauf mit Gebühren', () {
      final r = computeLedger([
        buy(10, 100, '2026-01-02', fees: 1),
        sell(10, 110, '2026-02-02', fees: 1, taxes: 2.5),
      ]);
      // Kosten 1001, Erlös 1099 → +98
      expect(r.realizedEur, closeTo(98, 1e-9));
      expect(r.feesEur, closeTo(2, 1e-9));
      expect(r.taxesEur, closeTo(2.5, 1e-9));
      expect(r.realizedNetEur, closeTo(95.5, 1e-9));
      expect(r.openQty, 0);
      expect(r.isClosed, isTrue);
      expect(r.closed.single.holding.inDays, 31);
    });

    test('Teilverkauf verbraucht zuerst den ältesten Posten', () {
      final r = computeLedger([
        buy(10, 100, '2026-01-01'),
        buy(10, 200, '2026-01-10'),
        sell(15, 150, '2026-02-01'),
      ]);
      // 10 × (150−100) + 5 × (150−200) = 500 − 250
      expect(r.realizedEur, closeTo(250, 1e-9));
      expect(r.openQty, closeTo(5, 1e-9));
      expect(r.avgOpenPrice, closeTo(200, 1e-9));
      expect(r.openCostEur, closeTo(1000, 1e-9));
      expect(r.closed.length, 2);
      expect(r.isClosed, isFalse);
    });

    test('Kaufgebühren werden anteilig mit verkauft', () {
      final r = computeLedger([
        buy(4, 50, '2026-01-01', fees: 2),
        sell(1, 50, '2026-01-02'),
      ]);
      expect(r.realizedEur, closeTo(-0.5, 1e-9));
      expect(r.openCostEur, closeTo(151.5, 1e-9));
    });

    test('Reihenfolge der Eingabe egal – sortiert nach Datum', () {
      final r = computeLedger([
        sell(5, 30, '2026-03-01'),
        buy(5, 20, '2026-01-01'),
      ]);
      expect(r.realizedEur, closeTo(50, 1e-9));
    });

    test('Kauf und Verkauf zur selben Zeit: Kauf zuerst', () {
      final r = computeLedger([
        sell(1, 12, '2026-01-01T10:00:00'),
        buy(1, 10, '2026-01-01T10:00:00'),
      ]);
      expect(r.realizedEur, closeTo(2, 1e-9));
    });

    test('Leerverkauf / zu viel verkauft → Fehler', () {
      expect(
        () => computeLedger([buy(1, 10, '2026-01-01'), sell(2, 10, '2026-01-02')]),
        throwsA(isA<LedgerException>()),
      );
    });

    test('Krypto-Bruchteile ohne Rundungsrest', () {
      final r = computeLedger([
        buy(0.1, 60000, '2026-01-01'),
        buy(0.2, 60000, '2026-01-02'),
        sell(0.3, 70000, '2026-01-03'),
      ]);
      expect(r.openQty, lessThan(qtyEpsilon));
      expect(r.openLots, isEmpty);
      expect(r.realizedEur, closeTo(3000, 1e-6));
    });

    test('Fremdwährung: FX zum Kauf- und Verkaufszeitpunkt', () {
      final r = computeLedger([
        buy(10, 100, '2026-01-01', fx: 1.25), // 1000 USD = 800 EUR
        sell(10, 100, '2026-02-01', fx: 1.0), // 1000 USD = 1000 EUR
      ]);
      // Kursgewinn 0 USD, aber +200 EUR Währungsgewinn
      expect(r.realizedEur, closeTo(200, 1e-9));
    });

    test('Ungültige Stückzahl → Fehler', () {
      expect(() => computeLedger([buy(0, 10, '2026-01-01')]),
          throwsA(isA<LedgerException>()));
    });
  });
}
