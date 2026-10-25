import 'package:flutter/material.dart';

/// App icons drawn from the design references (ui-spec.md "Icons"), in
/// the ambient [IconTheme] color unless [color] is given.

/// Setlist: "note queue", three lines (the last short) with a note at the
/// lower right.
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

/// Stopwatch: "When I press Start" (the top row's left button).
class StopwatchIcon extends StatelessWidget {
  const StopwatchIcon({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _StopwatchPainter(color ?? IconTheme.of(context).color!),
  );
}

class _StopwatchPainter extends CustomPainter {
  _StopwatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawCircle(const Offset(12, 14), 7.5, stroke)
      ..drawLine(const Offset(12, 14), const Offset(12, 10), stroke)
      ..drawLine(const Offset(10, 2.8), const Offset(14, 2.8), stroke)
      ..drawLine(const Offset(12, 2.8), const Offset(12, 6.5), stroke)
      ..drawLine(const Offset(18.5, 6.8), const Offset(20, 5.3), stroke);
  }

  @override
  bool shouldRepaint(_StopwatchPainter old) => old.color != color;
}

/// Stage mode: a stage (floor and riser) with an arrow up onto it.
class StageIcon extends StatelessWidget {
  const StageIcon({super.key, this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _StagePainter(color ?? IconTheme.of(context).color!),
  );
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(const Offset(3, 20), const Offset(21, 20), stroke)
      ..drawPath(
        Path()
          ..moveTo(6, 20)
          ..lineTo(6, 14)
          ..lineTo(18, 14)
          ..lineTo(18, 20),
        stroke,
      )
      ..drawPath(
        Path()
          ..moveTo(8, 8)
          ..lineTo(12, 4)
          ..lineTo(16, 8),
        stroke,
      )
      ..drawLine(const Offset(12, 4), const Offset(12, 12), stroke);
  }

  @override
  bool shouldRepaint(_StagePainter old) => old.color != color;
}
