import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../model/on_start.dart';
import 'haptics.dart';
import 'motion.dart';
import 'segmented.dart';
import 'theme.dart';
import 'time_signature_sheet.dart';
import 'value_stepper.dart';

/// The "When I press Start" sheet (ui-spec.md, `on-start-sheet.reference
/// .html`), opened from the stopwatch button: Count-in, Speed up, Stop
/// after. Changes apply at once and belong to the loaded song like its
/// tempo.
Future<void> showOnStartSheet(
  BuildContext context,
  MetronomeController metronome,
) => showDragSheet(context, child: OnStartSheet(metronome: metronome));

class OnStartSheet extends StatelessWidget {
  const OnStartSheet({super.key, required this.metronome});

  final MetronomeController metronome;

  static const countInKey = Key('count-in');
  static const speedUpKey = Key('speed-up');
  static const stopAfterKey = Key('stop-after');
  static const countInBarsKey = Key('count-in-bars');
  static const stopByKey = Key('stop-by');

  static const countInHint =
      'Beats only, before the song. Not counted in the steps or the limit.';
  static const speedUpHint = 'Each change lands on a bar line.';
  static const stopAfterHint = 'Stops at the next bar line after the limit.';

  static const changeLabel = 'Change by';
  static const everyLabel = 'Every';
  static const lengthLabel = 'Length';

  /// The first tap from "No limit": the current tempo ± 20.
  static const limitJump = 20;

  /// The muted line under a part's name while it's on.
  static String countInSummary(OnStart on) => OnStart.barsLabel(on.countInBars);

  static String speedUpSummary(OnStart on) {
    final every = on.every == 1 ? 'bar' : '${on.every} bars';
    final limit = on.upTo == null
        ? ''
        : ', ${on.limitLabel.toLowerCase()} ${on.upTo}';
    return '${OnStart.changeLabel(on.changeBy)} every $every$limit';
  }

  static String stopAfterSummary(OnStart on) => on.stopBy == StopBy.bars
      ? OnStart.barsLabel(on.stopBars)
      : OnStart.timeLabel(on.stopTime);

