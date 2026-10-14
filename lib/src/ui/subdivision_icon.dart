import 'dart:math';

import 'package:flutter/material.dart';

/// Music-note icon for a subdivision, drawn as vector shapes (ui-spec.md:
/// not font glyphs): quarter (1), beamed eighths (2), beamed triplet with a
/// small "3" (3), beamed sixteenths (4). Geometry follows the eighth-note
/// SVG in main-screen.reference.html (26 × 24 units).
class SubdivisionIcon extends StatelessWidget {
  const SubdivisionIcon(this.stepsPerBeat, {super.key, this.size = 26});

  final int stepsPerBeat;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size, size * 24 / 26),
    painter: _NotePainter(
      stepsPerBeat,
      IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color!,
    ),
  );
}

class _NotePainter extends CustomPainter {
  _NotePainter(this.steps, this.color);

  final int steps;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    canvas.scale(size.width / 26, size.height / 24);

    // Note heads with stems; x is the head centre.
    final heads = switch (steps) {
      1 => [13.0],
      3 => [4.5, 13.0, 21.5],
      _ => [6.0, 19.0],
    };
    final headRx = steps == 3 ? 3.4 : 4.2;
    final headRy = steps == 3 ? 2.5 : 3.0;
    final stemTop = steps == 3 ? 7.0 : 3.0;
    for (final x in heads) {
      canvas
        ..save()
        ..translate(x, 19)
        ..rotate(-20 * pi / 180)
        ..drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: headRx * 2,
            height: headRy * 2,
          ),
          paint,
        )
        ..restore();
      canvas.drawRect(
        Rect.fromLTWH(x + headRx - 1, stemTop, 2, 19 - stemTop),
        paint,
      );
    }

    if (steps == 1) return;
    final left = heads.first + headRx - 1;
    final right = heads.last + headRx + 1;
    // One beam for eighths and triplets, two for sixteenths.
    canvas.drawRect(Rect.fromLTRB(left, stemTop, right, stemTop + 3.5), paint);
    if (steps == 4) {
      canvas.drawRect(
        Rect.fromLTRB(left, stemTop + 5.5, right, stemTop + 8.5),
        paint,
      );
    }
    if (steps == 3) {
      final three = TextPainter(
        text: TextSpan(
          text: '3',
          style: TextStyle(
            color: color,
            fontSize: 7,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      three.paint(
        canvas,
        Offset((left + right - three.width) / 2, stemTop - three.height - 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_NotePainter old) =>
      old.steps != steps || old.color != color;
}
