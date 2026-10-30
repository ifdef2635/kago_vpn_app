import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/app_widgets.dart';
import 'package:kago_vpn/core/theme/kago_theme.dart';

void main() {
  for (final reduced in <bool>[false, true]) {
    testWidgets('press feedback keeps the action and reduced motion=$reduced',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          theme: KaGoTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: Scaffold(
                body: KagoPressFeedback(
                    child: FilledButton(
                        onPressed: () => taps++,
                        child: const Text('Connect')))),
          )));
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(FilledButton)));
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduced ? 1 : .97);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 160));
      expect(taps, 1);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });
  }
  test('secondary hover and primary press retain readable text in both themes',
      () {
    for (final theme in <ThemeData>[KaGoTheme.light(), KaGoTheme.dark()]) {
      final p = theme.extension<KaGoPalette>()!;
      final filled = theme.filledButtonTheme.style!;
      expect(
          filled.backgroundColor!.resolve(<WidgetState>{WidgetState.pressed}),
          p.brandStrong);
      final outline = theme.outlinedButtonTheme.style!;
      expect(
          outline.backgroundColor!.resolve(<WidgetState>{WidgetState.hovered}),
          p.accentTint);
      expect(
          outline.foregroundColor!.resolve(<WidgetState>{WidgetState.hovered}),
          p.accentStrong);
      expect(
          outline.side!.resolve(<WidgetState>{WidgetState.focused})!.width, 2);
    }
  });
}
