import 'package:flutter_test/flutter_test.dart';
import 'package:trade_tracker/core/fx.dart';
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/core/portfolio.dart';

void main() {
  group('FxTable', () {
    final fx = FxTable.fromFrankfurter(
        '{"amount":1.0,"base":"EUR","date":"2026-09-22","rates":{"USD":1.1463,"CHF":0.9312}}');

    test('EUR ist immer 1', () {
      expect(fx.rate('EUR'), 1);
      expect(fx.toEur(50, 'EUR'), 50);
    });

    test('USD → EUR', () {
      expect(fx.toEur(114.63, 'USD'), closeTo(100, 1e-9));
      expect(fx.toEur(10, 'usd'), closeTo(10 / 1.1463, 1e-12));
    });

    test('unbekannte Währung → null', () {
      expect(fx.toEur(1, 'XYZ'), isNull);
      expect(fx.supports('XYZ'), isFalse);
    });

    test('Datum wird gelesen', () {
      expect(fx.date, DateTime(2026, 9, 22));
    });

    test('falsche Basis wird abgelehnt', () {
      expect(() => FxTable.fromFrankfurter('{"base":"USD","rates":{}}'),
          throwsFormatException);
    });

    test('Cache-Roundtrip', () {
      final c = FxTable.fromCache(fx.toCache());
      expect(c.rate('USD'), 1.1463);
    });
  });

  group('PositionView', () {
    Position pos({PriceSource src = PriceSource.ls, String ccy = 'EUR', double? manual,
            double? sl, double? tp}) =>
        Position(
          id: 'p',
          assetClass: AssetClass.stock,
          name: 'Test',
          currency: ccy,
          priceSource: src,
          sourceRef: '1',
          manualPrice: manual,
          manualPriceAt: manual == null ? null : DateTime.now(),
          stopLoss: sl,
          takeProfit: tp,
        );

    final txns = [
      Txn(
        id: 't',
        positionId: 'p',
        side: TxnSide.buy,
        quantity: 10,
        price: 100,
        fees: 0,
        executedAt: DateTime(2026, 1, 1),
      ),
    ];

    Quote quote(double price, [String ccy = 'EUR']) => Quote(
        price: price, currency: ccy, at: DateTime.now(), source: PriceSource.ls);

    test('unrealisierter Gewinn in EUR', () {
      final v = PositionView.build(
          position: pos(), txns: txns, quote: quote(120), fx: FxTable.eurOnly);
      expect(v.valueEur, closeTo(1200, 1e-9));
      expect(v.unrealizedEur, closeTo(200, 1e-9));
      expect(v.unrealizedPct, closeTo(0.2, 1e-9));
      expect(v.origin, PriceOrigin.live);
    });

    test('Kurs in Fremdwährung wird mit aktuellem FX umgerechnet', () {
      final fx = FxTable({'USD': 1.2});
      final v = PositionView.build(
          position: pos(), txns: txns, quote: quote(120, 'USD'), fx: fx);
      expect(v.valueEur, closeTo(1000, 1e-9));
      expect(v.unrealizedEur, closeTo(0, 1e-9));
    });

    test('fehlender FX-Kurs → keine Bewertung statt falscher Zahl', () {
      final v = PositionView.build(
          position: pos(), txns: txns, quote: quote(120, 'USD'), fx: FxTable.eurOnly);
      expect(v.valueEur, isNull);
      expect(PortfolioSummary.of([v]).missingPrices, 1);
    });

    test('Quelle gestört → manueller Kurs als Fallback', () {
      final v = PositionView.build(
          position: pos(manual: 90), txns: txns, quote: null, fx: FxTable.eurOnly);
      expect(v.origin, PriceOrigin.manualFallback);
      expect(v.unrealizedEur, closeTo(-100, 1e-9));
    });

    test('Stop-Loss und Take-Profit erkannt', () {
      final low = PositionView.build(
          position: pos(sl: 95, tp: 130), txns: txns, quote: quote(94), fx: FxTable.eurOnly);
      expect(low.stopLossHit, isTrue);
      expect(low.takeProfitHit, isFalse);
      final high = PositionView.build(
          position: pos(sl: 95, tp: 130), txns: txns, quote: quote(131), fx: FxTable.eurOnly);
      expect(high.takeProfitHit, isTrue);
    });

    test('Bestandsfehler wird angezeigt statt Absturz', () {
      final bad = [
        ...txns,
        Txn(
            id: 's',
            positionId: 'p',
            side: TxnSide.sell,
            quantity: 20,
            price: 1,
            executedAt: DateTime(2026, 2, 1)),
      ];
      final v = PositionView.build(
          position: pos(), txns: bad, quote: quote(1), fx: FxTable.eurOnly);
      expect(v.ledgerError, isNotNull);
    });

    test('Summe über Positionen', () {
      final a = PositionView.build(
          position: pos(), txns: txns, quote: quote(110), fx: FxTable.eurOnly);
      final s = PortfolioSummary.of([a, a]);
      expect(s.valueEur, closeTo(2200, 1e-9));
      expect(s.unrealizedEur, closeTo(200, 1e-9));
    });
  });
}
