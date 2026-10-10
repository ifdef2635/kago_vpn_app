import 'dart:io';

import 'package:flutter/material.dart';

/// Fallback fonts that draw country flag emoji (Windows).
const kagoFlagFonts = <String>['KagoFlags'];

/// The interface font of usekago.net's design system (assets/fonts, OFL):
/// headings in Black, text in Medium.
const kagoFontFamily = 'Onest';

/// Corner radii of the design system (`--radius-*` of globals.css).
abstract final class KaGoRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;

  /// Pills and chips (`border-radius: 999px`).
  static const double pill = 999;

  /// Filled buttons of the site (`.btn-primary`).
  static const double button = 10;
}

/// Font weights of the design system.
abstract final class KaGoWeight {
  /// Body text (Onest Medium).
  static const body = FontWeight.w500;
  static const semiBold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const extraBold = FontWeight.w800;

  /// Headings (Onest Black).
  static const heading = FontWeight.w900;
}

/// Colors of usekago.net: a light blue-grey page with white cards, a royal
/// blue for buttons and links, and a navy hero card. The dark variant keeps
/// the same hues for the site's moon toggle.
@immutable
class KaGoPalette extends ThemeExtension<KaGoPalette> {
  const KaGoPalette({
    required this.brand,
    required this.brandStrong,
    required this.accent,
    required this.accentSoft,
    required this.accentTint,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderLight,
    required this.text,
    required this.muted,
    required this.hint,
    required this.danger,
    required this.warning,
    required this.success,
    required this.successSoft,
    required this.telegram,
    required this.heroStart,
    required this.heroEnd,
    required this.heroAccent,
    required this.heroBlob,
    required this.heroGlow,
    required this.heroText,
    required this.heroMuted,
    required this.shadow,
  });

  /// Filled buttons ("Купить", "Войти", the connect button); white text on it.
  final Color brand;

  /// The pressed/hovered shade of [brand] (`--color-primary-strong`).
  final Color brandStrong;

  /// Links, icons, selected states.
  final Color accent;

  /// Tinted backgrounds behind accent icons and chips
  /// (`--color-primary-light`).
  final Color accentSoft;

  /// A step stronger than [accentSoft]: chip borders, icon squares
  /// (`--color-primary-tint`).
  final Color accentTint;
  final Color canvas;
  final Color surface;

  /// Inner tiles inside a card (the site's device rows and inputs).
  final Color surfaceRaised;
  final Color border;

  /// The quieter border of inner tiles (`--color-border-light`).
  final Color borderLight;
  final Color text;
  final Color muted;

  /// Captions and placeholders (`--color-text-hint`).
  final Color hint;
  final Color danger;
  final Color warning;
  final Color success;
  final Color successSoft;

  /// Telegram blue (`--color-tg`).
  final Color telegram;

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

  /// The card shadow of the site (`--color-shadow`).
  final Color shadow;

  // From the site's globals.css (`:root` and `html[data-theme="dark"]`).
  // Text colors are slightly darker where the site's value is below WCAG AA.
  static const light = KaGoPalette(
    brand: Color(0xFF2B5FD0), // --color-primary
    brandStrong: Color(0xFF1E47A8), // --color-primary-strong
    accent: Color(0xFF2B5FD0),
    accentSoft: Color(0xFFE8F0FF), // --color-primary-light
    accentTint: Color(0xFFD2E1FF), // --color-primary-tint
    // Page and borders a step darker than usekago.net: on a monitor the
    // site's #EDF2FA page and #E2E8F0 borders left white cards hard to see.
    canvas: Color(0xFFE3E9F3), // --color-page-bg #EDF2FA, darkened
    surface: Color(0xFFFFFFFF), // --color-bg
    surfaceRaised: Color(0xFFEEF2F9), // --color-surface #F4F8FE, darkened
    border: Color(0xFFCCD6E6), // --color-border #E2E8F0, darkened
    borderLight: Color(0xFFDCE4F0), // --color-border-light #EAEFF7, darkened
    text: Color(0xFF13203F), // --color-text-h
    muted: Color(0xFF42526B), // --color-text-body
    hint: Color(0xFF64748B), // --color-text-muted (--color-text-hint is < AA)
    danger: Color(0xFFC62828), // --color-danger #DC2626, darkened for AA
    warning: Color(0xFFA35200),
    success: Color(0xFF12723A), // --color-success #15A34A, darkened for AA
    successSoft: Color(0xFFE7F8EE), // --color-success-bg
    telegram: Color(0xFF1C87BC), // --color-tg #229ED9, darkened for AA
    heroStart: Color(0xFF16223F), // --color-navy
    heroEnd: Color(0xFF1E2E54), // --color-navy2
    heroAccent: Color(0xFF1E47A8), // --color-primary-strong
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
    shadow: Color(0x1A14285A), // --color-shadow rgba(20,40,90,.10)
  );

