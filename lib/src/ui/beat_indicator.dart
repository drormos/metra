import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';

/// One dot per step of the bar; the current step lights up when the engine
/// clock (plus the visual offset) reaches it. Checked once per frame.
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
    // switch the controller already holds the next pattern until the bar
    // line.
    final step = _step;
    final pattern = step?.pattern ?? _controller.pattern;
    final litBeat = step == null
        ? null
        : step.barPosition ~/ pattern.stepsPerBeat;
    final colors = Theme.of(context).colorScheme;
    // Scales down for long bars (12/8) on narrow phones.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        children: [
          for (final (i, level) in pattern.beatLevels.indexed)
            _dot(index: i, level: level, lit: i == litBeat, colors: colors),
        ],
      ),
    );
  }

  /// One dot per beat. Tapping cycles the beat normal → accent → silent,
  /// heard from the next click.
  Widget _dot({
    required int index,
    required StepLevel level,
    required bool lit,
    required ColorScheme colors,
  }) {
    final accent = level == StepLevel.accent;
    final silent = level == StepLevel.silent;
    final size = accent ? 32.0 : 24.0;
    final edge = silent
        ? colors.onSurface.withValues(alpha: 0.3)
        : colors.onSurface;
    return Semantics(
      button: true,
      label: 'Beat ${index + 1}: ${level.name}. Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _controller.cycleBeat(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Container(
            key: ValueKey('beat-$index-${lit ? 'on' : 'off'}'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: !lit
                  ? null
                  : silent
                  ? edge
                  : accent
                  ? colors.primary
                  : colors.onSurface,
              border: Border.all(color: edge, width: 2),
            ),
          ),
        ),
      ),
    );
  }
}
