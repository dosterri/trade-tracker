import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trade_tracker/core/fx.dart';
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/core/notifications.dart';
import 'package:trade_tracker/data/quote_sources.dart';
import 'package:trade_tracker/data/repository.dart';
import 'package:trade_tracker/state/app_scope.dart';
import 'package:trade_tracker/state/app_state.dart';
import 'package:trade_tracker/ui/home_page.dart';
import 'package:trade_tracker/ui/analytics_page.dart';
import 'package:trade_tracker/ui/import_page.dart';
import 'package:trade_tracker/ui/notifications_page.dart';
import 'package:trade_tracker/ui/position_detail.dart';
import 'package:trade_tracker/ui/position_form.dart';
import 'package:trade_tracker/ui/theme.dart';

/// Repository ohne Netzwerk mit festen Beispieldaten.
class FakeRepo extends Repository {
  FakeRepo()
      : super(SupabaseClient('http://localhost', 'test',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final positions = [
    const Position(
        id: 'sap', assetClass: AssetClass.stock, name: 'SAP SE',
        isin: 'DE0007164600', priceSource: PriceSource.ls, sourceRef: '34313',
        stopLoss: 150, takeProfit: 250),
    const Position(
        id: 'turbo', assetClass: AssetClass.derivative,
        name: 'J.P. MORGAN SE TURBOS O.END NVIDIA 240,0 mit sehr langem Namen',
        isin: 'DE000JY5HEJ7', priceSource: PriceSource.manual, manualPrice: 0.0123,
        derivativeType: DerivativeType.koShort, barrier: 240, ratio: 0.1),
    const Position(
        id: 'btc', assetClass: AssetClass.crypto, name: 'Bitcoin',
        symbol: 'bitcoin', priceSource: PriceSource.coingecko, sourceRef: 'bitcoin'),
    const Position(
        id: 'aapl', assetClass: AssetClass.stock, name: 'Apple (USD)',
        currency: 'USD', priceSource: PriceSource.manual, manualPrice: 230),
    const Position(
        id: 'old', assetClass: AssetClass.etf, name: 'MSCI World (geschlossen)',
        priceSource: PriceSource.manual),
  ];

  Txn t(String pos, TxnSide side, double q, double p, String d, {double fx = 1}) => Txn(
      id: '$pos$d$side', positionId: pos, side: side, quantity: q, price: p,
      fees: 1, fxRate: fx, executedAt: DateTime.parse(d));

  @override
  Future<PortfolioData> loadAll() async => PortfolioData(
        positions: positions,
        txns: [
          t('sap', TxnSide.buy, 12, 170, '2026-05-02'),
          t('turbo', TxnSide.buy, 5000, 0.02, '2026-09-01'),
          t('btc', TxnSide.buy, 0.05, 60000, '2026-03-03'),
          t('aapl', TxnSide.buy, 10, 200, '2026-01-10', fx: 1.1),
          t('old', TxnSide.buy, 10, 100, '2025-01-10'),
          t('old', TxnSide.sell, 10, 120, '2026-02-10'),
        ],
        snapshots: const {},
      );

  @override
  Future<void> insertSnapshots(List<Map<String, dynamic>> rows) async {}

  NotificationSettings settings = const NotificationSettings(
      telegramEnabled: true, telegramChatId: '12345678');

  @override
  Future<NotificationSettings?> loadNotificationSettings() async => settings;

  @override
  Future<NotificationSettings> saveNotificationSettings(
      NotificationSettings s, String userId) async {
    settings = s;
    return s;
  }

  @override
  Future<List<AlertEvent>> loadAlertEvents({int limit = 30}) async => [
        AlertEvent(
            id: 1,
            kind: 'up',
            message: '📈 SAP SE +10,20 % – Kurs 187,40 €',
            at: DateTime(2026, 9, 22, 15, 45),
            delivered: const ['telegram']),
      ];

  @override
  Future<BackendRun?> lastBackendRun() async =>
      BackendRun(kind: 'check', at: DateTime.now(), minutesAgo: 12);
  @override
  Future<void> writeCache({
    required List<Position> positions,
    required List<Txn> txns,
    required Map<String, Quote> quotes,
    required FxTable fx,
  }) async {}
}

final mockHttp = MockClient((req) async {
  final u = req.url.toString();
  if (u.contains('frankfurter')) {
    return http.Response('{"base":"EUR","date":"2026-09-22","rates":{"USD":1.15}}', 200);
  }
  if (u.contains('ls-tc.de')) {
    return http.Response(
        '{"series":{"intraday":{"data":[[1790060580000,182.41],[1790062000000,181.0],'
        '[1790064000000,183.2]]}}}',
        200);
  }
  if (u.contains('coingecko')) {
    return http.Response('{"prices":[[1790000000000,74000],[1790003600000,75447]]}', 200);
  }
  return http.Response('nope', 404);
});

Future<AppState> pumpApp(WidgetTester tester, Size size, Widget Function() home) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(repo: FakeRepo(), quotes: QuoteService(client: mockHttp));
  await tester.pumpWidget(AppScope(
    state: state,
    child: MaterialApp(
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.dark,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(builder: (_) => home()),
    ),
  ));
  await tester.runAsync(() async {
    await state.load();
    await state.refreshQuotes();
  });
  await tester.pumpAndSettle();
  return state;
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  for (final (label, size) in [
    ('iPhone', const Size(390, 844)),
    ('Windows breit', const Size(1400, 900)),
  ]) {
    testWidgets('Startseite rendert ohne Überlauf ($label)', (tester) async {
      final state = await pumpApp(tester, size, () => const HomePage());
      expect(find.text('SAP SE'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(state.views.firstWhere((v) => v.id == 'sap').price, 183.2);
      expect(state.views.firstWhere((v) => v.id == 'aapl').valueEur, closeTo(2000, 1e-6));

      state.toggleCompact();
      await tester.pumpAndSettle();
      state.setFilter(PositionFilter.closed);
      await tester.pumpAndSettle();
      expect(find.text('MSCI World (geschlossen)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Detailseite rendert ($label)', (tester) async {
      await pumpApp(tester, size, () => const PositionDetailPage(positionId: 'turbo'));
      await tester.scrollUntilVisible(find.text('Knock-out-Schwelle'), 200);
      await tester.scrollUntilVisible(find.text('TRANSAKTIONEN'), 200);
      expect(find.text('TRANSAKTIONEN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Auswertung rendert ($label)', (tester) async {
      await pumpApp(tester, size, () => const AnalyticsPage());
      expect(find.text('Nach Anlageklasse'.toUpperCase()), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Trefferquote'), 200, scrollable: list);
      await tester.scrollUntilVisible(find.text('Ø gesamt'), 200, scrollable: list);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PDF-Import rendert ($label)', (tester) async {
      await pumpApp(tester, size, () => const ImportPage());
      expect(find.text('PDF-Dateien auswählen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Benachrichtigungen rendern ($label)', (tester) async {
      final state = await pumpApp(tester, size, () => const NotificationsPage());
      state.userId = 'u1';
      await tester.pumpAndSettle();
      expect(find.text('Chat-ID'), findsOneWidget);
      // Die Seite hat mehrere Scrollables (Dropdowns), daher die ListView gezielt.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('Testnachricht senden'), 200,
          scrollable: list);
      await tester.scrollUntilVisible(find.textContaining('SAP SE'), 200,
          scrollable: list);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Formular Neuer Trade rendert ($label)', (tester) async {
      await pumpApp(tester, size, () => const PositionFormPage());
      await tester.tap(find.text('Derivat'));
      await tester.pumpAndSettle();
      expect(find.text('Knock-out-Schwelle'), findsOneWidget);
      // Leeres Formular speichern → Validierungsfehler statt Absturz
      await tester.tap(find.widgetWithText(TextButton, 'Speichern'));
      await tester.pumpAndSettle();
      expect(find.text('Pflichtfeld'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
