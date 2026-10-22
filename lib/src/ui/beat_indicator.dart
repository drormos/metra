import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'haptics.dart';
import 'theme.dart';

/// How lit a beat light is [since] its click (negative: before it), for a
/// light whose next click is [interval] later (ui-spec.md "Beat lights: a
/// short pulse, not a flash"): up over [MetraMotion.lightRise] from
/// [MetraMotion.lightLead] before the click (full on the sound), lit for
/// 35% of the interval, down over 35% (ease-in-out), each part at most
/// [MetraMotion.lightCap]; then at rest. [reduced] ("Remove animations"):
/// fully on from the click for the same time, then off.
double beatPulse(Duration since, Duration? interval, {required bool reduced}) {
  final share = interval == null
      ? MetraMotion.lightCap
      : interval * MetraMotion.lightShare;
  final part = share < MetraMotion.lightCap ? share : MetraMotion.lightCap;
  final rise = MetraMotion.lightRise;
  final litEnd = rise - MetraMotion.lightLead + part;
  if (reduced) return since >= Duration.zero && since < litEnd ? 1 : 0;
  final t = since + MetraMotion.lightLead; // from the start of the rise
  if (t.isNegative) return 0;
  double of(Duration a, Duration b) => a.inMicroseconds / b.inMicroseconds;
  // A strong ease-out: ~90% on the sound itself.
  if (t < rise) return Curves.easeOutCubic.transform(of(t, rise));
  final down = since - litEnd;
  if (down.isNegative) return 1;
  if (down >= part || part <= Duration.zero) return 0;
  return 1 - Curves.easeInOut.transform(of(down, part));
}

/// Beat blocks (ui-spec.md): one block per beat with a subdivision strip
/// under it. Blocks show their type at rest (accent, regular, muted) and
/// pulse at their click: a block at its beat, a tick at its own click
/// ([beatPulse]). Driven by the engine clock
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

  // Display-only: derived from the engine clock every frame. Lights by
  // beat and by bar position (a light can rise before its click while the
  // one before it is still coming down).
  ScheduledStep? _step;
  Map<int, double> _blocks = const {};
  Map<int, double> _ticks = const {};

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
          _blocks = _ticks = const {};
        });
      }
    }
  }

  // The frame timestamp, not the ticker's elapsed time: one clock shared
  // with the polyrhythm lane, which feeds the same smoother.
  // Rebuilds only when something lit changes.
  void _onTick(Duration _) {
    final now = _controller.visualTimeAt(
      SchedulerBinding.instance.currentFrameTimeStamp,
    );
    final step = now == null ? null : _controller.stepAt(now);
    final blocks = <int, double>{};
    final ticks = <int, double>{};
    if (now != null) {
      final reduced = MetraMotion.reduced(context);
      // The step sounding now, and the next one if its light is rising.
      final next = _controller.stepAt(now + MetraMotion.lightLead);
      for (final s in {?step, ?next}) {
        final perBeat = s.pattern.stepsPerBeat;
        final interval = _controller.stepInterval(s);
        void light(Map<int, double> lights, int key, double v) {
          if (v > (lights[key] ?? 0)) lights[key] = v;
        }

        // The block pulses at its beat's first click, over the beat.
        final beatStart = interval == null
            ? s.time
            : s.time - interval * (s.barPosition % perBeat);
        light(
          blocks,
          s.barPosition ~/ perBeat,
          beatPulse(
            now - beatStart,
            interval == null ? null : interval * perBeat,
            reduced: reduced,
          ),
        );
        if (s.level != StepLevel.silent) {
          light(
            ticks,
            s.barPosition,
            beatPulse(now - s.time, interval, reduced: reduced),
          );
        }
      }
    }
    if (step?.index != _step?.index ||
        !mapEquals(blocks, _blocks) ||
        !mapEquals(ticks, _ticks)) {
      setState(() {
        _step = step;
        _blocks = blocks;
        _ticks = ticks;
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (beat, level) in pattern.beatLevels.indexed) ...[
          if (beat > 0) const SizedBox(width: 6),
          Expanded(
            child: _tapTarget(
              beat,
              level,
              child: Column(
                // Blocks fill the beat's width (a muted block has no colored
                // fill to size it otherwise).
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _block(
                    beat,
                    level,
                    // A muted block never lights.
                    light: level == StepLevel.silent ? 0 : _blocks[beat] ?? 0,
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
                              light: _ticks[beat * perBeat + tick] ?? 0,
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
  Widget _tapTarget(int beat, StepLevel level, {required Widget child}) {
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
