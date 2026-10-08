import 'dart:io';

import 'package:flutter/material.dart';

/// Fallback fonts that draw country flag emoji (Windows).
const kagoFlagFonts = <String>['KagoFlags'];

/// Colors of usekago.net: a light blue-grey page with white cards, a royal
/// blue for buttons and links, and a navy hero card. The dark variant keeps
/// the same hues for the site's moon toggle.
@immutable
class KaGoPalette extends ThemeExtension<KaGoPalette> {
  const KaGoPalette({
    required this.brand,
    required this.accent,
    required this.accentSoft,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.muted,
    required this.danger,
    required this.warning,
    required this.success,
    required this.successSoft,
    required this.heroStart,
    required this.heroEnd,
    required this.heroAccent,
    required this.heroBlob,
    required this.heroGlow,
    required this.heroText,
    required this.heroMuted,
  });

  /// Filled buttons ("Купить", "Войти", the connect button); white text on it.
  final Color brand;

  /// Links, icons, selected states.
  final Color accent;

  /// Tinted backgrounds behind accent icons and chips.
  final Color accentSoft;
  final Color canvas;
  final Color surface;

  /// Inner tiles inside a card (the site's device rows and inputs).
  final Color surfaceRaised;
  final Color border;
  final Color text;
  final Color muted;
  final Color danger;
  final Color warning;
  final Color success;
  final Color successSoft;

  /// The navy subscription card of the personal account.
  final Color heroStart;
  final Color heroEnd;

  /// Where the gradient fades out (the site's `--color-primary-strong`).
  final Color heroAccent;

  /// The blue glow at the top right and the green one at the bottom.
  final Color heroBlob;
  final Color heroGlow;
  final Color heroText;
  final Color heroMuted;

  // From the site's globals.css (`:root` and `html[data-theme="dark"]`).
  // Text colors are slightly darker where the site's value is below WCAG AA.
  static const light = KaGoPalette(
    brand: Color(0xFF2B5FD0), // --color-primary
    accent: Color(0xFF2B5FD0),
    accentSoft: Color(0xFFE8F0FF), // --color-primary-light
    // Page and borders a step darker than usekago.net: on a monitor the
    // site's #EDF2FA page and #E2E8F0 borders left white cards hard to see.
    canvas: Color(0xFFE3E9F3), // --color-page-bg #EDF2FA, darkened
    surface: Color(0xFFFFFFFF), // --color-bg
    surfaceRaised: Color(0xFFEEF2F9), // --color-surface #F4F8FE, darkened
    border: Color(0xFFCCD6E6), // --color-border #E2E8F0, darkened
    text: Color(0xFF13203F), // --color-text-h
    muted: Color(0xFF42526B), // --color-text-body
    danger: Color(0xFFC62828), // --color-danger #DC2626, darkened for AA
    warning: Color(0xFFA35200),
    success: Color(0xFF12723A), // --color-success #15A34A, darkened for AA
    successSoft: Color(0xFFE7F8EE), // --color-success-bg
    heroStart: Color(0xFF16223F), // --color-navy
    heroEnd: Color(0xFF1E2E54), // --color-navy2
    heroAccent: Color(0xFF1E47A8), // --color-primary-strong
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
  );

  static const dark = KaGoPalette(
    // White on the site's dark primary (#5B8CF5) is below AA, so filled
    // buttons keep the light primary; links and icons use the dark one.
    brand: Color(0xFF2B5FD0),
    accent: Color(0xFF5B8CF5), // --color-primary
    accentSoft: Color(0xFF17243F), // --color-primary-light
    canvas: Color(0xFF080B14), // --color-page-bg
    surface: Color(0xFF121A2E), // --color-bg
    surfaceRaised: Color(0xFF16203A), // --color-surface2
    border: Color(0xFF283452), // --color-border
    text: Color(0xFFEEF3FB), // --color-text-h
    muted: Color(0xFF8E9CB8), // --color-text-muted #8493B0, lifted for AA
    danger: Color(0xFFF87171), // --color-danger
    warning: Color(0xFFF5B544),
    success: Color(0xFF34D671), // --color-success
    successSoft: Color(0xFF10271D), // --color-success-bg
    heroStart: Color(0xFF0C1426), // --color-navy
    heroEnd: Color(0xFF1B2A4E), // --color-navy2
    heroAccent: Color(0xFF2B4FA8),
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
  );

