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
    final pattern = _controller.pattern;
    final colors = Theme.of(context).colorScheme;
    final current = _step == null ? null : _step!.index % pattern.stepsPerBar;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < pattern.stepsPerBar; i++)
          _dot(
            lit: i == current,
            accent: pattern.steps[i] == StepLevel.accent,
            index: i,
            colors: colors,
          ),
      ],
    );
  }

  Widget _dot({
    required bool lit,
    required bool accent,
    required int index,
    required ColorScheme colors,
  }) {
    final size = accent ? 32.0 : 24.0;
    return Container(
      key: ValueKey('beat-$index-${lit ? 'on' : 'off'}'),
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: lit ? (accent ? colors.primary : colors.onSurface) : null,
        border: Border.all(color: colors.onSurface, width: 2),
      ),
    );
  }
}