  static const dark = KaGoPalette(
    // White on the site's dark primary (#5B8CF5) is below AA, so filled
    // buttons keep the light primary; links and icons use the dark one.
    brand: Color(0xFF2B5FD0),
    brandStrong: Color(0xFF1E47A8),
    accent: Color(0xFF5B8CF5), // --color-primary
    accentSoft: Color(0xFF17243F), // --color-primary-light
    accentTint: Color(0xFF213256), // --color-primary-tint
    canvas: Color(0xFF080B14), // --color-page-bg
    surface: Color(0xFF121A2E), // --color-bg
    surfaceRaised: Color(0xFF16203A), // --color-surface2
    border: Color(0xFF283452), // --color-border
    borderLight: Color(0xFF1E2842), // --color-border-light
    text: Color(0xFFEEF3FB), // --color-text-h
    muted: Color(0xFF8E9CB8), // --color-text-muted #8493B0, lifted for AA
    hint: Color(0xFF7C8BA8), // --color-text-hint, lifted for AA
    danger: Color(0xFFF87171), // --color-danger
    warning: Color(0xFFF5B544),
    success: Color(0xFF34D671), // --color-success
    successSoft: Color(0xFF10271D), // --color-success-bg
    telegram: Color(0xFF3BB4E8), // --color-tg
    heroStart: Color(0xFF0C1426), // --color-navy
    heroEnd: Color(0xFF1B2A4E), // --color-navy2
    heroAccent: Color(0xFF2B4FA8),
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
    shadow: Color(0x80000000), // --color-shadow rgba(0,0,0,.5)
  );

  /// Dark palette on pure black for OLED screens.
  static final black = dark.copyWith(
    canvas: Colors.black,
    surface: const Color(0xFF0B0F18),
    surfaceRaised: const Color(0xFF121826),
    border: const Color(0xFF1E283B),
    borderLight: const Color(0xFF17202F),
  );

  @override
  KaGoPalette copyWith({
    Color? brand,
    Color? brandStrong,
    Color? accent,
    Color? accentSoft,
    Color? accentTint,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? borderLight,
    Color? text,
    Color? muted,
    Color? hint,
    Color? danger,
    Color? warning,
    Color? success,
    Color? successSoft,
    Color? telegram,
    Color? heroStart,
    Color? heroEnd,
    Color? heroAccent,
    Color? heroBlob,
    Color? heroGlow,
    Color? heroText,
    Color? heroMuted,
    Color? shadow,
  }) =>
      KaGoPalette(
        brand: brand ?? this.brand,
        brandStrong: brandStrong ?? this.brandStrong,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        accentTint: accentTint ?? this.accentTint,
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        border: border ?? this.border,
        borderLight: borderLight ?? this.borderLight,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        hint: hint ?? this.hint,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
        success: success ?? this.success,
        successSoft: successSoft ?? this.successSoft,
        telegram: telegram ?? this.telegram,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
        heroAccent: heroAccent ?? this.heroAccent,
        heroBlob: heroBlob ?? this.heroBlob,
        heroGlow: heroGlow ?? this.heroGlow,
        heroText: heroText ?? this.heroText,
        heroMuted: heroMuted ?? this.heroMuted,
        shadow: shadow ?? this.shadow,
      );

  @override
  KaGoPalette lerp(KaGoPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return KaGoPalette(
      brand: mix(brand, other.brand),
      brandStrong: mix(brandStrong, other.brandStrong),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentTint: mix(accentTint, other.accentTint),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      borderLight: mix(borderLight, other.borderLight),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      hint: mix(hint, other.hint),
      danger: mix(danger, other.danger),
      warning: mix(warning, other.warning),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      telegram: mix(telegram, other.telegram),
      heroStart: mix(heroStart, other.heroStart),
      heroEnd: mix(heroEnd, other.heroEnd),
      heroAccent: mix(heroAccent, other.heroAccent),
      heroBlob: mix(heroBlob, other.heroBlob),
      heroGlow: mix(heroGlow, other.heroGlow),
      heroText: mix(heroText, other.heroText),
      heroMuted: mix(heroMuted, other.heroMuted),
      shadow: mix(shadow, other.shadow),
    );
  }
}

extension KaGoPaletteContext on BuildContext {
  KaGoPalette get kago =>
      Theme.of(this).extension<KaGoPalette>() ?? KaGoPalette.light;

