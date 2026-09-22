import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../data/quote_sources.dart';
import '../state/app_scope.dart';
import 'widgets.dart';

const currencies = ['EUR', 'USD', 'CHF', 'GBP', 'JPY', 'CAD', 'AUD', 'DKK', 'SEK', 'NOK', 'HKD'];

/// Neue Position (mit erstem Kauf) anlegen oder bestehende bearbeiten.
class PositionFormPage extends StatefulWidget {
  const PositionFormPage({super.key, this.existing});
  final Position? existing;

  @override
  State<PositionFormPage> createState() => _PositionFormPageState();
}

class _PositionFormPageState extends State<PositionFormPage> {
  final _form = GlobalKey<FormState>();
  late AssetClass _cls;
  late String _currency;
  late PriceSource _source;
  String? _sourceRef;
  DerivativeType? _dType;
  DateTime? _expiry;
  DateTime _buyDate = DateTime.now();

  final _search = TextEditingController();
  final _name = TextEditingController();
  final _isin = TextEditingController();
  final _symbol = TextEditingController();
  final _manual = TextEditingController();
  final _sl = TextEditingController();
  final _tp = TextEditingController();
  final _underlying = TextEditingController();
  final _strike = TextEditingController();
  final _barrier = TextEditingController();
  final _ratio = TextEditingController();
  final _issuer = TextEditingController();
  final _notes = TextEditingController();
  final _qty = TextEditingController();
  final _price = TextEditingController();
  final _fees = TextEditingController(text: '1');
  final _fx = TextEditingController();