  /// Dark palette on pure black for OLED screens.
  static final black = dark.copyWith(
    canvas: Colors.black,
    surface: const Color(0xFF0B0F18),
    surfaceRaised: const Color(0xFF121826),
    border: const Color(0xFF1E283B),
  );

  @override
  KaGoPalette copyWith({
    Color? brand,
    Color? accent,
    Color? accentSoft,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? text,
    Color? muted,
    Color? danger,
    Color? warning,
    Color? success,
    Color? successSoft,
    Color? heroStart,
    Color? heroEnd,
    Color? heroAccent,
    Color? heroBlob,
    Color? heroGlow,
    Color? heroText,
    Color? heroMuted,
  }) =>
      KaGoPalette(
        brand: brand ?? this.brand,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
        heroAccent: heroAccent ?? this.heroAccent,
        heroBlob: heroBlob ?? this.heroBlob,
        heroGlow: heroGlow ?? this.heroGlow,
        heroText: heroText ?? this.heroText,
        heroMuted: heroMuted ?? this.heroMuted,
      );

  @override
  KaGoPalette lerp(KaGoPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return KaGoPalette(
      brand: mix(brand, other.brand),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      heroStart: mix(heroStart, other.heroStart),
      heroEnd: mix(heroEnd, other.heroEnd),
      heroAccent: mix(heroAccent, other.heroAccent),
      heroBlob: mix(heroBlob, other.heroBlob),
      heroGlow: mix(heroGlow, other.heroGlow),
      heroText: mix(heroText, other.heroText),
      heroMuted: mix(heroMuted, other.heroMuted),
    );
  }
}

extension KaGoPaletteContext on BuildContext {
  KaGoPalette get kago =>
      Theme.of(this).extension<KaGoPalette>() ?? KaGoPalette.light;
}

abstract final class KaGoTheme {
  static ThemeData light() => _build(KaGoPalette.light, Brightness.light);

  static ThemeData dark({bool pureBlack = false}) =>
      _build(pureBlack ? KaGoPalette.black : KaGoPalette.dark, Brightness.dark);

  static ThemeData _build(KaGoPalette p, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: p.brand,
      brightness: brightness,
      surface: p.surface,
    ).copyWith(
      primary: p.accent,
      onPrimary: brightness == Brightness.light ? Colors.white : p.canvas,
      secondary: p.accent,
      primaryContainer: p.brand,
      onPrimaryContainer: Colors.white,
      error: p.danger,
      outline: p.border,
      outlineVariant: p.border,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
    );
    final rounded =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // Windows fonts draw a flag emoji as two letters ("DE"); the bundled
      // flag font turns them into the flag.
      fontFamilyFallback: Platform.isWindows ? kagoFlagFonts : null,
      extensions: <ThemeExtension<dynamic>>[p],
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
      scaffoldBackgroundColor: p.canvas,
      cardColor: p.surface,
      dividerColor: p.border,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.accent : p.muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected) ? p.accent : p.muted)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        selectedIconTheme: IconThemeData(color: p.accent),
        unselectedIconTheme: IconThemeData(color: p.muted),
        selectedLabelTextStyle: TextStyle(
            color: p.accent, fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: p.muted, fontSize: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.surfaceRaised,
          disabledForegroundColor: p.muted,
          shape: rounded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          backgroundColor: p.accentSoft,
          side: BorderSide(color: p.accent.withValues(alpha: .25)),
          shape: rounded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.brand : null),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            brightness == Brightness.light ? p.text : p.surfaceRaised,
        contentTextStyle: TextStyle(
            color: brightness == Brightness.light ? Colors.white : p.text),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
            color: p.text),
        titleLarge:
            TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: p.text),
        titleMedium:
            TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.text),
        bodyLarge: TextStyle(fontSize: 15, color: p.text),
        bodyMedium: TextStyle(fontSize: 14, color: p.text),
        bodySmall: TextStyle(fontSize: 12, color: p.muted),
      ),
    );
  }
}
