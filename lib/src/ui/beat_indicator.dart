import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'theme.dart';

/// Beat blocks (ui-spec.md): one block per beat with a subdivision strip
/// under it. Blocks show their type at rest (accent, regular, muted) and
/// light only while sounding: a block for its whole beat, a tick for its own
/// click. Driven by the engine clock (plus the visual offset), checked once
/// per frame. Tapping a block cycles regular → accent → muted.
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
        _controller.resetVisualClock(); // ticker elapsed restarts at zero
        _ticker.start();
      }
    } else {
      _ticker.stop();
      if (_step != null) setState(() => _step = null);
    }
  }

  void _onTick(Duration elapsed) {
    final step = _controller.visualStepAt(elapsed);
    if (step?.index != _step?.index) setState(() => _step = step);
  }

  @override
  Widget build(BuildContext context) {
    // While playing, draw the pattern of the step being heard: after a song
    // switch the controller already holds the next pattern until it starts.
    final step = _step;
    final pattern = step?.pattern ?? _controller.pattern;
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
                children: [
                  _block(
                    beat,
                    level,
                    sounding: beat == soundingBeat && level != StepLevel.silent,
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
                              sounding: beat * perBeat + tick == soundingStep,
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
  /// at least 44 px tall.
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
      label:
          'Beat ${beat + 1}, $kind${sounding ? ', playing' : ''}. '
          'Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _controller.cycleBeat(beat),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: child,
        ),
      ),
    );
  }

  Widget _block(int beat, StepLevel level, {required bool sounding}) {
    final colors = context.colors;
    final muted = level == StepLevel.silent;
    final accent = level == StepLevel.accent;
    final color = muted
        ? colors.mutedFill
        : accent
        ? (sounding ? colors.accentSounding : colors.accentResting)
        : (sounding ? colors.beatSounding : colors.beatResting);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        key: ValueKey('beat-$beat-${sounding ? 'on' : 'off'}'),
        height: 36,
        color: color,
        child: muted
            ? CustomPaint(painter: _MutedLine(colors.mutedLine))
            : null,
      ),
    );
  }

  Widget _tick(int beat, int tick, {required bool sounding}) => Container(
    key: ValueKey('tick-$beat-$tick-${sounding ? 'on' : 'off'}'),
    height: 5,
    color: sounding ? context.colors.tickSounding : context.colors.tickResting,
  );
}

/// One thin diagonal, bottom-left to top-right: muted, explicit but quiet.
class _MutedLine extends CustomPainter {
  _MutedLine(this.color);

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
  bool shouldRepaint(_MutedLine old) => old.color != color;
}
