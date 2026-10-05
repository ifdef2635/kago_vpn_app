import 'package:flutter/material.dart';

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
  final Color heroGlow;
  final Color heroText;
  final Color heroMuted;

  static const light = KaGoPalette(
    brand: Color(0xFF2D5BD0),
    accent: Color(0xFF2D5BD0),
    accentSoft: Color(0xFFE6EDFC),
    canvas: Color(0xFFEEF2F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF4F7FC),
    border: Color(0xFFE0E6F0),
    text: Color(0xFF0F1B3D),
    muted: Color(0xFF56627F),
    danger: Color(0xFFC9302C),
    warning: Color(0xFFA35200),
    success: Color(0xFF12723A),
    successSoft: Color(0xFFE5F6EB),
    heroStart: Color(0xFF1A2D5C),
    heroEnd: Color(0xFF24448C),
    heroGlow: Color(0xFF1C7A6E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
  );

  static const dark = KaGoPalette(
    brand: Color(0xFF2D5BD0),
    accent: Color(0xFF7DA2F2),
    accentSoft: Color(0xFF1C2A4A),
    canvas: Color(0xFF0B1220),
    surface: Color(0xFF131C2E),
    surfaceRaised: Color(0xFF1A2539),
    border: Color(0xFF26344D),
    text: Color(0xFFE8EEFA),
    muted: Color(0xFF97A5C2),
    danger: Color(0xFFF27A7A),
    warning: Color(0xFFF5B544),
    success: Color(0xFF4ADE80),
    successSoft: Color(0xFF12301F),
    heroStart: Color(0xFF16284F),
    heroEnd: Color(0xFF22408A),
    heroGlow: Color(0xFF1C7A6E),
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
