// ignore_for_file: depend_on_referenced_packages
// ignore_for_file: avoid_print
// Einmal-Werkzeug: liest ein PDF mit pdfrx und zeigt, was der Parser erkennt.
// Aufruf: dart run tool/pdf_probe.dart "C:\Pfad\zur\Datei.pdf"
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:trade_tracker/core/tr_parser.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args.first);
  final buf = StringBuffer();
  for (final page in doc.pages) {
    buf.writeln((await page.loadText())?.fullText ?? '');
  }
  await doc.dispose();
  final text = buf.toString();
  print('Zeichen: ${text.length}');
  final d = parseTradeRepublicPdf(text);
  print('Typ: ${d.type.label}  Seite: ${d.side?.label}  Datum: ${d.executedAt}');
  print('Auftrag: ${d.orderId}  Ausführung: ${d.executionId}');
  for (final i in d.items) {
    print('Position: ${i.name} | ${i.isin} | ${i.quantity} x ${i.price} ${i.currency} = ${i.amount}');
  }
  print('Gebühren: ${d.fees}  Steuern: ${d.taxes}  Gesamt: ${d.total}');
  print('Importierbar: ${d.isImportable}  Warnungen: ${d.warnings}');
}
