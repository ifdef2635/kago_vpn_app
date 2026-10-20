import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motion tokens of the KAGO interface («Полярная орбита»): one rhythm and
/// one set of curves for every animation of the app, so separate pieces read
/// as one brand.
abstract final class KaGoMotion {
  /// Hover and press feedback.
  static const Duration quick = Duration(milliseconds: 160);

  /// State changes on screen: colours, icons.
  static const Duration base = Duration(milliseconds: 320);

  /// Content entering the screen.
  static const Duration slow = Duration(milliseconds: 560);

  /// The step between items that enter one after another.
  static const Duration stagger = Duration(milliseconds: 70);

  /// Arriving: a quick start and a long, soft landing.
  static const Curve enter = Cubic(.22, 1, .36, 1);

  /// Moving between two states that are both on screen.
  static const Curve move = Cubic(.65, 0, .35, 1);

  /// A landing with a barely visible overshoot (the mark, a released press).
  static const Curve settle = Cubic(.34, 1.36, .64, 1);
}

/// The first appearance of the main screen plays once per run of the app.
/// Later mounts (a language switch rebuilds every screen) show their content
/// at once.
abstract final class KagoIntro {
  static bool _played = false;

  static bool get played => _played;

  /// Marks the intro as played after the current frame, so every widget of
  /// the intro mounted in this frame still plays.
  static void markPlayed() {
    if (_played) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _played = true);
  }

  @visibleForTesting
  static void reset({bool played = false}) => _played = played;
}

/// Fades [child] in and slides it from [offset] into place, [order] steps of
/// [KaGoMotion.stagger] after the screen appears. Plays only with the first
/// appearance of the app ([KagoIntro]) and never when the system asks for
/// less motion.
class KagoEntrance extends StatefulWidget {
  const KagoEntrance({
    super.key,
    required this.order,
    required this.child,
    this.offset = const Offset(0, 14),
  });

  final int order;
  final Offset offset;
  final Widget child;

  @override
  State<KagoEntrance> createState() => _KagoEntranceState();
}

class _KagoEntranceState extends State<KagoEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final delay = KaGoMotion.stagger * widget.order;
    final total = delay + KaGoMotion.slow;
    _controller = AnimationController(vsync: this, duration: total);
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: KaGoMotion.enter,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KagoIntro.played || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      KagoIntro.markPlayed();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _progress,
        child: AnimatedBuilder(
          animation: _progress,
          builder: (context, child) => Transform.translate(
            offset: widget.offset * (1 - _progress.value),
            child: child,
          ),
          child: widget.child,
        ),
      );
}

/// The KAGO mark arriving: it grows from 82 % with a soft landing, then a
/// band of light slides across it like a glint on ice. The mark is only
/// scaled uniformly, so the penguin keeps its proportions.
class KagoMarkReveal extends StatefulWidget {
  const KagoMarkReveal({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  State<KagoMarkReveal> createState() => _KagoMarkRevealState();
}

class _KagoMarkRevealState extends State<KagoMarkReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1060),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, .23, curve: Curves.easeOut),
  );
  late final Animation<double> _scale =
      Tween<double>(begin: .82, end: 1).animate(CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, .45, curve: KaGoMotion.settle),
  ));
  late final Animation<double> _glint = CurvedAnimation(
    parent: _controller,
    curve: const Interval(.34, 1, curve: KaGoMotion.move),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KagoIntro.played || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      KagoIntro.markPlayed();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The mark's own corner radius (rx 28 of 120 in kago-mark.svg).
    final radius = BorderRadius.circular(widget.size * 28 / 120);
    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Stack(
          children: <Widget>[
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: radius,
                  child: CustomPaint(painter: _GlintPainter(_glint)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A diagonal band of white that crosses the mark once; brightest in the
/// middle of its pass. Invisible on the white penguin, a shine on the blue.
class _GlintPainter extends CustomPainter {
  _GlintPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    if (t <= 0 || t >= 1) return;
    final centre = -.25 + 1.5 * t;
    const half = .16;
    double stop(double value) => value.clamp(0.0, 1.0);
    const clear = Color(0x00FFFFFF);
    final bounds = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          clear,
          clear,
          Colors.white.withValues(alpha: .5 * math.sin(math.pi * t)),
          clear,
          clear,
        ],
        stops: <double>[
          0,
          stop(centre - half),
          stop(centre),
          stop(centre + half),
          1,
        ],
      ).createShader(bounds);
    canvas.drawRect(bounds, paint);
  }

  @override
  bool shouldRepaint(_GlintPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
