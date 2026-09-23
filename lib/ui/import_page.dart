import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/import_plan.dart';
import '../core/tr_parser.dart';
import '../data/pdf_import.dart';
import '../state/app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

class ImportPage extends StatefulWidget {
  const ImportPage({super.key});

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  List<ImportPlan> _plans = [];
  final Map<int, String> _errors = {};
  final Set<int> _done = {};
  bool _busy = false;
  String? _message;

  Future<void> _pick() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final state = AppScope.read(context);
    try {
      final files = await pickPdfFiles();
      if (files.isEmpty) return;
      final positions = [for (final v in state.views) v.position];
      final refs = state.externalRefs;
      final plans = <ImportPlan>[];
      for (final f in files) {
        try {
          final text = await extractPdfText(f.path);
          final doc = parseTradeRepublicPdf(text);
          plans.addAll(planImport(doc, f.name,
              positions: positions, existingRefs: refs));
        } catch (e) {
          plans.add(ImportPlan(
            fileName: f.name,
            status: ImportStatus.skip,
            doc: const TrDocument(type: TrDocType.unknown),
            reason: 'Datei nicht lesbar: $e',
          ));
        }
      }
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _errors.clear();
        _done.clear();
      });
    } catch (e) {
      if (mounted) showError(context, 'Auswahl fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importAll() async {
    final state = AppScope.read(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    var ok = 0;
    for (var i = 0; i < _plans.length; i++) {
      final plan = _plans[i];
      if (!plan.canImport || _done.contains(i)) continue;
      try {
        await state.applyImport(plan);
        _done.add(i);
        ok++;
      } catch (e) {
        _errors[i] = '$e';
      }
    }
    if (!mounted) return;
    if (ok > 0) HapticFeedback.mediumImpact();
    setState(() {
      _busy = false;
      _message = ok == 0
          ? 'Nichts importiert.'
          : '$ok Buchung(en) importiert.'
              '${_errors.isEmpty ? '' : ' ${_errors.length} fehlgeschlagen.'}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final open = _plans.where((p) => p.canImport).length - _done.length;

    return Scaffold(
      appBar: AppBar(title: const Text('PDF-Import')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            children: [
              Text(
                'Wähle Abrechnungen von Trade Republic aus. Die Dateien werden '
                'nur auf diesem Gerät gelesen; gespeichert werden ausschließlich '
                'die erkannten Buchungen. Vor dem Speichern siehst du alles zur '
                'Kontrolle.',
                style: t.bodySmall?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _busy ? null : _pick,
                child: Text(_busy ? 'Bitte warten…' : 'PDF-Dateien auswählen'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!, style: t.bodyMedium),
              ],
              const SizedBox(height: 16),
              for (final (i, p) in _plans.indexed) ...[
                _PlanCard(
                  plan: p,
                  done: _done.contains(i),
                  error: _errors[i],
                ),
                const SizedBox(height: 10),
              ],
              if (_plans.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy || open <= 0 ? null : _importAll,
                  child: Text(open <= 0
                      ? 'Nichts zu importieren'
                      : '$open Buchung(en) importieren'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.done, this.error});

  final ImportPlan plan;
  final bool done;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;
    final item = plan.item;
    final txn = plan.txn;

    final color = switch (plan.status) {
      ImportStatus.ready => pnl.gain,
      ImportStatus.newPosition => pnl.gain,
      ImportStatus.duplicate => pnl.neutral,
      ImportStatus.skip => pnl.loss,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(plan.fileName,
                    style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(done ? 'Importiert' : plan.status.label,
                    style: t.labelSmall?.copyWith(color: color)),
              ),
            ]),
            const SizedBox(height: 8),
            if (item != null && txn != null) ...[
              Text('${txn.side.label}: ${item.name}', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(
                '${fmtQty(item.quantity)} × ${fmtPrice(item.price, item.currency)}'
                ' · ${fmtDate(txn.executedAt)}',
                style: t.bodySmall,
              ),
              Text(
                'Gebühren ${fmtMoney(txn.fees, item.currency)}'
                '${txn.taxes == 0 ? '' : ' · Steuern ${fmtMoney(txn.taxes, item.currency)}'}'
                ' · ${item.isin}',
                style: t.bodySmall,
              ),
              if (plan.status == ImportStatus.newPosition)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Position wird neu angelegt (Kursquelle zunächst manuell – '
                    'danach im Trade über „Suchen“ verknüpfen).',
                    style: t.bodySmall,
                  ),
                ),
              if (plan.target != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Wird gebucht auf: ${plan.target!.name}',
                      style: t.bodySmall),
                ),
            ] else
              Text(plan.doc.type.label, style: t.titleMedium),
            if (plan.reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(plan.reason!, style: t.bodySmall?.copyWith(color: color)),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Fehler: $error',
                    style: t.bodySmall?.copyWith(color: pnl.loss)),
              ),
          ],
        ),
      ),
    );
  }
}
