import 'package:flutter/material.dart';

abstract final class KaGoColors {
  /// The KAGO logo blue (#1A4780): filled buttons, the brand mark. Too dark to
  /// be used as text or an icon color on the dark surfaces, so [accent] is its
  /// lighter tint of the same hue.
  static const brand = Color(0xFF1A4780);
  static const accent = Color(0xFF5C9CE6);
  static const accentSoft = Color(0xFFBFD8FA);
  static const canvas = Color(0xFF08111F);
  static const surface = Color(0xFF0E1B31);
  static const surfaceRaised = Color(0xFF152744);
  static const border = Color(0xFF22395E);
  static const text = Color(0xFFF4F8FF);
  static const muted = Color(0xFF93A7C4);
  static const danger = Color(0xFFF87171);
  static const warning = Color(0xFFFBBF24);
}

abstract final class KaGoTheme {
  static ThemeData dark({bool pureBlack = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: KaGoColors.brand,
      brightness: Brightness.dark,
      surface: pureBlack ? Colors.black : KaGoColors.surface,
    ).copyWith(
      // Bright tint for indicators, focus rings and switches; the logo blue
      // itself is used for filled buttons below.
      primary: KaGoColors.accent,
      onPrimary: KaGoColors.canvas,
      secondary: KaGoColors.accent,
      primaryContainer: KaGoColors.brand,
      onPrimaryContainer: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        },
      ),
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
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KaGoColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: KaGoColors.surfaceRaised,
          disabledForegroundColor: KaGoColors.muted,
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
