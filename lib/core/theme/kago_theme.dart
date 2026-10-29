import 'dart:io';

import 'package:flutter/material.dart';

/// Fallback fonts that draw country flag emoji (Windows).
const kagoFlagFonts = <String>['KagoFlags'];

/// Единое семейство KAGO из DESIGN.md, локальные файлы SIL OFL.
const kagoFontFamily = 'Onest';

/// Corner radii of the design system (`--radius-*` of globals.css).
abstract final class KaGoRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double card = 14;
  static const double panel = 18;
  static const double hero = 22;
  static const double sheet = 24;

  /// Pills and chips (`border-radius: 999px`).
  static const double pill = 999;

  /// Filled buttons of the site (`.btn-primary`).
  static const double button = 10;
}

/// Font weights of the design system.
abstract final class KaGoWeight {
  /// Основной текст макета.
  static const body = FontWeight.w400;
  static const semiBold = FontWeight.w600;
  static const bold = FontWeight.w700;
  static const extraBold = FontWeight.w800;

  /// Заголовки бренда: Onest ExtraBold, основной текст — Regular.
  static const heading = FontWeight.w800;
  static const appTitle = FontWeight.w900;
}

/// Роли типографики DESIGN.md в логических пикселях Flutter.
/// Размер текста дополнительно масштабируется настройками системы.
abstract final class KaGoText {
  static const double display = 34;
  static const double pageTitle = 32;
  static const double appTitle = 26;
  static const double headingLarge = 30;
  static const double heading = 24;
  static const double titleLarge = 22;
  static const double title = 20;
  static const double lead = 18;
  static const double body = 16;
  static const double bodySmall = 15;
  static const double secondary = 14;
  static const double label = 13;
  static const double caption = 12;
  static const double meta = 11;
}

/// Отступы из DESIGN.md; карточки приложения плотнее маркетинговых секций.
abstract final class KaGoSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double section = 48;
  static const double page = 64;
}

