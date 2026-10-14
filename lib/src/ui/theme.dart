import 'package:flutter/material.dart';

class Bench {
  static const bg = Color(0xFF14181B);
  static const panel = Color(0xFF1D2428);
  static const panelAlt = Color(0xFF232B30);
  static const rail = Color(0xFF101315);
  static const border = Color(0xFF2E373D);
  static const accent = Color(0xFF4B8BFF);
  static const text = Color(0xFFE6EAED);
  static const muted = Color(0xFF8A969E);
  static const canvas = Color(0xFF0E1113);

  static ThemeData theme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: Brightness.dark, surface: panel),
      scaffoldBackgroundColor: bg,
      dividerColor: border,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: panelAlt,
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: border)),
      ),
      tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 400)),
    );
  }
}
