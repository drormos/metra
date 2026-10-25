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
  const BeatIndicator({
    super.key,
    required this.controller,
    this.blockHeight = 36,
    this.editable = true,
  });

  final MetronomeController controller;

  /// 36px on the main screen, 64px in stage mode.
  final double blockHeight;

  /// Tapping a beat cycles it; off in stage mode, where nothing edits.
  final bool editable;

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
  bool _countingIn = false;
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
      if (_step != null || _countingIn) {
        setState(() {
          _step = null;
          _countingIn = false;
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
    // Also before the count-in's first beat has sounded.
    final countingIn =
        step?.countIn != null || (step == null && _controller.countingIn);
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
        // A count-in plays beats only: the strip stays dark.
        if (s.level != StepLevel.silent && s.countIn == null) {
          light(
            ticks,
            s.barPosition,
            beatPulse(now - s.time, interval, reduced: reduced),
          );
        }
      }
    }
    if (step?.index != _step?.index ||
        countingIn != _countingIn ||
        !mapEquals(blocks, _blocks) ||
        !mapEquals(ticks, _ticks)) {
      setState(() {
        _step = step;
        _countingIn = countingIn;
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
    // A count-in draws the song's bar (its own has no subdivisions).
    final pattern =
        _countingIn ||
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
                  if (_countingIn)
                    _countInBlock(beat, light: _blocks[beat] ?? 0)
                  else
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
    if (!widget.editable) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: child,
      );
    }
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
        height: widget.blockHeight,
        color: color,
        child: muted ? CustomPaint(painter: MutedLine(colors.mutedLine)) : null,
      ),
    );
  }

  /// During a count-in (ui-spec.md "When I press Start"): every beat
  /// sounds, so each block is a plain one showing its number, muted, and
  /// lights as it sounds (beat 1 as the accent it is).
  Widget _countInBlock(int beat, {required double light}) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        key: ValueKey('beat-$beat-${light > 0 ? 'on' : 'off'}'),
        height: widget.blockHeight,
        alignment: Alignment.center,
        color: Color.lerp(
          colors.tickResting,
          beat == 0 ? colors.accentSounding : colors.beatSounding,
          light,
        ),
        child: Text(
          '${beat + 1}',
          key: ValueKey('count-in-${beat + 1}'),
          // Inside a fixed 36px block.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontFamily: MetraFonts.condensed,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1,
            color: Color.lerp(colors.muted, colors.background, light),
          ),
        ),
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
