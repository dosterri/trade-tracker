import 'models.dart';
import 'tr_parser.dart';

/// Plant, was aus einem eingelesenen PDF werden soll – reine Logik, damit sie
/// unabhängig von Dateiauswahl und Oberfläche geprüft werden kann.

enum ImportStatus {
  /// Kann direkt einer bestehenden Position zugebucht werden.
  ready('Zuordnen'),

  /// Wertpapier ist noch nicht angelegt.
  newPosition('Position anlegen'),

  /// Diese Ausführung wurde bereits importiert.
  duplicate('Bereits importiert'),

  /// Kein importierbares Dokument (Kosteninformation, Dividende, Fremd-PDF).
  skip('Nicht importierbar');

  const ImportStatus(this.label);
  final String label;
}

class ImportPlan {
  const ImportPlan({
    required this.fileName,
    required this.status,
    required this.doc,
    this.item,
    this.target,
    this.txn,
    this.reason,
  });

  final String fileName;
  final ImportStatus status;
  final TrDocument doc;
  final TrItem? item;

  /// Vorhandene Position, der zugebucht wird.
  final Position? target;

  /// Fertige Buchung (ohne Positions-ID, falls die Position noch fehlt).
  final Txn? txn;
  final String? reason;

  bool get canImport =>
      status == ImportStatus.ready || status == ImportStatus.newPosition;

  ImportPlan copyWith({ImportStatus? status, String? reason}) => ImportPlan(
        fileName: fileName,
        status: status ?? this.status,
        doc: doc,
        item: item,
        target: target,
        txn: txn,
        reason: reason ?? this.reason,
      );
}

/// Erzeugt je Wertpapier im Dokument einen Plan.
/// Gebühren und Steuern werden bei mehreren Positionen anteilig nach
/// Betrag verteilt.
List<ImportPlan> planImport(
  TrDocument doc,
  String fileName, {
  required List<Position> positions,
  required Set<String> existingRefs,
}) {
  if (!doc.isImportable) {
    return [
      ImportPlan(
        fileName: fileName,
        status: ImportStatus.skip,
        doc: doc,
        reason: doc.warnings.isNotEmpty ? doc.warnings.first : doc.type.label,
      ),
    ];
  }

  final totalAmount = doc.items.fold(0.0, (s, i) => s + i.amount.abs());
  final plans = <ImportPlan>[];

  for (final item in doc.items) {
    final share = totalAmount > 0 ? item.amount.abs() / totalAmount : 1.0;
    final ref = doc.items.length == 1
        ? doc.externalRef
        : '${doc.externalRef ?? 'tr'}:${item.isin}';

    if (ref != null && existingRefs.contains(ref)) {
      plans.add(ImportPlan(
        fileName: fileName,
        status: ImportStatus.duplicate,
        doc: doc,
        item: item,
        reason: 'Diese Ausführung ist bereits gebucht.',
      ));
      continue;
    }

    Position? target;
    for (final p in positions) {
      if (p.isin != null && p.isin!.toUpperCase() == item.isin.toUpperCase()) {
        target = p;
        break;
      }
    }

    // Ein Verkauf ohne bekannte Position ergibt keinen Bestand – dann fehlt
    // der Kauf. Sonst stünde die Position sofort mit Fehler da.
    if (target == null && doc.side == TxnSide.sell) {
      plans.add(ImportPlan(
        fileName: fileName,
        status: ImportStatus.skip,
        doc: doc,
        item: item,
        reason: 'Verkauf ohne passende Position (${item.isin}). '
            'Bitte zuerst den Kauf importieren oder die Position anlegen.',
      ));
      continue;
    }

    final txn = Txn(
      id: '',
      positionId: target?.id ?? '',
      side: doc.side!,
      quantity: item.quantity,
      price: item.price,
      fees: doc.fees * share,
      taxes: doc.taxes * share,
      fxRate: 1,
      executedAt: doc.executedAt!,
      externalRef: ref,
    );

    plans.add(ImportPlan(
      fileName: fileName,
      status: target == null ? ImportStatus.newPosition : ImportStatus.ready,
      doc: doc,
      item: item,
      target: target,
      txn: txn,
    ));
  }
  return plans;
}

/// Vorschlag für eine noch nicht vorhandene Position.
Position positionFromImport(TrItem item) => Position(
      id: '',
      assetClass: AssetClass.stock,
      name: item.name.isEmpty ? item.isin : item.name,
      isin: item.isin,
      currency: item.currency,
      priceSource: PriceSource.manual,
      manualPrice: item.price,
      manualPriceAt: DateTime.now(),
      notes: 'Aus PDF-Import angelegt.',
    );
