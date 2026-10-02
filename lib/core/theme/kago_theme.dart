import 'package:flutter/material.dart';

abstract final class KaGoColors {
  static const accent = Color(0xFF22C55E);
  static const accentSoft = Color(0xFF86EFAC);
  static const canvas = Color(0xFF0B0F0D);
  static const surface = Color(0xFF131A16);
  static const surfaceRaised = Color(0xFF1A231D);
  static const border = Color(0xFF28342C);
  static const text = Color(0xFFF1F5F2);
  static const muted = Color(0xFF93A198);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
}

abstract final class KaGoTheme {
  static ThemeData dark({bool pureBlack = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: KaGoColors.accent,
      brightness: Brightness.dark,
      surface: pureBlack ? Colors.black : KaGoColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: pureBlack ? Colors.black : KaGoColors.canvas,
      cardColor: pureBlack ? Colors.black : KaGoColors.surface,
      dividerColor: KaGoColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: KaGoColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: pureBlack ? Colors.black : KaGoColors.canvas,
        indicatorColor: KaGoColors.accent.withValues(alpha: .15),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: pureBlack ? const Color(0xFF090909) : KaGoColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KaGoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KaGoColors.border),
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.7),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(fontSize: 14, color: KaGoColors.text),
        bodySmall: TextStyle(fontSize: 12, color: KaGoColors.muted),
      ),
    );
  }
}
