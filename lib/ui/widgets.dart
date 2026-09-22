import 'package:flutter/material.dart';

import '../core/format.dart';

/// Breite ab der die Windows-/Tablet-Darstellung greift.
const double wideBreakpoint = 760;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideBreakpoint;

/// Auf schmalen Geräten Bottom-Sheet (iOS-typisch), auf breiten ein Dialog.
Future<T?> showAdaptiveSheet<T>(BuildContext context, WidgetBuilder builder) {
  if (isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: builder(ctx),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 16),
      child: builder(ctx),
    ),
  );
}

Future<bool> confirm(BuildContext context,
    {required String title, required String message, String action = 'Löschen'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return r ?? false;
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$e'), behavior: SnackBarBehavior.floating),
  );
}

void showInfo(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

/// Zahlenfeld, akzeptiert Komma oder Punkt als Dezimaltrennzeichen.
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.controller,
    required this.label,
    this.required = false,
    this.allowNegative = false,
    this.positive = false,
    this.suffix,
    this.helper,
    this.autofocus = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowNegative;
  final bool positive;
  final String? suffix;
  final String? helper;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        autofocus: autofocus,
        onChanged: onChanged,
        keyboardType:
            TextInputType.numberWithOptions(decimal: true, signed: allowNegative),
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
        validator: (v) {
          if (v == null || v.trim().isEmpty) {
            return required ? 'Pflichtfeld' : null;
          }
          final n = parseNum(v);
          if (n == null) return 'Keine gültige Zahl';
          if (!allowNegative && n < 0) return 'Darf nicht negativ sein';
          if (positive && n <= 0) return 'Muss größer als 0 sein';
          return null;
        },
      );
}

class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final now = DateTime.now();
          final d = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(2000),
            lastDate: lastDate ?? DateTime(now.year + 30),
          );
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: allowClear && value != null
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => onChanged(null))
                : const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(value == null ? '–' : fmtDate(value)),
        ),
      );
}

String numText(double? v) {
  if (v == null) return '';
  final s = v.toStringAsFixed(10).replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

/// Legt ein Datum (lokal) mit aktueller Uhrzeit zusammen; heute → jetzt.
DateTime withTimeOfDay(DateTime day) {
  final now = DateTime.now();
  if (day.year == now.year && day.month == now.month && day.day == now.day) {
    return now;
  }
  return DateTime(day.year, day.month, day.day, 12);
}
