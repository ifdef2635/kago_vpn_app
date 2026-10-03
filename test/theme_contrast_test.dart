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
  test('the logo blue is exactly the KAGO logo color', () {
    expect(KaGoColors.brand, const Color(0xFF1A4780));
  });

  test('text and icons stay readable (WCAG AA, 4.5:1) on every surface', () {
    for (final surface in <Color>[
      KaGoColors.canvas,
      KaGoColors.surface,
      KaGoColors.surfaceRaised,
    ]) {
      for (final foreground in <Color>[
        KaGoColors.text,
        KaGoColors.muted,
        KaGoColors.accent,
        KaGoColors.accentSoft,
        KaGoColors.danger,
        KaGoColors.warning,
      ]) {
        expect(_contrast(foreground, surface), greaterThanOrEqualTo(4.5),
            reason: '$foreground on $surface');
      }
    }
  });

  test('white on the logo blue (filled buttons) is readable', () {
    expect(_contrast(Colors.white, KaGoColors.brand), greaterThanOrEqualTo(7));
  });
}
