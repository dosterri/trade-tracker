import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/portfolio.dart';
import '../state/app_scope.dart';
import 'widgets.dart';

/// Öffnet das Formular für Nachkauf oder Verkauf einer Position.
Future<bool?> showTxnForm(BuildContext context, PositionView view, TxnSide side) =>
    showAdaptiveSheet<bool>(context, (_) => TxnForm(view: view, side: side));

class TxnForm extends StatefulWidget {
  const TxnForm({super.key, required this.view, required this.side});
  final PositionView view;
  final TxnSide side;

  @override
  State<TxnForm> createState() => _TxnFormState();
}

class _TxnFormState extends State<TxnForm> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _fees = TextEditingController(text: '1');
  final _taxes = TextEditingController();
  final _fx = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;
  bool _loadingFx = false;
  String? _error;

  bool get _sell => widget.side == TxnSide.sell;
  String get _ccy => widget.view.position.currency;

  @override
  void initState() {
    super.initState();
    final v = widget.view;
    if (v.price != null && v.priceCurrency == _ccy) _price.text = numText(v.price);
    if (_ccy != 'EUR') {
      final r = AppScope.read(context).fx.rate(_ccy);
      if (r != null) _fx.text = numText(r);
    }
  }

  @override
  void dispose() {
    for (final c in [_qty, _price, _fees, _taxes, _fx]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFx() async {
    setState(() => _loadingFx = true);
    try {
      final r = await AppScope.read(context).quotes.fx.rateOn(_date, _ccy);
      _fx.text = numText(r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingFx = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final state = AppScope.read(context);
    final txn = Txn(
      id: '',
      positionId: widget.view.id,
      side: widget.side,
      quantity: parseNum(_qty.text)!,
      price: parseNum(_price.text)!,
      fees: parseNum(_fees.text) ?? 0,
      taxes: parseNum(_taxes.text) ?? 0,
      fxRate: _ccy == 'EUR' ? 1 : parseNum(_fx.text)!,
      executedAt: withTimeOfDay(_date),
    );
    final problem = state.validateTxn(txn);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await state.addTxn(txn);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = widget.view;
    return Form(
      key: _form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${widget.side.label}: ${v.position.name}', style: t.titleMedium),
            if (_sell)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Im Bestand: ${fmtQty(v.openQty)} Stk', style: t.bodySmall),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: NumField(
                    controller: _qty, label: 'Stückzahl', required: true,
                    positive: true, autofocus: true),
              ),
              if (_sell) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _qty.text = numText(v.openQty),
                  child: const Text('Alles'),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            NumField(
                controller: _price, label: 'Kurs je Stück', required: true, suffix: _ccy),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: NumField(controller: _fees, label: 'Gebühren', suffix: _ccy)),
              if (_sell) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: NumField(
                      controller: _taxes, label: 'Steuern', suffix: _ccy,
                      allowNegative: true),
                ),
              ],
            ]),
            const SizedBox(height: 12),
            DateField(
              label: 'Ausführungsdatum',
              value: _date,
              lastDate: DateTime.now(),
              onChanged: (d) => setState(() => _date = d ?? DateTime.now()),
            ),
            if (_ccy != 'EUR') ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: NumField(
                      controller: _fx, label: '$_ccy je 1 EUR', required: true,
                      positive: true),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _loadingFx ? null : _loadFx,
                  child: Text(_loadingFx ? 'Lädt…' : 'EZB-Kurs'),
                ),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Speichert…' : '${widget.side.label} speichern'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