  bool _searching = false;
  bool _saving = false;
  bool _loadingFx = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _cls = p?.assetClass ?? AssetClass.stock;
    _currency = p?.currency ?? 'EUR';
    _source = p?.priceSource ?? PriceSource.manual;
    _sourceRef = p?.sourceRef;
    _dType = p?.derivativeType;
    _expiry = p?.expiry;
    if (p != null) {
      _name.text = p.name;
      _isin.text = p.isin ?? '';
      _symbol.text = p.symbol ?? '';
      _manual.text = numText(p.manualPrice);
      _sl.text = numText(p.stopLoss);
      _tp.text = numText(p.takeProfit);
      _underlying.text = p.underlying ?? '';
      _strike.text = numText(p.strike);
      _barrier.text = numText(p.barrier);
      _ratio.text = numText(p.ratio);
      _issuer.text = p.issuer ?? '';
      _notes.text = p.notes ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [
      _search, _name, _isin, _symbol, _manual, _sl, _tp, _underlying, _strike,
      _barrier, _ratio, _issuer, _notes, _qty, _price, _fees, _fx,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    List<InstrumentHit> hits;
    try {
      hits = await AppScope.read(context).quotes.search(q, _cls);
    } catch (e) {
      if (mounted) showError(context, 'Suche fehlgeschlagen: $e');
      return;
    } finally {
      if (mounted) setState(() => _searching = false);
    }
    if (!mounted) return;
    if (hits.isEmpty) {
      showInfo(context, 'Nichts gefunden – du kannst die Position manuell anlegen.');
      return;
    }
    final hit = await showDialog<InstrumentHit>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Treffer auswählen'),
        children: [
          for (final h in hits.take(20))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, h),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(h.name),
                subtitle: Text([
                  h.source.label,
                  if (h.category != null) h.category!,
                  if (h.isin != null) h.isin!,
                  if (h.symbol != null) h.symbol!,
                ].join(' · ')),
              ),
            ),
        ],
      ),
    );
    if (hit == null) return;
    setState(() {
      _name.text = hit.name;
      if (hit.isin != null) _isin.text = hit.isin!;
      if (hit.source == PriceSource.coingecko) _symbol.text = hit.ref;
      _source = hit.source;
      _sourceRef = hit.ref;
    });
  }

  Future<void> _loadFx() async {
    setState(() => _loadingFx = true);
    try {
      final r = await AppScope.read(context).quotes.fx.rateOn(_buyDate, _currency);
      _fx.text = numText(r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingFx = false);
    }
  }

  String? _nz(TextEditingController c) {
    final s = c.text.trim();
    return s.isEmpty ? null : s;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_source != PriceSource.manual &&
        _source != PriceSource.coingecko &&
        _sourceRef == null) {
      showError(context, 'Bitte über „Suchen“ ein Instrument wählen oder Kursquelle „Manuell“.');
      return;
    }
    final state = AppScope.read(context);
    final old = widget.existing;
    final manual = parseNum(_manual.text);
    final derivative = _cls == AssetClass.derivative;
    final p = Position(
      id: old?.id ?? '',
      assetClass: _cls,
      name: _name.text.trim(),
      isin: _nz(_isin)?.toUpperCase(),
      symbol: _nz(_symbol),
      currency: _currency,
      priceSource: _source,
      sourceRef: _source == PriceSource.coingecko ? (_nz(_symbol) ?? _sourceRef) : _sourceRef,
      manualPrice: manual,
      manualPriceAt: manual == null
          ? null
          : (manual == old?.manualPrice ? old?.manualPriceAt : DateTime.now()),
      stopLoss: parseNum(_sl.text),
      takeProfit: parseNum(_tp.text),
      derivativeType: derivative ? _dType : null,
      underlying: derivative ? _nz(_underlying) : null,
      strike: derivative ? parseNum(_strike.text) : null,
      barrier: derivative ? parseNum(_barrier.text) : null,
      expiry: derivative ? _expiry : null,
      ratio: derivative ? parseNum(_ratio.text) : null,
      issuer: derivative ? _nz(_issuer) : null,
      notes: _nz(_notes),
    );

    setState(() => _saving = true);
    try {
      if (old != null) {
        await state.updatePosition(p);
      } else {
        await state.createPosition(
          p,
          Txn(
            id: '',
            positionId: '',
            side: TxnSide.buy,
            quantity: parseNum(_qty.text)!,
            price: parseNum(_price.text)!,
            fees: parseNum(_fees.text) ?? 0,
            fxRate: _currency == 'EUR' ? 1 : parseNum(_fx.text)!,
            executedAt: withTimeOfDay(_buyDate),
          ),
        );
        HapticFeedback.mediumImpact();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const gap = SizedBox(height: 12, width: 12);

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 10),
          child: Text(title.toUpperCase(),
              style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        );

    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), gap, Expanded(child: b)],
        );

    final sourceItems = PriceSource.values.where((s) {
      if (_cls == AssetClass.crypto) {
        return s == PriceSource.coingecko || s == PriceSource.manual;
      }
      return s != PriceSource.coingecko;
    }).toList();
    if (!sourceItems.contains(_source)) _source = PriceSource.manual;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Position bearbeiten' : 'Neuer Trade'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Speichert…' : 'Speichern'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Form(
          key: _form,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  SegmentedButton<AssetClass>(
                    segments: [
                      for (final c in AssetClass.values)
                        ButtonSegment(value: c, label: Text(c.label)),
                    ],
                    selected: {_cls},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _cls = s.first;
                        _source = PriceSource.manual;
                        _sourceRef = null;
                      });
                    },
                  ),
                  section('Instrument'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: _cls == AssetClass.crypto
                              ? 'Coin suchen (z. B. Bitcoin)'
                              : 'ISIN oder Name suchen',
                        ),
                        onSubmitted: (_) => _runSearch(),
                      ),
                    ),
                    gap,
                    FilledButton.tonal(
                      onPressed: _searching ? null : _runSearch,
                      child: Text(_searching ? 'Sucht…' : 'Suchen'),
                    ),
                  ]),
                  gap,
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
                  ),
                  gap,
                  pair(
                    TextFormField(
                      controller: _isin,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'ISIN (optional)'),
                      validator: (v) {
                        final s = (v ?? '').trim().toUpperCase();
                        if (s.isEmpty) return null;
                        return RegExp(r'^[A-Z]{2}[A-Z0-9]{9}[0-9]$').hasMatch(s)
                            ? null
                            : 'Ungültige ISIN';
                      },
                    ),
                    TextFormField(
                      controller: _symbol,
                      decoration: InputDecoration(
                          labelText: _cls == AssetClass.crypto
                              ? 'CoinGecko-ID'
                              : 'Kürzel (optional)'),
                      validator: (v) => _cls == AssetClass.crypto &&
                              _source == PriceSource.coingecko &&
                              (v == null || v.trim().isEmpty)
                          ? 'Pflichtfeld für CoinGecko'
                          : null,
                    ),
                  ),
                  gap,
                  pair(
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'Handelswährung'),
                      items: [
                        for (final c in currencies)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: _editing
                          ? null // Währung nachträglich ändern würde Historie verfälschen.
                          : (v) => setState(() => _currency = v ?? 'EUR'),
                    ),
                    DropdownButtonFormField<PriceSource>(
                      isExpanded: true,
                      key: ValueKey('src-$_cls-$_source'),
                      initialValue: _source,
                      decoration: const InputDecoration(labelText: 'Kursquelle'),
                      items: [
                        for (final s in sourceItems)
                          DropdownMenuItem(value: s, child: Text(s.label)),
                      ],
                      onChanged: (v) => setState(() {
                        _source = v ?? PriceSource.manual;
                        if (_source != PriceSource.manual) _sourceRef = null;
                      }),
                    ),
                  ),
                  if (_sourceRef != null && _source != PriceSource.manual)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Verknüpft: ${_source.label} · $_sourceRef',
                          style: t.bodySmall),
                    ),
                  gap,
                  NumField(
                    controller: _manual,
                    label: _source == PriceSource.manual
                        ? 'Aktueller Kurs (manuell)'
                        : 'Manueller Kurs (Fallback, optional)',
                    suffix: _currency,
                  ),
                  if (_cls == AssetClass.derivative) ...[
                    section('Derivat'),
                    DropdownButtonFormField<DerivativeType>(
                      isExpanded: true,
                      initialValue: _dType,
                      decoration: const InputDecoration(labelText: 'Typ'),
                      items: [
                        for (final d in DerivativeType.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (v) => setState(() => _dType = v),
                    ),
                    gap,
                    pair(
                      TextFormField(
                          controller: _underlying,
                          decoration: const InputDecoration(labelText: 'Basiswert')),
                      TextFormField(
                          controller: _issuer,
                          decoration: const InputDecoration(labelText: 'Emittent')),
                    ),
                    gap,
                    pair(
                      NumField(controller: _strike, label: 'Strike / Basispreis'),
                      NumField(controller: _barrier, label: 'Knock-out-Schwelle'),
                    ),
                    gap,
                    pair(
                      NumField(
                          controller: _ratio, label: 'Bezugsverhältnis',
                          positive: true, helper: 'z. B. 0,1'),
                      DateField(
                        label: 'Laufzeit bis',
                        value: _expiry,
                        allowClear: true,
                        onChanged: (d) => setState(() => _expiry = d),
                      ),
                    ),
                  ],
                  section('Stop-Loss / Take-Profit'),
                  pair(
                    NumField(controller: _sl, label: 'Stop-Loss', suffix: _currency),
                    NumField(controller: _tp, label: 'Take-Profit', suffix: _currency),
                  ),
                  if (!_editing) ...[
                    section('Kauf'),
                    pair(
                      NumField(
                          controller: _qty, label: 'Stückzahl', required: true,
                          positive: true),
                      NumField(
                          controller: _price, label: 'Kurs je Stück', required: true,
                          suffix: _currency),
                    ),
                    gap,
                    pair(
                      NumField(controller: _fees, label: 'Gebühren', suffix: _currency),
                      DateField(
                        label: 'Kaufdatum',
                        value: _buyDate,
                        lastDate: DateTime.now(),
                        onChanged: (d) => setState(() => _buyDate = d ?? DateTime.now()),
                      ),
                    ),
                    if (_currency != 'EUR') ...[
                      gap,
                      Row(children: [
                        Expanded(
                          child: NumField(
                              controller: _fx, label: '$_currency je 1 EUR',
                              required: true, positive: true),
                        ),
                        gap,
                        TextButton(
                          onPressed: _loadingFx ? null : _loadFx,
                          child: Text(_loadingFx ? 'Lädt…' : 'EZB-Kurs'),
                        ),
                      ]),
                    ],
                  ],
                  section('Notizen'),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notiz (optional)'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Speichert…' : 'Speichern'),
                  ),
                  const SizedBox(height: 8),
                  Text('Tipp: Strg+S speichert. Dezimaltrennzeichen: Komma oder Punkt.',
                      style: t.bodySmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
