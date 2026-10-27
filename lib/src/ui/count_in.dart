import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller/metronome_controller.dart';

/// Where a count-in is: [bar] of [bars], beat [beat] of [of].
typedef CountIn = ({int bar, int bars, int beat, int of});

/// The count-in at engine time [now] (the visual clock), or null outside
/// one. Before the first click sounds it is already bar 1, beat 1, so
/// nothing shows a bare "Count-in" first (ui-spec.md "Count-in", "Shown
/// from the moment you press Start").
CountIn? countInAt(MetronomeController controller, Duration? now) {
  final step = now == null ? null : controller.stepAt(now);
  if (step?.countIn case final c?) {
    return (
      bar: c.bar,
      bars: c.bars,
      beat: step!.barPosition + 1,
      of: step.pattern.beatsPerBar,
    );
  }
  if (step != null || !controller.countingIn) return null;
  return (
    bar: 1,
    bars: controller.onStart.countIn,
    beat: 1,
    of: controller.pattern.beatsPerBar,
  );
}

/// "Count-in · 3 of 4" ("Count-in · 2 · 3 of 4" in bar 2 of 2).
String countInLine(CountIn c) => c.bars > 1
    ? 'Count-in · ${c.bar} · ${c.beat} of ${c.of}'
    : 'Count-in · ${c.beat} of ${c.of}';

/// Rebuilds [builder] with the count-in as it plays (read once per frame
/// from the engine clock, like the beat lights), null outside one. Ticks
/// only while playing.
class CountInBuilder extends StatefulWidget {
  const CountInBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  final MetronomeController controller;
  final Widget Function(BuildContext context, CountIn? countIn) builder;

  @override
  State<CountInBuilder> createState() => _CountInBuilderState();
}

class _CountInBuilderState extends State<CountInBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _read());
  CountIn? _countIn;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    // Built as playback starts (the Stop button appears): the count from
    // its first frame, not one frame later.
    _countIn = _now();
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.controller.isPlaying) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      if (_countIn != null) setState(() => _countIn = null);
    }
  }

  CountIn? _now() => countInAt(
    widget.controller,
    widget.controller.visualTimeAt(
      SchedulerBinding.instance.currentFrameTimeStamp,
    ),
  );

  void _read() {
    final countIn = _now();
    if (countIn != _countIn) setState(() => _countIn = countIn);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _countIn);
}

/// The red Stop button's content: "■ Stop", and during a count-in
/// "■ Stop · Count-in 3 of 4" (the count regular). When that doesn't fit
/// on one line, two lines: "■ Stop", then the count, smaller; scaled down
/// rather than split or cut (ui-spec.md "The button you pressed shows the
/// count").
class StopLabel extends StatelessWidget {
  const StopLabel({
    super.key,
    required this.controller,
    required this.fontSize,
    required this.iconSize,
  });

  final MetronomeController controller;
  final double fontSize;
  final double iconSize;

  @override
  Widget build(BuildContext context) => CountInBuilder(
    controller: controller,
    builder: (context, countIn) {
      final stop = TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600);
      final icon = Icon(Icons.stop, size: iconSize);
      final gap = SizedBox(width: iconSize / 3);
      Widget line(Widget text) =>
          Row(mainAxisSize: MainAxisSize.min, children: [icon, gap, text]);
      if (countIn == null) return line(Text('Stop', style: stop));
      final count = 'Count-in ${countIn.beat} of ${countIn.of}';
      final regular = stop.copyWith(fontWeight: FontWeight.w400);
      final one = TextSpan(
        children: [
          TextSpan(text: 'Stop', style: stop),
          TextSpan(text: ' · $count', style: regular),
        ],
      );
      return LayoutBuilder(
        builder: (context, box) {
          final painter = TextPainter(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [one],
            ),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          final width = iconSize + iconSize / 3 + painter.width;
          painter.dispose();
          if (width <= box.maxWidth) {
            return line(Text.rich(one, maxLines: 1, softWrap: false));
          }
          return FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                line(Text('Stop', style: stop)),
                Text(
                  count,
                  maxLines: 1,
                  softWrap: false,
                  style: regular.copyWith(fontSize: fontSize * 0.7),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
