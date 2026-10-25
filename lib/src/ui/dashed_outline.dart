import 'package:flutter/material.dart';

/// A dashed rounded outline (stage mode's exit pill, "+ Add part").
class DashedOutline extends CustomPainter {
  DashedOutline(this.color, {required this.radius, this.width = 1});

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          rect.deflate(width / 2),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedOutline old) =>
      old.color != color || old.radius != radius || old.width != width;
}
