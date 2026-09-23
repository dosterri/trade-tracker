import 'package:flutter_test/flutter_test.dart';
import 'package:trade_tracker/core/analytics.dart';
import 'package:trade_tracker/core/fx.dart';
import 'package:trade_tracker/core/import_plan.dart';
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/core/portfolio.dart';
import 'package:trade_tracker/core/tr_parser.dart';

Position pos(String id, AssetClass c, {String? isin}) => Position(
      id: id,
      assetClass: c,
      name: id,
      isin: isin,
      // Kursquelle "ls", damit der übergebene Kurs auch verwendet wird –
      // bei "manual" zählt nur der gespeicherte manuelle Kurs.
      priceSource: PriceSource.ls,
      sourceRef: '1',
    );

Txn tx(String pos, TxnSide side, double q, double p, String day) => Txn(
      id: '$pos-$day-${side.name}',
      positionId: pos,
      side: side,
      quantity: q,
      price: p,
      executedAt: DateTime.parse(day),
    );

PositionView view(Position p, List<Txn> txns, double? price) =>
    PositionView.build(
      position: p,
      txns: txns,
      quote: price == null
          ? null
          : Quote(
              price: price,
              currency: 'EUR',
              at: DateTime.now(),
              source: PriceSource.manual),
      fx: FxTable.eurOnly,
    );

