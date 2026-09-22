import 'package:flutter/material.dart';

/// Semantische Farben für Performance – dezent, nicht grell.
class PnlColors extends ThemeExtension<PnlColors> {
  const PnlColors({required this.gain, required this.loss, required this.neutral});

  final Color gain;
  final Color loss;
  final Color neutral;

  Color of(double? v) {
    if (v == null || v.abs() < 1e-9) return neutral;
    return v > 0 ? gain : loss;
  }

  @override
  PnlColors copyWith({Color? gain, Color? loss, Color? neutral}) => PnlColors(
      gain: gain ?? this.gain,
      loss: loss ?? this.loss,
      neutral: neutral ?? this.neutral);

  @override
  PnlColors lerp(ThemeExtension<PnlColors>? other, double t) {
    if (other is! PnlColors) return this;
    return PnlColors(
      gain: Color.lerp(gain, other.gain, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

extension PnlTheme on BuildContext {
  PnlColors get pnl => Theme.of(this).extension<PnlColors>()!;
}

const _tabular = [FontFeature.tabularFigures()];

ThemeData _build(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF0E0F12) : const Color(0xFFF5F5F7);
  final surface = dark ? const Color(0xFF17181C) : Colors.white;
  final outline = dark ? const Color(0xFF2A2C32) : const Color(0xFFE2E3E8);
  final text = dark ? const Color(0xFFECEDEF) : const Color(0xFF16171A);
  final muted = dark ? const Color(0xFF8B8E97) : const Color(0xFF6B6E77);
  const accent = Color(0xFF7FA7FF);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: b,
  ).copyWith(
    primary: accent,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outline: outline,
    outlineVariant: outline,
    surfaceContainerLowest: bg,
    surfaceContainerLow: surface,
    surfaceContainer: surface,
    surfaceContainerHigh: dark ? const Color(0xFF1F2025) : const Color(0xFFF0F0F3),
    surfaceContainerHighest: dark ? const Color(0xFF26272D) : const Color(0xFFE8E8EC),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600, letterSpacing: -0.5, color: text,
              fontFeatures: _tabular),
          titleMedium: base.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: text),
          bodyMedium: base.textTheme.bodyMedium
              ?.copyWith(color: text, fontFeatures: _tabular),
          bodySmall: base.textTheme.bodySmall
              ?.copyWith(color: muted, fontFeatures: _tabular),
          labelSmall: base.textTheme.labelSmall?.copyWith(color: muted),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: text,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: outline),
      ),
    ),
    dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1D22) : const Color(0xFFF7F7F9),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: outline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: outline)),
      isDense: true,
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: outline),
      backgroundColor: surface,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: [
      dark
          ? const PnlColors(
              gain: Color(0xFF5CC98F), loss: Color(0xFFE0717B), neutral: Color(0xFF8B8E97))
          : const PnlColors(
              gain: Color(0xFF1E9A5C), loss: Color(0xFFC8414E), neutral: Color(0xFF6B6E77)),
    ],
  );
}

final ThemeData darkTheme = _build(Brightness.dark);
final ThemeData lightTheme = _build(Brightness.light);
