import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'haptics.dart';
import 'theme.dart';

/// The polyrhythm lane (ui-spec.md "Polyrhythm", `polyrhythm.reference
/// .html`): n cells placed by time across the bar's width, with the beat
/// blocks' 6px gaps, so cell 1 lines up with beat 1. Cells show their
/// state at rest and only the sounding one lights, for the length of its
/// pulse (engine clock plus the visual offset, once per frame). Tapping a
/// cell cycles regular → accent → muted.
class PolyLane extends StatefulWidget {
  const PolyLane({super.key, required this.controller});

  final MetronomeController controller;

  static const height = 22.0;

  @override
  State<PolyLane> createState() => _PolyLaneState();
}

class _PolyLaneState extends State<PolyLane>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  // Display-only: derived from the engine clock every frame.
  ScheduledPulse? _pulse;

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
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      if (_pulse != null) setState(() => _pulse = null);
    }
  }

  // The frame timestamp, shared with the beat blocks (same smoother).
  void _onTick(Duration _) {
    final pulse = _controller.visualPulseAt(
      SchedulerBinding.instance.currentFrameTimeStamp,
    );
    if (pulse?.time != _pulse?.time) setState(() => _pulse = pulse);
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _controller.pattern;
    final n = pattern.polyrhythm;
    final pulse = _pulse;
    // Only a pulse of the lane being drawn lights, and never a muted one.
    final sounding =
        pulse != null && pulse.count == n && pulse.level != StepLevel.silent
        ? pulse.pulse
        : null;
    return Semantics(
      label: '$n against ${pattern.beatsPerBar}',
      container: true,
      child: Row(
        children: [
          for (var k = 0; k < n; k++) ...[
            if (k > 0) const SizedBox(width: 6),
            Expanded(
              child: _cell(k, pattern.polyStates[k], sounding: k == sounding),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(int k, StepLevel level, {required bool sounding}) {
    final colors = context.colors;
    final muted = level == StepLevel.silent;
    final accent = level == StepLevel.accent;
    final color = muted
        ? colors.background
        : accent
        ? (sounding ? colors.accent : colors.pulseAccentResting)
        : (sounding ? colors.beatSounding : colors.pulseResting);
    final kind = muted ? 'muted' : (accent ? 'accented' : 'regular');
    final n = _controller.pattern.polyrhythm;
    return Semantics(
      button: true,
      label:
          'Pulse ${k + 1} of $n, $kind${sounding ? ', playing' : ''}. '
          'Tap to change.',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.tick();
          _controller.cyclePulse(k);
        },
        child: CustomPaint(
          key: ValueKey('pulse-$k-${sounding ? 'on' : 'off'}'),
          painter: _Cell(color, muted ? colors.pulseMutedLine : null),
          size: const Size.fromHeight(PolyLane.height),
        ),
      ),
    );
  }
}

/// A 3px-radius cell; muted ones get a thin dashed outline instead.
class _Cell extends CustomPainter {
  _Cell(this.fill, this.dashes);

  final Color fill;
  final Color? dashes;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(3),
    );
    canvas.drawRRect(rect, Paint()..color = fill);
    final dashes = this.dashes;
    if (dashes == null) return;
    final paint = Paint()
      ..color = dashes
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Cell old) => old.fill != fill || old.dashes != dashes;
}
