import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'beat_indicator.dart';
import 'haptics.dart';
import 'theme.dart';

/// The polyrhythm lane (ui-spec.md "Polyrhythm", `polyrhythm.reference
/// .html`): n cells placed by time across the bar's width, with the beat
/// blocks' 6px gaps, so cell 1 lines up with beat 1. Cells show their
/// state at rest and each one pulses when it sounds ([beatPulse]; engine
/// clock plus the visual offset, once per frame). Tapping a
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
  // Lights by cell (one can rise before its pulse while the last comes
  // down).
  Map<int, double> _lights = const {};

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
  // Each cell pulses at its own pulse ([beatPulse]).
  void _onTick(Duration _) {
    final now = _controller.visualTimeAt(
      SchedulerBinding.instance.currentFrameTimeStamp,
    );
    final pulse = now == null ? null : _controller.pulseAt(now);
    final lights = <int, double>{};
    if (now != null) {
      final reduced = MetraMotion.reduced(context);
      final next = _controller.pulseAt(now + MetraMotion.lightLead);
      for (final p in {?pulse, ?next}) {
        // Only a pulse of the lane being drawn lights, never a muted one.
        if (p.level == StepLevel.silent ||
            p.count != _controller.pattern.polyrhythm) {
          continue;
        }
        final v = beatPulse(now - p.time, p.end - p.time, reduced: reduced);
        if (v > (lights[p.pulse] ?? 0)) lights[p.pulse] = v;
      }
    }
    if (pulse?.time != _pulse?.time || !mapEquals(lights, _lights)) {
      setState(() {
        _pulse = pulse;
        _lights = lights;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _controller.pattern;
    final n = pattern.polyrhythm;
    return Semantics(
      label: '$n against ${pattern.beatsPerBar}',
      container: true,
      child: Row(
        children: [
          for (var k = 0; k < n; k++) ...[
            if (k > 0) const SizedBox(width: 6),
            Expanded(
              child: _cell(k, pattern.polyStates[k], light: _lights[k] ?? 0),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(int k, StepLevel level, {required double light}) {
    final colors = context.colors;
    final muted = level == StepLevel.silent;
    final accent = level == StepLevel.accent;
    final sounding = light > 0;
    final color = muted
        ? colors.background
        : accent
        ? Color.lerp(colors.pulseAccentResting, colors.accent, light)!
        : Color.lerp(colors.pulseResting, colors.beatSounding, light)!;
    final kind = muted ? 'muted' : (accent ? 'accented' : 'regular');
    final n = _controller.pattern.polyrhythm;
    return Semantics(
      button: true,
      label: 'Pulse ${k + 1} of $n, $kind',
      onTapHint: 'change',
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
