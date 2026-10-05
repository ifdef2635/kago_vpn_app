import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/kago_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + .05) / (dark + .05);
}

void main() {
  final palettes = <String, KaGoPalette>{
    'light': KaGoPalette.light,
    'dark': KaGoPalette.dark,
    'black': KaGoPalette.black,
  };

  for (final entry in palettes.entries) {
    final p = entry.value;
    test('${entry.key}: text and icons are readable (WCAG AA 4.5:1)', () {
      for (final surface in <Color>[p.canvas, p.surface, p.surfaceRaised]) {
        for (final foreground in <Color>[
          p.text,
          p.muted,
          p.accent,
          p.danger,
          p.warning,
          p.success,
        ]) {
          expect(_contrast(foreground, surface), greaterThanOrEqualTo(4.5),
              reason: '$foreground on $surface');
        }
      }
      expect(_contrast(p.accent, p.accentSoft), greaterThanOrEqualTo(4.5),
          reason: 'accent on its tinted chip');
      expect(_contrast(p.success, p.successSoft), greaterThanOrEqualTo(4.5),
          reason: 'success on its pill');
    });

    test('${entry.key}: white on filled buttons and the hero card', () {
      expect(_contrast(Colors.white, p.brand), greaterThanOrEqualTo(4.5));
      for (final hero in <Color>[p.heroStart, p.heroEnd]) {
        expect(_contrast(p.heroText, hero), greaterThanOrEqualTo(7));
        expect(_contrast(p.heroMuted, hero), greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('the button blue matches usekago.net', () {
    expect(KaGoPalette.light.brand, const Color(0xFF2B5FD0));
  });
}
