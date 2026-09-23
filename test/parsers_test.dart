import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trade_tracker/core/format.dart';
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/core/notifications.dart';
import 'package:trade_tracker/data/quote_sources.dart';

// Gekürzte Original-Antworten der Quellen (Stand 22.09.2026).
const lsSearch =
    '[{"id":34313,"displayname":"SAP SE","isin":"DE0007164600","wkn":716460,'
    '"categoryid":5,"productcount":141,"alias":"","categorysort":1,"instrumentId":34313,'
    '"categorySymbol":"STK","categoryName":"Aktie","url":34313,"link":"/de/aktie/34313"}]';

const lsChart = '{"info":{"isin":"DE0007164600"},"container":null,"series":{"intraday":'
    '{"id":"34313midi","data":[[1790060580000,182.41],[1790060640000,182.5],'
    '[1790064000000,182.72]]}}}';

const onvistaQuery = '{"expires":1,"searchValue":"DE000JY5HEJ7","list":[{"type":"Instrument",'
    '"entityType":"BOND","entityValue":"336330339","name":"J.P. MORGAN SE TURBOS O.END NVIDIA 240,0",'
    '"isin":"DE000JY5HEJ7","wkn":"JY5HEJ"}]}';

const onvistaSnapshot = '{"type":"BondsSnapshot","quote":{"last":10.57,"bid":10.55,"ask":10.77,'
    '"datetimeLast":"2026-09-22T16:36:54.000+00:00","datetimeBid":"2026-09-22T16:37:10.000+00:00",'
    '"isoCurrency":"EUR","previousLast":11.83}}';

const geckoChart = '{"prices":[[1790000000000,75000.5],[1790003600000,75447.0]],'
    '"market_caps":[],"total_volumes":[]}';

