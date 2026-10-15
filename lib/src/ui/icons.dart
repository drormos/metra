import 'package:flutter/material.dart';

/// App icons drawn from the design references (ui-spec.md "Icons"), in
/// the ambient [IconTheme] color unless [color] is given.

/// Setlist: "note queue", three lines (the last short) with a note at the
/// lower right. Distinct from the Menu icon.
class SetlistIcon extends StatelessWidget {
  const SetlistIcon({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _SetlistPainter(color ?? IconTheme.of(context).color!),
  );
}

class _SetlistPainter extends CustomPainter {
  _SetlistPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(const Offset(3, 6), const Offset(14, 6), stroke)
      ..drawLine(const Offset(3, 11), const Offset(14, 11), stroke)
      ..drawLine(const Offset(3, 16), const Offset(9, 16), stroke)
      ..drawPath(
        Path()
          ..moveTo(17, 18.5)
          ..lineTo(17, 7)
          ..lineTo(21, 5.8),
        stroke,
      )
      ..drawCircle(const Offset(15, 18.5), 2.2, Paint()..color = color)
      ..drawCircle(const Offset(15, 18.5), 2.2, stroke);
  }

  @override
  bool shouldRepaint(_SetlistPainter old) => old.color != color;
}

/// Menu: ☰, three equal lines.
class MenuIcon extends StatelessWidget {
  const MenuIcon({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MenuPainter(IconTheme.of(context).color!),
  );
}

class _MenuPainter extends CustomPainter {
  _MenuPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (final y in [5.0, 10.0, 15.0]) {
      canvas.drawLine(Offset(3, y), Offset(17, y), stroke);
    }
  }

  @override
  bool shouldRepaint(_MenuPainter old) => old.color != color;
}

/// Free play: a metronome body with its pendulum.
class MetronomeIcon extends StatelessWidget {
  const MetronomeIcon({super.key, this.size = 26, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _MetronomePainter(color ?? IconTheme.of(context).color!),
  );
}

class _MetronomePainter extends CustomPainter {
  _MetronomePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 26);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(9, 3)
          ..lineTo(17, 3)
          ..lineTo(22, 23)
          ..lineTo(4, 23)
          ..close(),
        stroke,
      )
      ..drawLine(const Offset(13, 19), const Offset(18, 6), stroke)
      ..drawLine(const Offset(8, 19), const Offset(18, 19), stroke);
  }

  @override
  bool shouldRepaint(_MetronomePainter old) => old.color != color;
}
