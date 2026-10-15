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

/// The marking slot of a row while removing songs or deleting sets
/// (setlist-select.reference.html): an empty circle, or a filled accent
/// circle with a check.
class MarkCircle extends StatelessWidget {
  const MarkCircle({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      checked: checked,
      child: CustomPaint(
        size: const Size.square(20),
        painter: _Circle(
          checked ? colors.accent : colors.muted,
          check: checked ? colors.background : null,
        ),
      ),
    );
  }
}

class _Circle extends CustomPainter {
  _Circle(this.color, {this.check});

  final Color color;

  /// The check's color; null draws an empty ring.
  final Color? check;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final check = this.check;
    if (check == null) {
      canvas.drawCircle(
        const Offset(10, 10),
        8,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    canvas
      ..drawCircle(const Offset(10, 10), 9, Paint()..color = color)
      ..drawPath(
        Path()
          ..moveTo(5.5, 10.5)
          ..lineTo(8.5, 13.5)
          ..lineTo(14.5, 7),
        Paint()
          ..color = check
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
  }

  @override
  bool shouldRepaint(_Circle old) => old.color != color || old.check != check;
}
