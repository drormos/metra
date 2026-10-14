import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../controller/metronome_controller.dart';
import 'theme.dart';

/// Horizontal tempo ruler (ui-spec.md): a tick per bpm, a labeled tick
/// every 5, a fixed needle at the centre. Dragging moves the ruler and sets
/// the tempo in 1-bpm steps, clamped to the metronome's range.
///
/// Speed-sensitive: slow, small moves are 1 bpm per 14 px for precise
/// picking; faster moves cover more bpm per pixel (up to [maxGain]×).
/// Snapping depends on release speed: below [flingSpeed] the ruler stays
/// exactly where it's released (so 123 is reachable); a faster fling coasts
/// and always comes to rest on a multiple of 5. A light haptic tick marks
/// every multiple of 5 crossed, while dragging and coasting. Touching the
/// ruler stops a coast.
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

  /// Release speed (px/s) that counts as a fling. Tune on a real phone.
  static const flingSpeed = 300.0;

  /// How far a fling coasts: lower stops sooner (see [FrictionSimulation]).
  static const flingFriction = 0.05;

  /// Where a fling released at [value] with [bpmPerSecond] comes to rest:
  /// the multiple of 5 nearest to where friction would stop it, at least
  /// one multiple ahead in the fling's direction, within 30–300.
  static double flingTarget(double value, double bpmPerSecond) {
    final coast = FrictionSimulation(flingFriction, value, bpmPerSecond).finalX;
    var target = (coast / 5).round() * 5.0;
    if (bpmPerSecond > 0 && target <= value) {
      target = (value / 5).floor() * 5 + 5;
    }
    if (bpmPerSecond < 0 && target >= value) {
      target = (value / 5).ceil() * 5 - 5;
    }
    return target.clamp(
      MetronomeController.minBpm.toDouble(),
      MetronomeController.maxBpm.toDouble(),
    );
  }

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
    final previous = _value ?? _controller.bpm.toDouble();
    if ((previous / 5).floor() != (clamped / 5).floor()) {
      HapticFeedback.selectionClick(); // crossed a multiple of 5
    }
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
    // Slow release: stays exactly where it is.
    if (speed.abs() < TempoRuler.flingSpeed) return _settle();
    final from = _value!;
    final bpmPerSecond =
        -speed * TempoRuler.gainFor(speed.abs()) / TempoRuler.pxPerBpm;
    final target = TempoRuler.flingTarget(from, bpmPerSecond);
    // Decelerate starts at twice its average speed: match the release.
    final seconds = (2 * (target - from).abs() / bpmPerSecond.abs()).clamp(
      0.15,
      1.5,
    );
    _glide
      ..value = from
      ..animateTo(
        target,
        duration: Duration(microseconds: (seconds * 1e6).round()),
        curve: Curves.decelerate,
      ).then((_) {
        // Coasted all the way (not interrupted): exactly on the multiple.
        if (_glide.value == target) _controller.setBpm(target.round());
        _settle();
      });
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
    fill.color = colors.divider;
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
    fill.color = colors.accent;
    canvas.drawRect(Rect.fromLTWH(centre - 2, 0, 4, 22), fill);
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.value != value || old.bpm != bpm || old.colors != colors;
}
