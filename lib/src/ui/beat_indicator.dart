import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'haptics.dart';
import 'theme.dart';

/// How lit a beat light is [since] its click (ui-spec.md "Motion"): fully
/// on at the click, never a fade-in, then back to rest over
/// [MetraMotion.lightFade] (ease-out), or a third of [period] (the time to
/// its next click) if shorter. [reduced] ("Remove animations"): on until
/// the next click, then off.
double beatLight(Duration since, Duration? period, {required bool reduced}) {
  if (since.isNegative) return 0;
  if (reduced) return period == null || since < period ? 1 : 0;
  var fade = MetraMotion.lightFade;
  if (period != null && period ~/ 3 < fade) fade = period ~/ 3;
  if (since >= fade || fade <= Duration.zero) return 0;
  return 1 -
      Curves.easeOut.transform(since.inMicroseconds / fade.inMicroseconds);
}

/// Beat blocks (ui-spec.md): one block per beat with a subdivision strip
/// under it. Blocks show their type at rest (accent, regular, muted) and
/// light at their click: a block at its beat, a tick at its own click,
/// each fading back at once ([beatLight]). Driven by the engine clock
/// (plus the visual offset), read once per frame. Tapping a block cycles
/// regular → accent → muted.
class BeatIndicator extends StatefulWidget {
  const BeatIndicator({super.key, required this.controller});

  final MetronomeController controller;

  @override
  State<BeatIndicator> createState() => _BeatIndicatorState();
}

class _BeatIndicatorState extends State<BeatIndicator>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  // Display-only: derived from the engine clock every frame.
  ScheduledStep? _step;
  double _blockLight = 0;
  double _tickLight = 0;

  MetronomeController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  // Tick only while playing, so an idle app requests no frames.
  void _sync() {
    if (_controller.isPlaying) {
      if (!_ticker.isActive) {
        _controller.resetVisualClock();
        _ticker.start();
      }
    } else {
      _ticker.stop();
      if (_step != null) {
        setState(() {
          _step = null;
          _blockLight = _tickLight = 0;
        });
      }
    }
  }

  // The frame timestamp, not the ticker's elapsed time: one clock shared
  // with the polyrhythm lane, which feeds the same smoother.
  // Rebuilds only when something lit changes: a new step, or a fade.
  void _onTick(Duration _) {
    final now = _controller.visualTimeAt(
      SchedulerBinding.instance.currentFrameTimeStamp,
    );
    final step = now == null ? null : _controller.stepAt(now);
    var block = 0.0;
    var tick = 0.0;
    if (now != null && step != null) {
      final reduced = MetraMotion.reduced(context);
      final perBeat = step.pattern.stepsPerBeat;
      final interval = _controller.stepInterval(step);
      // The block lights at its beat's first click.
      final beatStart = interval == null
          ? step.time
          : step.time - interval * (step.barPosition % perBeat);
      block = beatLight(
        now - beatStart,
        interval == null ? null : interval * perBeat,
        reduced: reduced,
      );
      tick = step.level == StepLevel.silent
          ? 0
          : beatLight(now - step.time, interval, reduced: reduced);
    }
    if (step?.index != _step?.index ||
        block != _blockLight ||
        tick != _tickLight) {
      setState(() {
        _step = step;
        _blockLight = block;
        _tickLight = tick;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Draw the latest edits (a tapped block changes at once). Only while a
    // switch to a different shape is pending (song, meter, subdivision)
    // does the bar being heard win, so no block shows that isn't sounding.
    final step = _step;
    final latest = _controller.pattern;
    final heard = step?.pattern;
    final pattern =
        heard == null ||
            (heard.beatsPerBar == latest.beatsPerBar &&
                heard.stepsPerBeat == latest.stepsPerBeat)
        ? latest
        : heard;
    final perBeat = pattern.stepsPerBeat;
    final soundingBeat = step == null ? null : step.barPosition ~/ perBeat;
    // Silent steps (a muted beat's own click) don't light anything.
    final soundingStep = step == null || step.level == StepLevel.silent
        ? null
        : step.barPosition;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (beat, level) in pattern.beatLevels.indexed) ...[
          if (beat > 0) const SizedBox(width: 6),
          Expanded(
            child: _tapTarget(
              beat,
              level,
              sounding: beat == soundingBeat && level != StepLevel.silent,
              child: Column(
                // Blocks fill the beat's width (a muted block has no colored
                // fill to size it otherwise).
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _block(
                    beat,
                    level,
                    light: beat == soundingBeat && level != StepLevel.silent
                        ? _blockLight
                        : 0,
                  ),
                  if (perBeat > 1) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        for (var tick = 0; tick < perBeat; tick++) ...[
                          if (tick > 0) const SizedBox(width: 3),
                          Expanded(
                            child: _tick(
                              beat,
                              tick,
                              light: beat * perBeat + tick == soundingStep
                                  ? _tickLight
                                  : 0,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// The whole beat column (block and strip) is the tap target, padded to
  /// at least 48dp tall.
  Widget _tapTarget(
    int beat,
    StepLevel level, {
    required bool sounding,
    required Widget child,
  }) {
    final kind = switch (level) {
      StepLevel.silent => 'muted',
      StepLevel.accent => 'accented',
      _ => 'regular',
    };
    return Semantics(
      button: true,
      label: 'Beat ${beat + 1}, $kind',
      onTapHint: 'change',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tick();
          _controller.cycleBeat(beat);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: child,
        ),
      ),
    );
  }

  Widget _block(int beat, StepLevel level, {required double light}) {
    final colors = context.colors;
    final muted = level == StepLevel.silent;
    final accent = level == StepLevel.accent;
    final sounding = light > 0;
    final color = muted
        ? colors.mutedFill
        : accent
        ? Color.lerp(colors.accentResting, colors.accentSounding, light)!
        : Color.lerp(colors.beatResting, colors.beatSounding, light)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        key: ValueKey('beat-$beat-${sounding ? 'on' : 'off'}'),
        height: 36,
        color: color,
        child: muted ? CustomPaint(painter: MutedLine(colors.mutedLine)) : null,
      ),
    );
  }

  Widget _tick(int beat, int tick, {required double light}) => Container(
    key: ValueKey('tick-$beat-$tick-${light > 0 ? 'on' : 'off'}'),
    height: 5,
    color: Color.lerp(
      context.colors.tickResting,
      context.colors.tickSounding,
      light,
    ),
  );
}

/// One thin diagonal, bottom-left to top-right: muted, explicit but quiet.
class MutedLine extends CustomPainter {
  MutedLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    Offset(0, size.height),
    Offset(size.width, 0),
    Paint()
      ..color = color
      ..strokeWidth = 2,
  );

  @override
  bool shouldRepaint(MutedLine old) => old.color != color;
}
