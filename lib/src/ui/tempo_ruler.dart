import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import 'theme.dart';

/// Horizontal tempo ruler (ui-spec.md): a tick per bpm, a labeled tick
/// every 5, a fixed needle at the centre. Dragging moves the ruler and sets
/// the tempo in 1-bpm steps, clamped to the metronome's range. No momentum:
/// it stops where the finger lifts.
class TempoRuler extends StatefulWidget {
  const TempoRuler({super.key, required this.controller});

  final MetronomeController controller;

  /// Matches main-screen.reference.html: minor ticks 14 px apart.
  static const pxPerBpm = 14.0;
  static const height = 46.0;

  @override
  State<TempoRuler> createState() => _TempoRulerState();
}

class _TempoRulerState extends State<TempoRuler> {
  // While dragging, the ruler follows the finger between whole bpm values.
  double? _dragValue;

  MetronomeController get _controller => widget.controller;

  void _drag(double dx) {
    final value = (_dragValue! - dx / TempoRuler.pxPerBpm).clamp(
      MetronomeController.minBpm.toDouble(),
      MetronomeController.maxBpm.toDouble(),
    );
    setState(() => _dragValue = value);
    _controller.setBpm(value.round()); // no-op unless the whole value changed
  }

  void _endDrag() => setState(() => _dragValue = null);

  @override
  Widget build(BuildContext context) {
    final bpm = _controller.bpm;
    return Semantics(
      slider: true,
      label: 'Tempo',
      value: '$bpm bpm',
      increasedValue: '${bpm + 1} bpm',
      decreasedValue: '${bpm - 1} bpm',
      onIncrease: () => _controller.nudge(1),
      onDecrease: () => _controller.nudge(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) =>
            setState(() => _dragValue = bpm.toDouble()),
        onHorizontalDragUpdate: (details) => _drag(details.delta.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: SizedBox(
          height: TempoRuler.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _RulerPainter(
              value: _dragValue ?? bpm.toDouble(),
              bpm: bpm,
              colors: context.colors,
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.value, required this.bpm, required this.colors});

  /// The (possibly fractional) bpm under the needle.
  final double value;

  /// The current tempo; its label is highlighted.
  final int bpm;
  final MetraColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    const px = TempoRuler.pxPerBpm;
    final fill = Paint();
    final centre = size.width / 2;

    // Top and bottom rules.
    fill.color = colors.surface;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, 2), fill)
      ..drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), fill);

    final visible = (centre / px).ceil() + 1;
    final first = (value - visible).floor().clamp(
      MetronomeController.minBpm,
      MetronomeController.maxBpm,
    );
    final last = (value + visible).ceil().clamp(
      MetronomeController.minBpm,
      MetronomeController.maxBpm,
    );
    for (var b = first; b <= last; b++) {
      final x = centre + (b - value) * px;
      final major = b % 5 == 0;
      fill.color = major ? colors.muted : colors.beatResting;
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, major ? 20 : 12), fill);
      if (major) {
        final current = b == bpm;
        final label = TextPainter(
          text: TextSpan(
            text: '$b',
            style: TextStyle(
              fontFamily: MetraFonts.body,
              fontSize: 13,
              height: 18 / 13,
              fontWeight: current ? FontWeight.w600 : FontWeight.w500,
              color: current ? colors.text : colors.muted,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(x - label.width / 2, 23));
      }
    }

    // Fixed needle on top.
    fill.color = colors.needle;
    canvas.drawRect(Rect.fromLTWH(centre - 2, 0, 4, 22), fill);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.value != value || old.bpm != bpm || old.colors != colors;
}
