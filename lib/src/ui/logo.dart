import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The GateKeeper "Lift" mark: a pivot dot with three rising bars (the lifting arm drawn as signal bars).
/// Geometry mirrors design/logo/build_kit.py (MARKS["regular"]); keep them in sync.
class GateKeeperMark extends StatelessWidget {
  const GateKeeperMark({super.key, this.size = 32, this.barColor, this.dotColor = brandAmber});

  static const brandGreen = Color(0xFF1F6B5C);
  static const brandCream = Color(0xFFF3EFE4);
  static const brandAmber = Color(0xFFE8A33D);

  final double size;

  /// Defaults to the brand green, or cream on dark themes.
  final Color? barColor;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(barColor ?? (dark ? brandCream : brandGreen), dotColor),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.bar, this.dot);

  final Color bar;
  final Color dot;

  static const _hub = 26.0, _t = 28.0, _rs = 76.0;
  static const _angles = [0.0, -30.0, -60.0];
  static const _lengths = [44.0, 82.0, 120.0];

  static Offset _pt(double r, double deg) {
    final a = deg * math.pi / 180;
    return Offset(r * math.cos(a), r * math.sin(a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Bounding box of the construction (same as the generator).
    var minX = -_hub, minY = -_hub, maxX = _hub, maxY = _hub;
    final bars = <(Offset, Offset)>[];
    for (var i = 0; i < 3; i++) {
      final a = _pt(_rs, _angles[i]);
      final b = _pt(_rs + _lengths[i], _angles[i]);
      bars.add((a, b));
      for (final p in [a, b]) {
        minX = math.min(minX, p.dx - _t / 2);
        maxX = math.max(maxX, p.dx + _t / 2);
        minY = math.min(minY, p.dy - _t / 2);
        maxY = math.max(maxY, p.dy + _t / 2);
      }
    }
    final w = maxX - minX, h = maxY - minY;
    final s = size.shortestSide / math.max(w, h);
    canvas.translate((size.width - w * s) / 2 - minX * s, (size.height - h * s) / 2 - minY * s);
    canvas.scale(s);
    final barPaint = Paint()
      ..color = bar
      ..strokeWidth = _t
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (final (a, b) in bars) {
      canvas.drawLine(a, b, barPaint);
    }
    canvas.drawCircle(Offset.zero, _hub, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.bar != bar || old.dot != dot;
}
