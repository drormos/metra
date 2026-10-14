import 'dart:async';
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
/// picking; faster moves cover more bpm per pixel (up to [maxGain]×). One
/// swipe, drag and coast together, covers at most [maxSwipeBpm], so the
/// whole range takes two.
/// Snapping: short drags (under [shortDragBpm]) and slow ones (recent
/// finger speed under [fineSpeed]) stay exactly where they're released, so
/// 120 → 123 just works. A long, quick drag can keep an exact value too by
/// resting the finger for [lockDelay] first (a firmer haptic tick says
/// so); otherwise it slides to the next multiple of 5 in the direction it
/// was moving. A fling (release faster than [flingSpeed]) coasts and also
/// comes to rest on a multiple of 5. A light haptic tick marks every
/// multiple of 5 crossed, while dragging and coasting. Touching the ruler
/// stops a coast.
class TempoRuler extends StatefulWidget {
  const TempoRuler({super.key, required this.controller});

  final MetronomeController controller;

  /// Matches main-screen.reference.html: minor ticks 14 px apart.
  static const pxPerBpm = 14.0;
  static const height = 46.0;

  /// Finger speeds (px/s) where acceleration starts and tops out.
  static const slowSpeed = 300.0;
  static const fastSpeed = 1500.0;
  static const maxGain = 2.5;

  /// Release speed (px/s) that counts as a fling. Tune on a real phone.
  static const flingSpeed = 300.0;

  /// How long the finger rests on a value before lifting keeps it exactly.
  /// Shorter catches the brief pause many drags end with. Tune on a phone.
  static const lockDelay = Duration(milliseconds: 300);

  /// Drags that change the tempo by less than this (bpm) are fine-tuning:
  /// never snapped.
  static const shortDragBpm = 5.0;

  /// Recent finger speed (px/s, ~13 bpm/s) below which a drag is
  /// fine-tuning: never snapped. Measured over [recentSpeedWindow] of real
  /// movement; rests don't count.
  static const fineSpeed = 180.0;
  static const recentSpeedWindow = Duration(milliseconds: 300);

  /// Finger moves smaller than this (px) are jitter from a resting finger,
  /// not movement: they don't undo a lock or flip the direction.
  static const jitterPx = 3.0;

  /// How far a fling coasts: lower stops sooner (see [FrictionSimulation]).
  static const flingFriction = 0.05;

  /// Most a single swipe (drag plus coast) moves the tempo: half of
  /// 30–300, so the full range takes two swipes.
  static const maxSwipeBpm = 135.0;

