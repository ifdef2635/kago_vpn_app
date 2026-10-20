import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/theme/kago_motion.dart';
import '../../core/theme/kago_theme.dart';

/// The power button of the main screen in the motion of «Полярная орбита»
/// (the polar orbit of the KAGO penguin):
///
/// * connecting — two comets circle the button in opposite directions: the
///   handshake of the app and the server;
/// * connected — a ring closes in the site's blue-to-green light (the glows of
///   its hero card), sends one wave outwards, and three satellites stay on
///   the orbit; they speed up with the real traffic ([activity]);
/// * disconnecting — the satellites drift off the orbit and fade;
/// * the connection is being restored — the comets return in the warning
///   colour.
///
/// The button itself stays a regular [FilledButton] (focus, keyboard, screen
/// readers), blue when off and red («stop») when on, as before; the new colour
/// spreads from the centre of the button instead of fading through purple.
/// Frames are
/// drawn only while something moves and the screen is [live]; with animations
/// turned off in the system everything is static and progress is the usual
/// spinner.
class PowerOrb extends StatefulWidget {
  const PowerOrb({
    super.key,
    required this.connected,
    required this.busy,
    required this.onPressed,
    this.recovering = false,
    this.live = true,
    this.activity = 0,
  });

  /// The widget is a square of this side (the halos of the former button).
  static const double extent = 152;

  /// The VPN is up (or being restored).
  final bool connected;

  /// A start or stop is in progress.
  final bool busy;

  /// The connection dropped and is being restored.
  final bool recovering;
  final VoidCallback onPressed;

  /// False while the main screen is not seen (another tab, the app hidden):
  /// the orbit then stops, so no frames are drawn for nobody.
  final bool live;

  /// Traffic now, 0…1: how fast the satellites go.
  final double activity;

  @override
  State<PowerOrb> createState() => _PowerOrbState();
}

enum _Orbit { idle, handshake, secured }

enum _Wave { invite, sealed }

class _Ripple {
  const _Ripple(this.start, this.kind);

  /// Seconds on the orb's clock.
  final double start;
  final _Wave kind;
}

class _PowerOrbState extends State<PowerOrb> with TickerProviderStateMixin {
  // Radii inside the 152 px square.
  static const double _outer = 76;
  static const double _inner = 64;
  static const double _track = 70;
  static const double _button = 108;

  // Timings in seconds.
  static const double _handshakeTurn = 1.6;
  static const double _sealSweep = .48;
  static const double _sealFade = .52;
  static const double _rippleLife = .9;
  static const double _inviteAt = .62;

