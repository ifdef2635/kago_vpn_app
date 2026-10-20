import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kago_vpn/core/theme/kago_motion.dart';
import 'package:kago_vpn/core/theme/kago_theme.dart';
import 'package:kago_vpn/features/dashboard/power_orb.dart';

/// The motion of the main screen («Полярная орбита»): frames are drawn only
/// while something moves on a screen that is seen, and nothing moves when the
/// system asks for no animations.
void main() {
  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
        theme: KaGoTheme.light(),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: app!,
        ),
        home: Scaffold(body: Center(child: child)),
      );

  Widget orb({
    bool connected = false,
    bool busy = false,
    bool recovering = false,
    bool live = true,
    double activity = 0,
    VoidCallback? onPressed,
  }) =>
      PowerOrb(
        connected: connected,
        busy: busy,
        recovering: recovering,
        live: live,
        activity: activity,
        onPressed: onPressed ?? () {},
      );

  setUp(() => KagoIntro.reset(played: true));

  testWidgets('an idle orb draws no frames', (tester) async {
    await tester.pumpWidget(host(orb()));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
  });

  testWidgets('the first appearance sends one wave, then the orb rests',
      (tester) async {
    KagoIntro.reset();
    await tester.pumpWidget(host(orb()));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.binding.hasScheduledFrame, isTrue);
    // pumpAndSettle fails if the frames never stop.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('the handshake runs while connecting and stops off screen',
      (tester) async {
    await tester.pumpWidget(host(orb(busy: true)));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isTrue);
    // No spinner: the comets show the progress.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(host(orb(busy: true, live: false)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('connecting closes the ring and keeps the satellites moving',
      (tester) async {
    await tester.pumpWidget(host(orb(busy: true)));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(host(orb(connected: true, activity: .8)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

    // Another tab: the orbit stops.
    await tester.pumpWidget(host(orb(connected: true, live: false)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Turning the VPN off on a visible screen: the satellites drift away and
    // the frames stop by themselves.
    await tester.pumpWidget(host(orb(connected: true)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(host(orb()));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byIcon(Icons.power_settings_new_rounded), findsOneWidget);
  });

  testWidgets('restoring the connection shows the comets', (tester) async {
    await tester.pumpWidget(host(orb(connected: true, recovering: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('without system animations: static, spinner while busy',
      (tester) async {
    KagoIntro.reset();
    await tester.pumpWidget(host(orb(), reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(host(orb(busy: true), reduced: true));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(host(orb(connected: true), reduced: true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
  });

  testWidgets('a tap reaches onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(orb(onPressed: () => taps++)));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  double opacityOf(WidgetTester tester) => tester
      .widget<FadeTransition>(find
          .descendant(
              of: find.byType(KagoEntrance),
              matching: find.byType(FadeTransition))
          .first)
      .opacity
      .value;

  testWidgets('the entrance plays once per run of the app', (tester) async {
    KagoIntro.reset();
    await tester
        .pumpWidget(host(const KagoEntrance(order: 2, child: Text('KAGO'))));
    expect(opacityOf(tester), 0);
    await tester.pumpAndSettle();
    expect(opacityOf(tester), 1);
    expect(KagoIntro.played, isTrue);

    // A new mount (a language switch rebuilds the screens) shows at once.
    await tester.pumpWidget(host(const SizedBox()));
    await tester
        .pumpWidget(host(const KagoEntrance(order: 2, child: Text('KAGO'))));
    expect(opacityOf(tester), 1);
  });

  testWidgets('the entrance is skipped without system animations',
      (tester) async {
    KagoIntro.reset();
    await tester.pumpWidget(
        host(const KagoEntrance(order: 3, child: Text('KAGO')), reduced: true));
    expect(opacityOf(tester), 1);
  });
}