  /// Where a fling released at [value] with [bpmPerSecond] comes to rest:
  /// the multiple of 5 nearest to where friction would stop it, no more
  /// than [maxSwipeBpm] from where the swipe began ([start], default
  /// [value]), at least one multiple ahead in the fling's direction, within
  /// 30–300.
  static double flingTarget(
    double value,
    double bpmPerSecond, {
    double? start,
  }) {
    final coast = FrictionSimulation(flingFriction, value, bpmPerSecond).finalX;
    final from = start ?? value;
    var target = (coast / 5).round() * 5.0;
    if (bpmPerSecond > 0) {
      target = min(target, ((from + maxSwipeBpm) / 5).floor() * 5.0);
    } else {
      target = max(target, ((from - maxSwipeBpm) / 5).ceil() * 5.0);
    }
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

  /// Where an unlocked drag released at [value] rests: the next multiple
  /// of 5 in its [direction] (+1 up, −1 down), unless it's already within
  /// half a bpm of one. Within 30–300.
  static double snapTarget(double value, int direction) {
    final nearest = (value / 5).round() * 5.0;
    final target = (value - nearest).abs() < 0.5
        ? nearest
        : (direction > 0 ? (value / 5).ceil() : (value / 5).floor()) * 5.0;
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
  // Finger position (px from the drag start) and where it last really
  // moved, beyond jitter.
  double _fingerX = 0;
  double _restX = 0;
  // Times and positions of real moves, for the recent finger speed. Empty
  // when event times are missing.
  final _path = <(Duration, double)>[];
  // Restarted by every real move; fires once the finger has rested.
  Timer? _lockTimer;
  bool _locked = false;
  // Bpm direction of the last move: +1 up, −1 down.
  int _direction = 0;
  // Where this drag began, to cap how far one swipe goes.
  double _swipeStart = 0;
  late final AnimationController _glide = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => _moveTo(_glide.value));

  MetronomeController get _controller => widget.controller;

  static const _min = MetronomeController.minBpm * 1.0;
  static const _max = MetronomeController.maxBpm * 1.0;

  @override
  void dispose() {
    _lockTimer?.cancel();
    _glide.dispose();
    super.dispose();
  }

  void _moveTo(double value) {
    final clamped = value.clamp(_min, _max);
    final previous = _value ?? _controller.bpm.toDouble();
    if ((previous / 5).floor() != (clamped / 5).floor()) {
      // Crossed a multiple of 5. Not selectionClick: Android's CLOCK_TICK is
      // too faint to feel on many phones.
      HapticFeedback.lightImpact();
    }
    setState(() => _value = clamped);
    _controller.setBpm(clamped.round()); // no-op unless the whole value changed
    if (_glide.isAnimating && clamped != value) _glide.stop(); // hit an end
  }

  void _start(DragStartDetails details) {
    _glide.stop(); // touching the ruler stops a glide
    _value ??= _controller.bpm.toDouble();
    _swipeStart = _value!;
    _lastMoveTime = details.sourceTimeStamp;
    _fingerX = 0;
    _direction = 0;
    _path.clear();
    _rest(details.sourceTimeStamp);
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
      final speed = dx.abs() / seconds;
      gain = TempoRuler.gainFor(speed);
    }
    _fingerX += dx;
    final moved = _fingerX - _restX;
    if (moved.abs() >= TempoRuler.jitterPx) {
      _direction = moved < 0 ? 1 : -1; // dragging left raises the tempo
      _rest(now);
    }
    _moveTo(_value! - dx * gain / TempoRuler.pxPerBpm);
  }

  void _end(DragEndDetails details) {
    final speed = details.velocity.pixelsPerSecond.dx;
    _lockTimer?.cancel();
    final from = _value!;
    // Rested on it, or never really moved (a tap): keep it exactly.
    if (_locked || _direction == 0) return _settle();
    if (speed.abs() < TempoRuler.flingSpeed) {
      final recent = _recentSpeed();
      if ((from - _swipeStart).abs() < TempoRuler.shortDragBpm ||
          (recent != null && recent < TempoRuler.fineSpeed)) {
        return _settle(); // fine-tuning: keep it exactly
      }
      return _glideTo(TempoRuler.snapTarget(from, _direction), 0.15);
    }
    final bpmPerSecond =
        -speed * TempoRuler.gainFor(speed.abs()) / TempoRuler.pxPerBpm;
    final target = TempoRuler.flingTarget(
      from,
      bpmPerSecond,
      start: _swipeStart,
    );
    // Decelerate starts at twice its average speed: match the release.
    _glideTo(target, 2 * (target - from).abs() / bpmPerSecond.abs());
  }

  /// Finger speed (px/s) over the latest real movement, or null if unknown.
  double? _recentSpeed() {
    if (_path.length < 2) return null;
    final (t0, x0) = _path.first;
    final (t1, x1) = _path.last;
    final seconds = (t1 - t0).inMicroseconds / 1e6;
    return seconds > 0 ? (x1 - x0).abs() / seconds : null;
  }

  /// The finger is here now (at [time]): unlock, and lock again if it
  /// stays.
  void _rest(Duration? time) {
    _restX = _fingerX;
    if (time != null) {
      _path.add((time, _fingerX));
      // Keep one point from before the window, so the span covers it.
      while (_path.length > 2 &&
          _path[1].$1 <= time - TempoRuler.recentSpeedWindow) {
        _path.removeAt(0);
      }
    }
    _locked = false;
    _lockTimer?.cancel();
    _lockTimer = Timer(TempoRuler.lockDelay, () {
      _locked = true;
      HapticFeedback.heavyImpact(); // distinct from the multiple-of-5 tick
    });
  }

  void _cancel() {
    _lockTimer?.cancel();
    _settle();
  }

  void _glideTo(double target, double seconds) {
    final from = _value!;
    if (from == target) return _settle();
    seconds = seconds.clamp(0.15, 1.5);
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
          onHorizontalDragCancel: _cancel,
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
