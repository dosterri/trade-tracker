import 'package:flutter/material.dart';

import '../core/models.dart';

/// Minimaler Trendchart ohne Achsen.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    required this.color,
    this.height = 34,
    this.baseline,
  });

  final List<PricePoint> points;
  final Color color;
  final double height;

  /// Optionale Referenzlinie (z. B. Einstandskurs), gestrichelt.
  final double? baseline;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text('Noch kein Kursverlauf',
              style: Theme.of(context).textTheme.labelSmall),
        ),
      );
    }
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          points,
          color,
          baseline,
          Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.points, this.color, this.baseline, this.baseColor);

  final List<PricePoint> points;
  final Color color;
  final double? baseline;
  final Color baseColor;

  @override
  void paint(Canvas canvas, Size size) {
    var minV = points.first.price, maxV = points.first.price;
    for (final p in points) {
      if (p.price < minV) minV = p.price;
      if (p.price > maxV) maxV = p.price;
    }
    final b = baseline;
    final showBase = b != null && b >= minV - (maxV - minV) && b <= maxV + (maxV - minV);
    if (showBase) {
      if (b < minV) minV = b;
      if (b > maxV) maxV = b;
    }
    final range = (maxV - minV).abs() < 1e-12 ? 1.0 : maxV - minV;
    final t0 = points.first.at.millisecondsSinceEpoch.toDouble();
    final t1 = points.last.at.millisecondsSinceEpoch.toDouble();
    final span = (t1 - t0) <= 0 ? 1.0 : t1 - t0;
    const pad = 2.0;
    final h = size.height - pad * 2;

    Offset at(PricePoint p) => Offset(
          (p.at.millisecondsSinceEpoch - t0) / span * size.width,
          pad + h - (p.price - minV) / range * h,
        );

    final path = Path()..moveTo(at(points.first).dx, at(points.first).dy);
    for (final p in points.skip(1)) {
      final o = at(p);
      path.lineTo(o.dx, o.dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    if (showBase) {
      final y = pad + h - (b - minV) / range * h;
      final dash = Paint()
        ..color = baseColor
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), dash);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.color != color || old.baseline != baseline;
}
