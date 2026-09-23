import 'package:file_picker/file_picker.dart';
import 'package:pdfrx/pdfrx.dart';

/// Auswahl und Textextraktion von PDF-Dateien.
/// Die Dateien verlassen das Gerät nicht: Gelesen wird lokal, gespeichert
/// werden nur die erkannten Buchungsdaten.

class PickedPdf {
  const PickedPdf(this.name, this.path);
  final String name;
  final String path;
}

Future<List<PickedPdf>> pickPdfFiles() async {
  // file_picker 13: pickFiles ist statisch und erlaubt Mehrfachauswahl.
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Abrechnungen auswählen',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
  return [
    for (final f in files)
      if (f.path != null) PickedPdf(f.name, f.path!),
  ];
}

/// Liest den Text aller Seiten. Wirft, wenn die Datei kein lesbares PDF ist.
Future<String> extractPdfText(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    final buffer = StringBuffer();
    for (final page in doc.pages) {
      final text = await page.loadText();
      if (text != null) buffer.writeln(text.fullText);
    }
    return buffer.toString();
  } finally {
    await doc.dispose();
  }
}
