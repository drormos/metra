import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../controller/metronome_controller.dart';
import 'theme.dart';

/// Horizontal tempo ruler (ui-spec.md): a tick per bpm, a labeled tick
/// every 5, a fixed needle at the centre. Dragging moves the ruler and sets
/// the tempo in 1-bpm steps, clamped to the metronome's range.
///
/// Speed-sensitive: slow, small moves are 1 bpm per 14 px for precise
/// picking; faster moves cover more bpm per pixel (up to [maxGain]×). A
/// fast swipe glides on after release and slows to a stop; a slow drag
/// stops where the finger lifts. Touching the ruler stops a glide.
class TempoRuler extends StatefulWidget {
  const TempoRuler({super.key, required this.controller});

  final MetronomeController controller;

  /// Matches main-screen.reference.html: minor ticks 14 px apart.
  static const pxPerBpm = 14.0;
  static const height = 46.0;

  /// Finger speeds (px/s) where acceleration starts and tops out.
  static const slowSpeed = 300.0;
  static const fastSpeed = 1500.0;
  static const maxGain = 4.0;

  /// Below this release speed (px/s) there is no glide.
  static const minGlideSpeed = 600.0;

  /// Bpm-per-pixel multiplier for a finger speed in px/s.
  static double gainFor(double speed) =>
      1 +
      (maxGain - 1) *
          ((speed - slowSpeed) / (fastSpeed - slowSpeed)).clamp(0.0, 1.0);

  @override
  State<TempoRuler> createState() => _TempoRulerState();
}

class _TempoRulerState extends State<TempoRuler>
    with SingleTickerProviderStateMixin {
  // Fractional bpm under the needle while dragging or gliding; null at rest.
  double? _value;
  Duration? _lastMoveTime;
  late final AnimationController _glide = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => _moveTo(_glide.value));

  MetronomeController get _controller => widget.controller;

  static const _min = MetronomeController.minBpm * 1.0;
  static const _max = MetronomeController.maxBpm * 1.0;

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  void _moveTo(double value) {
    final clamped = value.clamp(_min, _max);
    setState(() => _value = clamped);
    _controller.setBpm(clamped.round()); // no-op unless the whole value changed
    if (_glide.isAnimating && clamped != value) _glide.stop(); // hit an end
  }

  void _start(DragStartDetails details) {
    _glide.stop(); // touching the ruler stops a glide
    _value ??= _controller.bpm.toDouble();
    _lastMoveTime = details.sourceTimeStamp;
  }

  void _update(DragUpdateDetails details) {
    final dx = details.delta.dx;
    // Finger speed from event timestamps (absent in some synthetic events:
    // then no acceleration).
    final now = details.sourceTimeStamp;
    final last = _lastMoveTime;
    _lastMoveTime = now;
    var gain = 1.0;
    if (now != null && last != null && now > last) {
      final seconds = (now - last).inMicroseconds / 1e6;
      gain = TempoRuler.gainFor(dx.abs() / seconds);
    }
    _moveTo(_value! - dx * gain / TempoRuler.pxPerBpm);
  }

  void _end(DragEndDetails details) {
    final speed = details.velocity.pixelsPerSecond.dx;
    if (speed.abs() < TempoRuler.minGlideSpeed) return _settle();
    final bpmPerSecond =
        -speed * TempoRuler.gainFor(speed.abs()) / TempoRuler.pxPerBpm;
    _glide
      ..value = _value!
      ..animateWith(
        // Stops once slower than 1 bpm/s, instead of creeping for seconds.
        FrictionSimulation(
          0.05,
          _value!,
          bpmPerSecond,
          tolerance: const Tolerance(velocity: 1),
        ),
      ).then((_) => _settle());
  }

  /// Back to rest: the ruler shows the whole tempo again.
  void _settle() {
    if (!mounted) return;
    setState(() => _value = null);
  }

  @override
  Widget build(BuildContext context) {
    final bpm = _controller.bpm;
    return Semantics(
      slider: true,
      label: 'Tempo',
      value: '$bpm bpm',
      increasedValue: '${min(bpm + 1, MetronomeController.maxBpm)} bpm',
      decreasedValue: '${max(bpm - 1, MetronomeController.minBpm)} bpm',
      onIncrease: () => _controller.nudge(1),
      onDecrease: () => _controller.nudge(-1),
      // Touch-down stops a glide. A raw listener, not a tap recognizer: a
      // competing tap would make the drag wait out the touch slop first.
      child: Listener(
        onPointerDown: (_) {
          if (_glide.isAnimating) {
            _glide.stop();
            _settle();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          onHorizontalDragCancel: _settle,
          child: SizedBox(
            height: TempoRuler.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _RulerPainter(
                value: _value ?? bpm.toDouble(),
                bpm: bpm,
                colors: context.colors,
              ),
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