  @override
  Widget build(BuildContext context) {
    final hint = TextStyle(
      fontSize: 13,
      height: 1.4,
      color: context.colors.muted,
    );
    const segmentStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: ListenableBuilder(
          listenable: metronome,
          builder: (context, _) {
            final on = metronome.onStart;
            void set(OnStart next) => metronome.setOnStart(next);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 18),
                  child: Text(
                    'When I press Start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                _part(
                  context,
                  switchKey: countInKey,
                  name: 'Count-in',
                  on: on.countInOn,
                  summary: countInSummary(on),
                  onChanged: (v) => set(on.copyWith(countInOn: v)),
                  controls: [
                    Segmented<int>(
                      key: countInBarsKey,
                      options: const {1: '1 bar', 2: '2 bars'},
                      selected: on.countInBars,
                      style: segmentStyle,
                      onSelected: (bars) {
                        Haptics.tick();
                        set(on.copyWith(countInBars: bars));
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(countInHint, style: hint),
                  ],
                ),
                _part(
                  context,
                  switchKey: speedUpKey,
                  name: 'Speed up',
                  on: on.speedUp,
                  summary: speedUpSummary(on),
                  onChanged: (v) => set(on.copyWith(speedUp: v)),
                  controls: [
                    ..._speedUp(on, set),
                    const SizedBox(height: 4),
                    Text(speedUpHint, style: hint),
                  ],
                ),
                _part(
                  context,
                  switchKey: stopAfterKey,
                  name: 'Stop after',
                  on: on.stopOn,
                  summary: stopAfterSummary(on),
                  onChanged: (v) => set(on.copyWith(stopOn: v)),
                  controls: [
                    Segmented<StopBy>(
                      key: stopByKey,
                      options: const {StopBy.bars: 'Bars', StopBy.time: 'Time'},
                      selected: on.stopBy,
                      style: segmentStyle,
                      onSelected: (v) {
                        Haptics.tick();
                        set(on.copyWith(stopBy: v));
                      },
                    ),
                    const SizedBox(height: 4),
                    _length(on, set),
                    const SizedBox(height: 4),
                    Text(stopAfterHint, style: hint),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Every part is the same when off: a 56px row, its name and a switch.
  /// On, a muted summary sits under the name and the controls unfold below
  /// (arrive); off, they fold away (leave), the values kept.
  Widget _part(
    BuildContext context, {
    required Key switchKey,
    required String name,
    required bool on,
    required String summary,
    required ValueChanged<bool> onChanged,
    required List<Widget> controls,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: 56),
          // The switch's 48dp touch target sets the height inside 56.
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.divider)),
          ),
          child: MergeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontSize: 16)),
                      if (on)
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: colors.muted),
                        ),
                    ],
                  ),
                ),
                Switch(
                  key: switchKey,
                  value: on,
                  onChanged: (v) {
                    Haptics.tick();
                    onChanged(v);
                  },
                ),
              ],
            ),
          ),
        ),
        ArriveLeave(
          child: on
              ? Padding(
                  key: ValueKey('$name controls'),
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: controls,
                  ),
                )
              : null,
        ),
      ],
    );
  }

  List<Widget> _speedUp(OnStart on, void Function(OnStart) set) {
    final upTo = on.upTo;
    final bpm = metronome.startBpm;
    // Beyond the current tempo, within 30–300; null: no room.
    final range = on.limitRange(bpm);
    final start = range == null
        ? null
        : OnStart.clampInt(
            bpm + (on.changeBy > 0 ? limitJump : -limitJump),
            range.$1,
            range.$2,
          );
    final label = on.limitLabel;
    return [
      ValueStepper(
        label: changeLabel,
        signed: true,
        display: OnStart.changeLabel(on.changeBy),
        editText: '${on.changeBy}',
        onMinus: on.changeBy > OnStart.minChange
            ? () => set(on.withChangeBy(OnStart.changeDown(on.changeBy)))
            : null,
        onPlus: on.changeBy < OnStart.maxChange
            ? () => set(on.withChangeBy(OnStart.changeUp(on.changeBy)))
            : null,
        onTyped: (text) {
          final v = int.tryParse(text.replaceAll('−', '-'));
          if (v == null) return;
          // 0 does nothing: the nearest allowed is +1.
          set(
            on.withChangeBy(
              v == 0
                  ? 1
                  : OnStart.clampInt(v, OnStart.minChange, OnStart.maxChange),
            ),
          );
        },
      ),
      ValueStepper(
        label: everyLabel,
        display: OnStart.barsLabel(on.every),
        editText: '${on.every}',
        onMinus: on.every > OnStart.minEvery
            ? () => set(
                on.copyWith(
                  every: OnStart.stepDown(
                    on.every,
                    OnStart.everyGrid,
                    OnStart.minEvery,
                  ),
                ),
              )
            : null,
        onPlus: on.every < OnStart.maxEvery
            ? () => set(
                on.copyWith(
                  every: OnStart.stepUp(
                    on.every,
                    OnStart.everyGrid,
                    OnStart.maxEvery,
                  ),
                ),
              )
            : null,
        onTyped: (text) {
          final v = int.tryParse(text);
          if (v == null) return;
          set(
            on.copyWith(
              every: OnStart.clampInt(v, OnStart.minEvery, OnStart.maxEvery),
            ),
          );
        },
      ),
      ValueStepper(
        label: label,
        display: upTo == null ? 'No limit' : '$upTo',
        editText: upTo == null ? '' : '$upTo',
        // From "No limit" either button starts at the tempo ± 20; − from
        // the lowest allowed value goes back to "No limit".
        onMinus: range == null
            ? null
            : () => set(
                on.withUpTo(
                  upTo == null
                      ? start
                      : upTo <= range.$1
                      ? null
                      : OnStart.stepDown(upTo, OnStart.upToGrid, range.$1),
                ),
              ),
        onPlus: range == null || (upTo != null && upTo >= range.$2)
            ? null
            : () => set(
                on.withUpTo(
                  upTo == null
                      ? start
                      : OnStart.clampInt(
                          OnStart.stepUp(upTo, OnStart.upToGrid, range.$2),
                          range.$1,
                          range.$2,
                        ),
                ),
              ),
        // An empty field is "No limit".
        onTyped: (text) {
          final v = int.tryParse(text);
          set(
            on.withUpTo(
              v == null || range == null
                  ? null
                  : OnStart.clampInt(v, range.$1, range.$2),
            ),
          );
        },
      ),
    ];
  }

  Widget _length(OnStart on, void Function(OnStart) set) {
    if (on.stopBy == StopBy.bars) {
      final bars = on.stopBars;
      return ValueStepper(
        label: lengthLabel,
        display: '$bars',
        editText: '$bars',
        onMinus: bars > OnStart.minBars
            ? () => set(
                on.copyWith(
                  stopBars: OnStart.stepDown(
                    bars,
                    OnStart.barsGrid,
                    OnStart.minBars,
                  ),
                ),
              )
            : null,
        onPlus: bars < OnStart.maxBars
            ? () => set(
                on.copyWith(
                  stopBars: OnStart.stepUp(
                    bars,
                    OnStart.barsGrid,
                    OnStart.maxBars,
                  ),
                ),
              )
            : null,
        onTyped: (text) {
          final v = int.tryParse(text);
          if (v == null) return;
          set(
            on.copyWith(
              stopBars: OnStart.clampInt(v, OnStart.minBars, OnStart.maxBars),
            ),
          );
        },
      );
    }
    final s = on.stopTime.inSeconds;
    Duration secs(int v) => Duration(seconds: v);
    return ValueStepper(
      label: lengthLabel,
      time: true,
      display: OnStart.timeLabel(on.stopTime),
      editText: '${s ~/ 60}${(s % 60).toString().padLeft(2, '0')}',
      onMinus: on.stopTime > OnStart.minTime
          ? () => set(
              on.copyWith(
                stopTime: secs(
                  OnStart.stepDown(
                    s,
                    OnStart.timeGrid,
                    OnStart.minTime.inSeconds,
                  ),
                ),
              ),
            )
          : null,
      onPlus: on.stopTime < OnStart.maxTime
          ? () => set(
              on.copyWith(
                stopTime: secs(
                  OnStart.stepUp(
                    s,
                    OnStart.timeGrid,
                    OnStart.maxTime.inSeconds,
                  ),
                ),
              ),
            )
          : null,
      onTyped: (text) {
        final d = OnStart.parseTimeDigits(text);
        if (d == null) return;
        set(on.copyWith(stopTime: OnStart.clampTime(d)));
      },
    );
  }
}
