import 'package:flutter/material.dart';

import 'theme.dart';

/// The play triangle at the start of a song row (picker, song library):
/// outlined and muted, filled in the accent for the current song. Shows
/// that tapping the row plays it.
class PlayMarker extends StatelessWidget {
  const PlayMarker({super.key, required this.current});

  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: current ? 'Playing' : null,
      child: CustomPaint(
        size: const Size.square(16),
        painter: _Triangle(
          current ? colors.accent : colors.muted,
          filled: current,
        ),
      ),
    );
  }
}

class _Triangle extends CustomPainter {
  _Triangle(this.color, {required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    // song-library.reference.html: points 3,2 14,8 3,14 in a 16px box.
    canvas.scale(size.width / 16);
    canvas.drawPath(
      Path()
        ..moveTo(3, 2)
        ..lineTo(14, 8)
        ..lineTo(3, 14)
        ..close(),
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Triangle old) =>
      old.color != color || old.filled != filled;
}
