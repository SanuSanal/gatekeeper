import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'logo.dart';

/// Launch splash. It continues the native launch screen (res/drawable/launch_background.xml on
/// Android 11, the SplashScreen API on 12+): same green, and the mark at the same size and position, so
/// the hand-over from Android to Flutter is invisible. Underneath, a car drives up, the barrier lifts and
/// the car drives through, then [onFinished] fires. Tapping skips it; with reduced motion it is skipped.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.duration = defaultDuration, this.onFinished});

  static const defaultDuration = Duration(milliseconds: 2200);

  // The native splash draws ic_launcher_foreground (108dp canvas) at 288dp. build_kit.py fits the mark
  // into a 52-unit box on that canvas and lifts it by 1.5% of the box for optical centring.
  static const _nativeIconDp = 288.0;
  static const markSize = _nativeIconDp * 52 / 108;
  static const _opticalLift = 0.015 * markSize;

  final Duration duration;
  final VoidCallback? onFinished;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: widget.duration);
  bool _started = false;
  bool _finished = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // No animation: show the end state and report on the next frame (not during this build).
    if (widget.duration == Duration.zero || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      _anim.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      _anim.forward().then((_) => _finish()); // never completes if disposed first
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const markSize = SplashScreen.markSize;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: GateKeeperMark.brandGreen,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: LayoutBuilder(
            builder: (context, box) {
              final below = box.maxHeight / 2 + markSize / 2;
              return Stack(
                children: [
                  Center(
                    child: Transform.translate(
                      offset: const Offset(0, -SplashScreen._opticalLift),
                      child: const GateKeeperMark(size: markSize, barColor: GateKeeperMark.brandCream),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: below + 24,
                    child: FadeTransition(
                      opacity: CurvedAnimation(parent: _anim, curve: const Interval(0.55, 0.85, curve: Curves.easeOut)),
                      child: const Text(
                        'GateKeeper',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: GateKeeperMark.brandCream,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: below + 140, // leaves room for the raised arm under the name
                    height: _GateScenePainter.height,
                    child: ExcludeSemantics(
                      child: RepaintBoundary(child: CustomPaint(painter: _GateScenePainter(_anim))),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A side view of a road with a barrier gate. Timeline over the animation (0..1): the car drives in and
/// stops at the gate (0–0.40), the arm lifts as it arrives (0.30–0.52), the car drives through (0.52–0.90).
class _GateScenePainter extends CustomPainter {
  _GateScenePainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const height = 52.0;
  static const _road = height - 4; // y of the road surface
  static const _carW = 72.0;
  static const _openAngle = 80 * math.pi / 180;
  static const _ink = Color(0xFF17231F);

  static double _seg(double v, double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final w = size.width;
    final gateX = w * 0.55;
    final armLen = math.min(84.0, w * 0.25);
    final cream = Paint()..color = GateKeeperMark.brandCream;

    // Road.
    canvas.drawLine(
      const Offset(0, _road + 1),
      Offset(w, _road + 1),
      Paint()
        ..color = GateKeeperMark.brandCream.withValues(alpha: 0.35)
        ..strokeWidth = 2,
    );

    // Gate post, arm and pivot (the logo's amber dot).
    final pivot = Offset(gateX, _road - 30);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(gateX - 3, pivot.dy, gateX + 3, _road), const Radius.circular(3)),
      cream,
    );
    final lift = Curves.easeInOut.transform(_seg(v, 0.30, 0.52)) * _openAngle;
    final armEnd = pivot + Offset(math.cos(-lift), math.sin(-lift)) * armLen;
    canvas.drawLine(
      pivot,
      armEnd,
      Paint()
        ..color = GateKeeperMark.brandCream
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 6, Paint()..color = GateKeeperMark.brandAmber);

    // Car: drives in, waits for the arm, drives through.
    final start = -_carW - 8, stop = gateX - 14 - _carW, end = w + 8;
    final x = v < 0.52
        ? start + (stop - start) * Curves.easeOutCubic.transform(_seg(v, 0, 0.40))
        : stop + (end - stop) * Curves.easeInCubic.transform(_seg(v, 0.52, 0.90));
    canvas.save();
    canvas.translate(x, _road);
    _paintCar(canvas, cream);
    canvas.restore();
  }

  /// A right-facing car, 72 wide, with its wheels resting on y = 0.
  void _paintCar(Canvas canvas, Paint body) {
    final cabin = Path()
      ..moveTo(14, -21)
      ..lineTo(24, -32)
      ..lineTo(46, -32)
      ..lineTo(58, -21)
      ..close();
    canvas.drawPath(cabin, body);
    canvas.drawPath(
      cabin,
      Paint()
        ..color = body.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(0, -22, _carW, -7), const Radius.circular(6)), body);
    final glass = Paint()..color = GateKeeperMark.brandGreen;
    canvas.drawPath(
      Path()
        ..moveTo(20, -22)
        ..lineTo(26, -29)
        ..lineTo(34, -29)
        ..lineTo(34, -22)
        ..close(),
      glass,
    );
    canvas.drawPath(
      Path()
        ..moveTo(38, -22)
        ..lineTo(38, -29)
        ..lineTo(45, -29)
        ..lineTo(52, -22)
        ..close(),
      glass,
    );
    for (final cx in [17.0, 55.0]) {
      canvas.drawCircle(Offset(cx, -7), 7, Paint()..color = _ink);
      canvas.drawCircle(Offset(cx, -7), 2.5, body);
    }
  }

  @override
  bool shouldRepaint(_GateScenePainter old) => old.t != t;
}