  /// The card shadow of the design system (`0 4px 24px var(--color-shadow)`).
  List<BoxShadow> get kagoCardShadow => <BoxShadow>[
        BoxShadow(
            color: kago.shadow, blurRadius: 24, offset: const Offset(0, 4))
      ];
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
      outlineVariant: p.borderLight,
      onSurface: p.text,
      onSurfaceVariant: p.muted,
    );
    final button = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KaGoRadius.button));
    TextStyle heading(double size, {FontWeight weight = KaGoWeight.heading}) =>
        TextStyle(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: size >= 24 ? -.6 : -.2,
            height: 1.25,
            color: p.text);
    TextStyle body(double size,
            {FontWeight weight = KaGoWeight.body, Color? color}) =>
        TextStyle(
            fontSize: size,
            fontWeight: weight,
            height: 1.45,
            color: color ?? p.text);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: kagoFontFamily,
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
      dividerColor: p.borderLight,
      dividerTheme: DividerThemeData(color: p.borderLight, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: heading(20),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.accentSoft,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.accent : p.muted)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: kagoFontFamily,
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? KaGoWeight.bold
                : KaGoWeight.semiBold,
            color: states.contains(WidgetState.selected) ? p.accent : p.muted)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.accentSoft,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: p.accent),
        unselectedIconTheme: IconThemeData(color: p.muted),
        selectedLabelTextStyle: TextStyle(
            fontFamily: kagoFontFamily,
            color: p.accent,
            fontSize: 12,
            fontWeight: KaGoWeight.bold),
        unselectedLabelTextStyle: TextStyle(
            fontFamily: kagoFontFamily,
            color: p.muted,
            fontSize: 12,
            fontWeight: KaGoWeight.body),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceRaised,
        hintStyle: body(14, color: p.hint),
        labelStyle: body(14, color: p.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.md),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.md),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.md),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.surfaceRaised,
          disabledForegroundColor: p.hint,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: 15,
              fontWeight: KaGoWeight.bold),
          shape: button,
        ),
      ),
      // `.btn-secondary`: a tinted pill with a primary outline.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          backgroundColor: p.accentSoft,
          side: BorderSide(color: p.accentTint, width: 1.5),
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: 15,
              fontWeight: KaGoWeight.semiBold),
          shape: button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: 14,
              fontWeight: KaGoWeight.semiBold),
          shape: button,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surfaceRaised,
          foregroundColor: p.muted,
          selectedBackgroundColor: p.accentSoft,
          selectedForegroundColor: p.accent,
          side: BorderSide(color: p.border),
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: 13,
              fontWeight: KaGoWeight.semiBold),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KaGoRadius.button)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.accentSoft,
        selectedColor: p.accentTint,
        side: BorderSide(color: p.accentTint),
        labelStyle: TextStyle(
            fontFamily: kagoFontFamily,
            fontSize: 13,
            fontWeight: KaGoWeight.body,
            color: p.accent),
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KaGoRadius.lg),
            side: BorderSide(color: p.border)),
        titleTextStyle: heading(19),
        contentTextStyle: body(14, color: p.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(KaGoRadius.xl))),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        titleTextStyle: body(14, weight: KaGoWeight.semiBold),
        subtitleTextStyle: body(12, color: p.muted),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KaGoRadius.md)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? p.brand : null),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
            color: p.heroStart,
            borderRadius: BorderRadius.circular(KaGoRadius.sm)),
        textStyle: const TextStyle(
            fontFamily: kagoFontFamily, fontSize: 12, color: Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceRaised,
        circularTrackColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            brightness == Brightness.light ? p.text : p.surfaceRaised,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KaGoRadius.md)),
        contentTextStyle: TextStyle(
            fontFamily: kagoFontFamily,
            fontSize: 14,
            fontWeight: KaGoWeight.body,
            color: brightness == Brightness.light ? Colors.white : p.text),
      ),
      textTheme: TextTheme(
        headlineMedium: heading(28),
        headlineSmall: heading(24),
        titleLarge: heading(20),
        titleMedium: heading(16, weight: KaGoWeight.extraBold),
        titleSmall: body(13, weight: KaGoWeight.bold),
        bodyLarge: body(15),
        bodyMedium: body(14),
        bodySmall: body(12, color: p.muted),
        labelLarge: body(14, weight: KaGoWeight.semiBold),
        labelMedium: body(12, weight: KaGoWeight.semiBold),
        labelSmall: body(11, weight: KaGoWeight.semiBold, color: p.muted),
      ),
    );
  }
}