void main() {
  group('Auswertung', () {
    final aktie = pos('SAP', AssetClass.stock);
    final krypto = pos('BTC', AssetClass.crypto);

    final views = [
      // offen: 10 Stück zu 100 gekauft, steht bei 120 → +200
      view(aktie, [tx('SAP', TxnSide.buy, 10, 100, '2026-01-01')], 120),
      // geschlossen mit Gewinn, 100 Tage gehalten
      view(
        pos('ALV', AssetClass.stock),
        [
          tx('ALV', TxnSide.buy, 10, 100, '2026-01-01'),
          tx('ALV', TxnSide.sell, 10, 150, '2026-04-11'),
        ],
        150,
      ),
      // geschlossen mit Verlust, 10 Tage gehalten
      view(
        krypto,
        [
          tx('BTC', TxnSide.buy, 1, 1000, '2026-01-01'),
          tx('BTC', TxnSide.sell, 1, 800, '2026-01-11'),
        ],
        800,
      ),
    ];

    final a = Analytics.of(views);

    test('Gewinn/Verlust-Quote und Haltedauer', () {
      expect(a.trades.closedCount, 2);
      expect(a.trades.wins, 1);
      expect(a.trades.losses, 1);
      expect(a.trades.winRate, 0.5);
      expect(a.trades.grossProfit, closeTo(500, 1e-9));
      expect(a.trades.grossLoss, closeTo(200, 1e-9));
      expect(a.trades.netEur, closeTo(300, 1e-9));
      expect(a.trades.profitFactor, closeTo(2.5, 1e-9));
      expect(a.trades.bestEur, closeTo(500, 1e-9));
      expect(a.trades.worstEur, closeTo(-200, 1e-9));
      // Toleranz wegen der Sommerzeitumstellung im Haltezeitraum.
      expect(a.trades.avgWinnerHoldingDays, closeTo(100, 0.1));
      expect(a.trades.avgLoserHoldingDays, closeTo(10, 0.1));
      expect(a.trades.avgHoldingDays, closeTo(55, 0.1));
    });

    test('Aufteilung nach Anlageklasse', () {
      final stocks = a.byClass.firstWhere((c) => c.assetClass == AssetClass.stock);
      expect(stocks.openCount, 1);
      expect(stocks.valueEur, closeTo(1200, 1e-9));
      expect(stocks.unrealizedEur, closeTo(200, 1e-9));
      expect(stocks.realizedEur, closeTo(500, 1e-9));
      expect(stocks.unrealizedPct, closeTo(0.2, 1e-9));

      final crypto = a.byClass.firstWhere((c) => c.assetClass == AssetClass.crypto);
      expect(crypto.openCount, 0);
      expect(crypto.realizedEur, closeTo(-200, 1e-9));
    });

    test('leeres Portfolio stürzt nicht ab', () {
      final empty = Analytics.of(const []);
      expect(empty.trades.winRate, isNull);
      expect(empty.trades.profitFactor, isNull);
      expect(empty.byClass, isEmpty);
      expect(empty.summary.valueEur, 0);
    });
  });

  group('Importplanung', () {
    TrDocument doc({
      TxnSide side = TxnSide.buy,
      String isin = 'DE0007164600',
      double fees = 1,
      double taxes = 0,
      List<TrItem>? items,
    }) =>
        TrDocument(
          type: TrDocType.settlement,
          side: side,
          executedAt: DateTime(2026, 5, 2, 10),
          items: items ??
              [
                TrItem(
                    name: 'SAP SE',
                    isin: isin,
                    quantity: 10,
                    price: 100,
                    amount: 1000)
              ],
          fees: fees,
          taxes: taxes,
          executionId: 'exec-1',
        );

    test('Kauf ohne passende Position → neue Position', () {
      final plan = planImport(doc(), 'a.pdf',
          positions: const [], existingRefs: const {}).single;
      expect(plan.status, ImportStatus.newPosition);
      expect(plan.txn!.quantity, 10);
      expect(plan.txn!.fees, 1);
      expect(plan.txn!.externalRef, 'tr:exec-1:buy:DE0007164600');
    });

    test('Kauf mit passender ISIN wird zugeordnet', () {
      final p = pos('x', AssetClass.stock, isin: 'DE0007164600');
      final plan =
          planImport(doc(), 'a.pdf', positions: [p], existingRefs: const {}).single;
      expect(plan.status, ImportStatus.ready);
      expect(plan.target?.id, 'x');
    });

    test('bereits importierte Ausführung wird erkannt', () {
      final plan = planImport(doc(), 'a.pdf',
          positions: const [],
          existingRefs: {'tr:exec-1:buy:DE0007164600'}).single;
      expect(plan.status, ImportStatus.duplicate);
      expect(plan.canImport, isFalse);
    });

    test('Verkauf ohne Position wird abgelehnt statt falsch gebucht', () {
      final plan = planImport(doc(side: TxnSide.sell), 'a.pdf',
          positions: const [], existingRefs: const {}).single;
      expect(plan.status, ImportStatus.skip);
      expect(plan.reason, contains('Verkauf ohne passende Position'));
    });

    test('Gebühren und Steuern werden anteilig verteilt', () {
      final d = doc(fees: 2, taxes: 30, items: const [
        TrItem(name: 'A', isin: 'DE0007164600', quantity: 1, price: 750, amount: 750),
        TrItem(name: 'B', isin: 'DE0008404005', quantity: 1, price: 250, amount: 250),
      ]);
      final plans =
          planImport(d, 'a.pdf', positions: const [], existingRefs: const {});
      expect(plans.length, 2);
      expect(plans.first.txn!.fees, closeTo(1.5, 1e-9));
      expect(plans.first.txn!.taxes, closeTo(22.5, 1e-9));
      expect(plans.last.txn!.fees, closeTo(0.5, 1e-9));
      // Eindeutige Kennzeichen je Wertpapier
      expect(plans.first.txn!.externalRef, isNot(plans.last.txn!.externalRef));
    });

    test('Kosteninformation ergibt keinen Import', () {
      const d = TrDocument(type: TrDocType.costInfo, warnings: ['nur Kosten']);
      final plan =
          planImport(d, 'k.pdf', positions: const [], existingRefs: const {}).single;
      expect(plan.status, ImportStatus.skip);
      expect(plan.canImport, isFalse);
    });

    test('Vorschlag für neue Position übernimmt ISIN und Kurs', () {
      const item = TrItem(
          name: 'SAP SE', isin: 'DE0007164600', quantity: 1, price: 182.5, amount: 182.5);
      final p = positionFromImport(item);
      expect(p.isin, 'DE0007164600');
      expect(p.manualPrice, 182.5);
      expect(p.priceSource, PriceSource.manual);
    });
  });
}