const geckoSearch = '{"coins":[{"id":"bitcoin","name":"Bitcoin","symbol":"btc"}]}';

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  group('Lang & Schwarz', () {
    test('Suche', () {
      final h = LsSource.parseSearch(lsSearch).single;
      expect(h.ref, '34313');
      expect(h.isin, 'DE0007164600');
      expect(h.name, 'SAP SE');
      expect(h.source, PriceSource.ls);
    });

    test('Chart → letzter Kurs und Verlauf', () {
      final pts = LsSource.parseChart(lsChart, 'intraday');
      expect(pts.length, 3);
      expect(pts.last.price, 182.72);
      expect(LsSource.parseChart(lsChart, 'history'), isEmpty);
    });
  });

  group('onvista', () {
    test('Suche liefert TYP/ID', () {
      final h = OnvistaSource.parseSearch(onvistaQuery).single;
      expect(h.ref, 'BOND/336330339');
      expect(h.isin, 'DE000JY5HEJ7');
    });

    test('Derivat: Geldkurs (Bid) bevorzugt', () {
      final q = OnvistaSource.parseSnapshot(onvistaSnapshot, preferBid: true);
      expect(q.price, 10.55);
      expect(q.currency, 'EUR');
      expect(q.at.toUtc(), DateTime.utc(2026, 9, 22, 16, 37, 10));
    });

    test('Sonst letzter Kurs', () {
      expect(OnvistaSource.parseSnapshot(onvistaSnapshot).price, 10.57);
    });

    test('Kein Kurs → QuoteException', () {
      expect(() => OnvistaSource.parseSnapshot('{"quote":null}'),
          throwsA(isA<QuoteException>()));
    });
  });

  group('CoinGecko', () {
    test('Market Chart', () {
      final q = CoinGeckoSource.parseMarketChart(geckoChart);
      expect(q.price, 75447.0);
      expect(q.history.length, 2);
      expect(q.currency, 'EUR');
    });

    test('Suche', () {
      final h = CoinGeckoSource.parseSearch(geckoSearch).single;
      expect(h.ref, 'bitcoin');
      expect(h.symbol, 'BTC');
    });
  });

  group('Zahlen-Eingabe', () {
    test('deutsches und englisches Format', () {
      expect(parseNum('1.234,56'), 1234.56);
      expect(parseNum('1,234.56'), 1234.56);
      expect(parseNum('12,5'), 12.5);
      expect(parseNum('12.5'), 12.5);
      expect(parseNum(' 1 234,5 € '), 1234.5);
      expect(parseNum('-0,5'), -0.5);
      expect(parseNum('1.234.567'), 1234567);
    });

    test('einzelner Punkt bleibt Dezimalpunkt (Derivatekurse)', () {
      expect(parseNum('1.234'), 1.234);
      expect(parseNum('0.0123'), 0.0123);
    });

    test('ungültig → null', () {
      expect(parseNum(''), isNull);
      expect(parseNum('abc'), isNull);
      expect(parseNum('1,2,3'), isNull);
      expect(parseNum(null), isNull);
    });
  });

  group('Formatierung', () {
    test('EUR und Prozent', () {
      // intl setzt ein geschütztes Leerzeichen vor das €-Zeichen.
      expect(fmtEur(1234.5), '1.234,50 €');
      expect(fmtEur(12, signed: true), '+12,00 €');
      expect(fmtPct(0.1234), '+12,34 %');
      expect(fmtPct(-0.05), '-5,00 %');
    });

    test('kleine Kurse mit mehr Stellen', () {
      expect(fmtPrice(0.0123), '0,0123 €');
      expect(fmtPrice(182.72), '182,72 €');
      expect(fmtPrice(10, 'USD'), '10,000 USD');
    });
  });

  group('Datenmodell', () {
    test('Position Roundtrip über Cache', () {
      final p = Position(
        id: 'x',
        assetClass: AssetClass.derivative,
        name: 'Turbo',
        isin: 'DE000JY5HEJ7',
        priceSource: PriceSource.onvista,
        sourceRef: 'BOND/336330339',
        derivativeType: DerivativeType.koShort,
        barrier: 240,
        expiry: DateTime(2027, 3, 19),
        ratio: 0.1,
      );
      final back = Position.fromRow(p.toCache());
      expect(back.derivativeType, DerivativeType.koShort);
      expect(back.expiry, DateTime(2027, 3, 19));
      expect(back.ratio, 0.1);
      expect(back.priceSource, PriceSource.onvista);
    });

    test('Alarm-Schwellen überleben den Roundtrip', () {
      const p = Position(
        id: 'x',
        assetClass: AssetClass.stock,
        name: 'SAP',
        alertUpPct: 10,
        alertDownPct: 5,
        alertsEnabled: false,
      );
      final back = Position.fromRow(p.toCache());
      expect(back.alertUpPct, 10);
      expect(back.alertDownPct, 5);
      expect(back.alertsEnabled, isFalse);
    });

    test('Benachrichtigungs-Einstellungen: leere Felder werden zu null', () {
      const s = NotificationSettings(
          telegramEnabled: true, telegramChatId: '  ', ntfyTopic: 'tt-abc');
      final row = s.toRow();
      expect(row['telegram_chat_id'], isNull);
      expect(row['ntfy_topic'], 'tt-abc');
      expect(s.anyChannel, isFalse);

      final back = NotificationSettings.fromRow({
        ...row,
        'telegram_chat_id': '999',
        'ntfy_enabled': true,
      });
      expect(back.telegramChatId, '999');
      expect(back.anyChannel, isTrue);
      expect(back.quietFrom, 22);
    });

    test('Supabase liefert numeric teils als String', () {
      final t = Txn.fromRow({
        'id': 'a',
        'position_id': 'p',
        'side': 'sell',
        'quantity': '0.5',
        'price': 100,
        'fees': '1.00',
        'taxes': null,
        'fx_rate': 1,
        'executed_at': '2026-01-01T10:00:00+00:00',
      });
      expect(t.quantity, 0.5);
      expect(t.fees, 1);
      expect(t.taxes, 0);
      expect(t.side, TxnSide.sell);
    });
  });
}
