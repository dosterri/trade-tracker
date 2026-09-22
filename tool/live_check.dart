// ignore_for_file: avoid_print
// Prüft, ob die Kursquellen erreichbar sind und das erwartete Format liefern.
// Aufruf:  dart run tool/live_check.dart
import 'package:trade_tracker/core/models.dart';
import 'package:trade_tracker/data/quote_sources.dart';

Future<void> main() async {
  final s = QuoteService();
  Future<void> check(String label, Future<Object> Function() f) async {
    try {
      final r = await f();
      print('OK    $label → $r');
    } catch (e) {
      print('FEHLER $label → $e');
    }
  }

  await check('EZB/Frankfurter', () async {
    final fx = await s.fx.latest();
    return 'USD ${fx.rate('USD')} (Stand ${fx.date})';
  });
  await check('LS Suche SAP', () async {
    final h = await s.ls.search('DE0007164600');
    return '${h.first.name} id=${h.first.ref}';
  });
  await check('LS Kurs SAP', () async {
    final q = await s.ls.fetch('34313');
    return '${q.price} ${q.currency} @ ${q.at.toLocal()} (${q.history.length} Punkte)';
  });
  await check('onvista Suche Turbo', () async {
    final h = await s.search('DE000JY5HEJ7', AssetClass.derivative);
    return '${h.first.name} ref=${h.first.ref}';
  });
  await check('onvista Kurs Turbo (Bid)', () async {
    final q = await s.onvista.fetch('BOND/336330339', preferBid: true);
    return '${q.price} ${q.currency} @ ${q.at.toLocal()}';
  });
  await check('CoinGecko Bitcoin', () async {
    final q = await s.coingecko.fetch('bitcoin');
    return '${q.price} EUR (${q.history.length} Punkte)';
  });
}