/// Signal Cobalt, Ice Wash и Night Navy из фирменной системы KAGO.
@immutable
class KaGoPalette extends ThemeExtension<KaGoPalette> {
  const KaGoPalette({
    required this.brand,
    required this.brandStrong,
    required this.accent,
    required this.accentStrong,
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

  /// Текст на более насыщенной подложке, включая hover вторичных кнопок.
  final Color accentStrong;

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

  static const light = KaGoPalette(
    brand: Color(0xFF2B5FD0),
    brandStrong: Color(0xFF1E47A8),
    accent: Color(0xFF2B5FD0),
    accentStrong: Color(0xFF1E47A8),
    accentSoft: Color(0xFFE8F0FF),
    accentTint: Color(0xFFD2E1FF),
    canvas: Color(0xFFEDF2FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF4F8FE),
    border: Color(0xFFE2E8F0),
    borderLight: Color(0xFFEAEFF7),
    text: Color(0xFF13203F),
    muted: Color(0xFF42526B),
    hint: Color(0xFF5B6B84),
    // Текстовые функциональные оттенки слегка темнее образца: AA на Ice Wash.
    danger: Color(0xFFD12525),
    warning: Color(0xFF92400E),
    success: Color(0xFF147A3A),
    successSoft: Color(0xFFE7F8EE),
    telegram: Color(0xFF1772A5),
    heroStart: Color(0xFF16223F),
    heroEnd: Color(0xFF1E2E54),
    heroAccent: Color(0xFF1E47A8),
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
    shadow: Color(0x1A14285A),
  );

  static const dark = KaGoPalette(
    brand: Color(0xFF3563D4),
    brandStrong: Color(0xFF2A55BD),
    accent: Color(0xFF5B8CF5),
    accentStrong: Color(0xFF82A6F9),
    accentSoft: Color(0xFF17243F),
    accentTint: Color(0xFF213256),
    canvas: Color(0xFF080B14),
    surface: Color(0xFF121A2E),
    surfaceRaised: Color(0xFF16203A),
    border: Color(0xFF283452),
    borderLight: Color(0xFF1E2842),
    text: Color(0xFFEEF3FB),
    muted: Color(0xFF8E9CB8),
    hint: Color(0xFF808EAB),
    danger: Color(0xFFF87171),
    warning: Color(0xFFFDE68A),
    success: Color(0xFF34D671),
    successSoft: Color(0xFF10271D),
    telegram: Color(0xFF3BB4E8),
    heroStart: Color(0xFF16223F),
    heroEnd: Color(0xFF1E2E54),
    heroAccent: Color(0xFF1E47A8),
    heroBlob: Color(0xFF5B8CF5),
    heroGlow: Color(0xFF22C55E),
    heroText: Color(0xFFFFFFFF),
    heroMuted: Color(0xFFC3CFEA),
    shadow: Color(0x80000000),
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
    Color? accentStrong,
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
        accentStrong: accentStrong ?? this.accentStrong,
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
      accentStrong: mix(accentStrong, other.accentStrong),
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

  /// Мягкая тень кабинета из DESIGN.md: глубина сначала задаётся тоном.
  List<BoxShadow> get kagoCardShadow => <BoxShadow>[
        BoxShadow(
            color: kago.shadow, blurRadius: 14, offset: const Offset(0, 2)),
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
            fontFamily: kagoFontFamily,
            fontSize: size,
            fontWeight: weight,
            letterSpacing: size >= 24 ? -.6 : -.2,
            height: size >= KaGoText.appTitle ? 1.15 : 1.3,
            color: p.text);
    TextStyle body(double size,
            {FontWeight weight = KaGoWeight.body, Color? color}) =>
        TextStyle(
            fontFamily: kagoFontFamily,
            fontSize: size,
            fontWeight: weight,
            height: size >= KaGoText.body ? 1.6 : 1.5,
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
        titleTextStyle: heading(KaGoText.title),
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
            fontSize: KaGoText.meta,
            fontWeight: states.contains(WidgetState.selected)
                ? KaGoWeight.bold
                : KaGoWeight.body,
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
            fontSize: KaGoText.caption,
            fontWeight: KaGoWeight.bold),
        unselectedLabelTextStyle: TextStyle(
            fontFamily: kagoFontFamily,
            color: p.muted,
            fontSize: KaGoText.caption,
            fontWeight: KaGoWeight.body),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.focused) ? p.surface : p.surfaceRaised),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: body(KaGoText.secondary, color: p.hint),
        labelStyle:
            body(KaGoText.label, weight: KaGoWeight.bold, color: p.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.sm),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.sm),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(KaGoRadius.sm),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.surfaceRaised,
          disabledForegroundColor: p.hint,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: KaGoText.bodySmall,
              fontWeight: KaGoWeight.bold),
          shape: button,
        ).copyWith(
          animationDuration: const Duration(milliseconds: 150),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? p.surfaceRaised
                  : states.contains(WidgetState.pressed) ||
                          states.contains(WidgetState.hovered)
                      ? p.brandStrong
                      : p.brand),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? BorderSide(color: p.accent, width: 2)
                  : BorderSide.none),
        ),
      ),
      // `.btn-secondary`: a tinted pill with a primary outline.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.accent,
          backgroundColor: p.accentSoft,
          side: BorderSide(color: p.accentTint, width: 1.5),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: KaGoText.bodySmall,
              fontWeight: FontWeight.w500),
          shape: button,
        ).copyWith(
          animationDuration: const Duration(milliseconds: 150),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? p.accentTint
                  : p.accentSoft),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled) ? p.hint : p.accentStrong),
          side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? p.accent
                  : p.accentTint,
              width: states.contains(WidgetState.focused) ? 2 : 1.5)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          textStyle: const TextStyle(
              fontFamily: kagoFontFamily,
              fontSize: KaGoText.secondary,
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
              fontSize: KaGoText.label,
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
            fontSize: KaGoText.label,
            fontWeight: KaGoWeight.body,
            color: p.accentStrong),
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KaGoRadius.xl),
            side: BorderSide(color: p.border)),
        titleTextStyle: heading(KaGoText.title),
        contentTextStyle: body(KaGoText.secondary, color: p.muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(KaGoRadius.sheet))),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        titleTextStyle: body(KaGoText.secondary, weight: KaGoWeight.semiBold),
        subtitleTextStyle: body(KaGoText.caption, color: p.muted),
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
            fontFamily: kagoFontFamily,
            fontSize: KaGoText.caption,
            color: Colors.white),
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
            fontSize: KaGoText.secondary,
            fontWeight: KaGoWeight.body,
            color: brightness == Brightness.light ? Colors.white : p.text),
      ),
      textTheme: TextTheme(
        headlineMedium: heading(KaGoText.pageTitle),
        headlineSmall: heading(KaGoText.appTitle, weight: KaGoWeight.appTitle),
        titleLarge: heading(KaGoText.title),
        titleMedium: heading(KaGoText.lead),
        titleSmall: body(KaGoText.label, weight: KaGoWeight.bold),
        bodyLarge: body(KaGoText.body),
        bodyMedium: body(KaGoText.secondary),
        bodySmall: body(KaGoText.caption, color: p.muted),
        labelLarge: body(KaGoText.secondary, weight: KaGoWeight.semiBold),
        labelMedium: body(KaGoText.caption, weight: KaGoWeight.semiBold),
        labelSmall:
            body(KaGoText.meta, weight: KaGoWeight.semiBold, color: p.muted),
      ),
    );
  }
}
