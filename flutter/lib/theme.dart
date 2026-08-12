import 'package:flutter/material.dart';

import 'domain.dart';

/// Paleta "sonar" do Sonda.
abstract final class SondaColors {
  static const bg = Color(0xFF0B141D);
  static const panel = Color(0xFF122230);
  static const panel2 = Color(0xFF0F1C28);
  static const line = Color(0x297EBED2);
  static const text = Color(0xFFE6F1F5);
  static const sub = Color(0xFF8FA9B8);
  static const accent = Color(0xFF45D8C8);
  static const hot = Color(0xFFFF6B6B);
  static const warm = Color(0xFFFFC24B);
  static const cold = Color(0xFF6FA8FF);

  static Color forBucket(ProximityBucket b) => switch (b) {
        ProximityBucket.immediate => hot,
        ProximityBucket.near => warm,
        ProximityBucket.far => cold,
      };
}

ThemeData sondaTheme() => ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: SondaColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: SondaColors.accent,
        surface: SondaColors.panel,
        onSurface: SondaColors.text,
      ),
      fontFamily: null, // fonte do sistema, como no protótipo
      useMaterial3: true,
    );