  late final Ticker _ticker = createTicker(_tick);
  late final AnimationController _hover =
      AnimationController(vsync: this, duration: KaGoMotion.quick);
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
    reverseDuration: const Duration(milliseconds: 360),
  );
  late final Animation<double> _pressScale =
      Tween<double>(begin: 1, end: .94).animate(CurvedAnimation(
    parent: _press,
    curve: Curves.easeOut,
    reverseCurve: KaGoMotion.settle.flipped,
  ));
  // The colour of the button spreading from its centre (blue ↔ red).
  late final AnimationController _toneReveal =
      AnimationController(vsync: this, duration: KaGoMotion.base, value: 1);
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Listenable _repaint =
      Listenable.merge(<Listenable>[_frame, _hover, _toneReveal]);
  Color _toneFrom = Colors.transparent;
  Color _toneTo = Colors.transparent;

  _Orbit _orbit = _Orbit.idle;
  bool _reduced = false;

  // The orb's clock: seconds of animated time, kept across ticker restarts.
  double _now = 0;
  double _clockBase = 0;

  double _arcAlpha = 0;
  double _satAlpha = 0;
  double _spin = 0;
  double _speed = 0;
  double? _sealStart;
  final List<_Ripple> _ripples = <_Ripple>[];

  _Orbit get _target => widget.busy || widget.recovering
      ? _Orbit.handshake
      : widget.connected
          ? _Orbit.secured
          : _Orbit.idle;

  bool get _motion => widget.live && !_reduced;

  Color _toneOf(KaGoPalette p) => widget.connected ? p.danger : p.brand;

  /// The colour the button shows now (the reveal grows from the centre).
  double get _reveal => KaGoMotion.move.transform(_toneReveal.value);

  /// Radians per second of the satellites: a calm drift at rest, up to about
  /// two-thirds of a turn per second under heavy traffic.
  double get _cruise =>
      2 * math.pi * (.1 + .55 * widget.activity.clamp(0.0, 1.0));

  bool get _moving =>
      _orbit != _Orbit.idle ||
      _sealStart != null ||
      _ripples.isNotEmpty ||
      _arcAlpha > 0 ||
      _satAlpha > 0;

  @override
  void initState() {
    super.initState();
    _orbit = _target;
    _arcAlpha = _orbit == _Orbit.handshake ? 1 : 0;
    _satAlpha = _orbit == _Orbit.secured ? 1 : 0;
    _speed = _cruise;
    if (_orbit == _Orbit.idle && !KagoIntro.played) {
      // The first appearance of the screen ends with one soft wave from the
      // button: it is ready.
      _ripples.add(const _Ripple(_inviteAt, _Wave.invite));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    // First build or a theme switch: the colour is set without a reveal.
    final tone = _toneOf(context.kago);
    if (tone != _toneTo) {
      _toneFrom = tone;
      _toneTo = tone;
      _toneReveal.value = 1;
    }
    _sync();
  }

  @override
  void didUpdateWidget(PowerOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _target;
    if (next != _orbit) {
      _sealStart = null;
      if (next == _Orbit.secured && _motion) {
        // The connection has just come up: the ring closes, then the wave.
        _sealStart = _now;
        _ripples.add(_Ripple(_now + _sealSweep, _Wave.sealed));
      }
      _orbit = next;
    }
    final tone = _toneOf(context.kago);
    if (tone != _toneTo) {
      _toneFrom = _reveal < .5 ? _toneFrom : _toneTo;
      _toneTo = tone;
      if (_reduced) {
        _toneReveal.value = 1;
      } else {
        _toneReveal.forward(from: 0);
      }
    }
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hover.dispose();
    _press.dispose();
    _toneReveal.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Starts or stops the frames: they run only while something moves on a
  /// screen that is seen. Without motion every value jumps to its end.
  void _sync() {
    if (!_motion) {
      if (_ticker.isActive) _ticker.stop();
      _arcAlpha = _orbit == _Orbit.handshake ? 1 : 0;
      _satAlpha = _orbit == _Orbit.secured ? 1 : 0;
      _speed = _cruise;
      _sealStart = null;
      _ripples.clear();
    } else if (_moving && !_ticker.isActive) {
      _clockBase = _now;
      _ticker.start();
    }
    _frame.value++;
  }

  void _tick(Duration elapsed) {
    final now = _clockBase + elapsed.inMicroseconds / 1e6;
    // A dropped frame must not make the orbit jump.
    final dt = math.min(now - _now, .05);
    _now = now;
    final seal = _sealStart;
    final sealing = seal != null && now - seal < _sealSweep + .12;
    // Comets only during the handshake; satellites once the ring has closed
    // (they dock slowly and leave quickly).
    _arcAlpha = _approach(_arcAlpha, _orbit == _Orbit.handshake ? 1 : 0, dt, 9);
    final docked = _orbit == _Orbit.secured && !sealing;
    _satAlpha = _approach(_satAlpha, docked ? 1 : 0, dt, docked ? 4 : 7);
    _speed += (_cruise - _speed) * math.min(1.0, dt * 2.5);
    _spin = (_spin + _speed * dt) % (2 * math.pi);
    if (seal != null && now - seal > _sealSweep + _sealFade) _sealStart = null;
    _ripples.removeWhere((ripple) => now - ripple.start > _rippleLife);
    _frame.value++;
    if (!_moving) _ticker.stop();
  }

  static double _approach(
      double value, double target, double dt, double rate) {
    final next = value + (target - value) * math.min(1.0, dt * rate);
    return (next - target).abs() < .004 ? target : next;
  }

  void _setHover(bool inside) {
    if (_reduced) {
      _hover.value = inside ? 1 : 0;
    } else if (inside) {
      _hover.forward();
    } else {
      _hover.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.kago;
    final duration = _reduced ? Duration.zero : KaGoMotion.base;
    final spinner = _reduced && widget.busy;
    final icon = AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation.drive(CurveTween(curve: KaGoMotion.enter)),
        child: RotationTransition(
          turns: animation.drive(Tween<double>(begin: -.18, end: 0)
              .chain(CurveTween(curve: KaGoMotion.enter))),
          child: ScaleTransition(
            scale: animation.drive(Tween<double>(begin: .6, end: 1)
                .chain(CurveTween(curve: KaGoMotion.settle))),
            child: child,
          ),
        ),
      ),
      child: spinner
          ? const SizedBox(
              key: ValueKey<String>('busy'),
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Colors.white),
            )
          : AnimatedOpacity(
              key: ValueKey<bool>(widget.connected),
              opacity: widget.busy ? .62 : 1,
              duration: duration,
              child: Icon(
                widget.connected
                    ? Icons.stop_rounded
                    : Icons.power_settings_new_rounded,
                size: 44,
              ),
            ),
    );
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: PowerOrb.extent,
        child: CustomPaint(
          painter: _OrbPainter(
            state: this,
            palette: p,
            recovering: widget.recovering,
          ),
          child: Center(
            child: MouseRegion(
              onEnter: (_) => _setHover(true),
              onExit: (_) => _setHover(false),
              child: Listener(
                onPointerDown: (_) {
                  if (!_reduced) _press.forward();
                },
                onPointerUp: (_) => _press.reverse(),
                onPointerCancel: (_) => _press.reverse(),
                child: ScaleTransition(
                  scale: _pressScale,
                  child: SizedBox.square(
                    dimension: _button,
                    // The disc is painted here, so it scales with the press;
                    // the button on top keeps focus, ink and semantics.
                    child: CustomPaint(
                      painter: _DiscPainter(this),
                      child: FilledButton(
                        onPressed: widget.onPressed,
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: EdgeInsets.zero,
                          backgroundColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                        ),
                        child: icon,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The disc of the button: the previous colour, and the new one growing from
/// the centre over it ([KaGoMotion.base]).
class _DiscPainter extends CustomPainter {
  _DiscPainter(this.state) : super(repaint: state._toneReveal);

  final _PowerOrbState state;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final reveal = state._reveal;
    if (reveal < 1) {
      canvas.drawCircle(centre, radius, Paint()..color = state._toneFrom);
    }
    if (reveal > 0) {
      canvas.drawCircle(
          centre, radius * reveal, Paint()..color = state._toneTo);
    }
  }

  @override
  bool shouldRepaint(_DiscPainter oldDelegate) => oldDelegate.state != state;
}

/// Draws everything around the button: the two halos, the waves, the comets
/// of the handshake, the closing ring and the satellites.
class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.state,
    required this.palette,
    required this.recovering,
  }) : super(repaint: state._repaint);

  final _PowerOrbState state;
  final KaGoPalette palette;
  final bool recovering;

  static const double _outer = _PowerOrbState._outer;
  static const double _inner = _PowerOrbState._inner;
  static const double _track = _PowerOrbState._track;

  @override
  void paint(Canvas canvas, Size size) {
    final s = state;
    final centre = size.center(Offset.zero);
    final hover = s._hover.value;
    final motion = s._motion;
    final now = s._now;
    // The halos follow the button's colour; the orbit takes the new one.
    final tone = Color.lerp(s._toneFrom, s._toneTo, s._reveal)!;
    final arcTone = recovering ? palette.warning : s._toneTo;

    // The halos of the button; the outer one opens a little on hover.
    final outer = _outer + 3 * hover;
    canvas.drawCircle(
        centre, outer, Paint()..color = tone.withValues(alpha: .08));
    canvas.drawCircle(
        centre,
        outer - .5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = tone.withValues(alpha: .20 + .10 * hover));
    canvas.drawCircle(
        centre, _inner, Paint()..color = tone.withValues(alpha: .14));
    canvas.drawCircle(
        centre,
        _inner - .5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = tone.withValues(alpha: .28 + .12 * hover));

    // Waves: one when the screen first appears, one when the ring closes.
    for (final ripple in s._ripples) {
      final age = (now - ripple.start) / _PowerOrbState._rippleLife;
      if (age < 0 || age > 1) continue;
      final e = Curves.easeOutCubic.transform(age);
      final sealed = ripple.kind == _Wave.sealed;
      final color = sealed ? palette.heroGlow : tone;
      // The invite starts at the inner halo, so it is not lost under it.
      final radius = sealed ? 54 + 40 * e : 62 + 32 * e;
      if (sealed) {
        canvas.drawCircle(centre, radius,
            Paint()..color = color.withValues(alpha: .10 * (1 - e)));
      }
      canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 - 1.4 * e
            ..color = color.withValues(alpha: (sealed ? .55 : .45) * (1 - e)));
    }

    final track = Rect.fromCircle(center: centre, radius: _track);

    // The handshake: two comets going opposite ways.
    if (s._arcAlpha > 0) {
      if (motion) {
        final turn = 2 * math.pi * now / _PowerOrbState._handshakeTurn;
        final length = .9 + .3 * math.sin(now * 2.4);
        _comet(canvas, track, -math.pi / 2 + turn, length, 1, arcTone,
            s._arcAlpha);
        _comet(canvas, track, math.pi / 2 - turn * .86, length, -1, arcTone,
            s._arcAlpha);
      } else {
        _comet(canvas, track, -math.pi / 4, .9, 1, arcTone, s._arcAlpha);
        _comet(canvas, track, math.pi * 3 / 4, .9, 1, arcTone, s._arcAlpha);
      }
    }

    // The ring closing from the top, blue to green and back to blue.
    final seal = s._sealStart;
    if (seal != null && motion) {
      final age = now - seal;
      final sweep = Curves.easeInOutCubic
          .transform((age / _PowerOrbState._sealSweep).clamp(0.0, 1.0));
      final fade = age <= _PowerOrbState._sealSweep
          ? 1.0
          : 1 -
              ((age - _PowerOrbState._sealSweep) / _PowerOrbState._sealFade)
                  .clamp(0.0, 1.0);
      if (sweep > 0 && fade > 0) {
        canvas.drawArc(
            track,
            -math.pi / 2,
            2 * math.pi * sweep,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5 + 1.5 * fade
              ..shader = SweepGradient(
                colors: <Color>[
                  palette.heroBlob.withValues(alpha: fade),
                  palette.heroGlow.withValues(alpha: fade),
                  palette.heroBlob.withValues(alpha: fade),
                ],
                transform: const GradientRotation(-math.pi / 2),
              ).createShader(track));
        if (sweep < 1) {
          final head = -math.pi / 2 + 2 * math.pi * sweep;
          canvas.drawCircle(
              centre + Offset(math.cos(head), math.sin(head)) * _track,
              3,
              Paint()
                ..color = Color.lerp(palette.heroGlow, Colors.white, .5)!);
        }
      }
    }

    // Satellites: they dock onto the orbit from outside and drift away when
    // the VPN turns off.
    if (s._satAlpha > 0) {
      final radius = _track + 12 * (1 - s._satAlpha);
      final orbit = Rect.fromCircle(center: centre, radius: radius);
      final base = motion ? s._spin : 0.0;
      for (var i = 0; i < 3; i++) {
        final angle = -math.pi / 2 + base + i * 2 * math.pi / 3;
        _comet(canvas, orbit, angle, .42, 1, s._toneTo, s._satAlpha * .85,
            width: 2, dot: 2.4);
      }
    }
  }

  /// An arc that fades from its tail to a bright head at [head] (radians),
  /// [length] radians long, moving clockwise (1) or anticlockwise (-1).
  void _comet(Canvas canvas, Rect rect, double head, double length,
      double direction, Color color, double alpha,
      {double width = 3, double dot = 2.6}) {
    final start = direction > 0 ? head - length : head;
    final solid = color.withValues(alpha: alpha);
    final clear = color.withValues(alpha: 0);
    // Butt caps: a round cap at the tail would wrap around the sweep gradient
    // and show the solid colour.
    canvas.drawArc(
        rect,
        start,
        length,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = SweepGradient(
            endAngle: length,
            colors: direction > 0
                ? <Color>[clear, solid]
                : <Color>[solid, clear],
            transform: GradientRotation(start),
          ).createShader(rect));
    canvas.drawCircle(
        rect.center + Offset(math.cos(head), math.sin(head)) * (rect.width / 2),
        dot,
        Paint()
          ..color = Color.lerp(color, Colors.white, .35)!
              .withValues(alpha: alpha));
  }

  @override
  bool shouldRepaint(_OrbPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.palette != palette ||
      oldDelegate.recovering != recovering;
}
