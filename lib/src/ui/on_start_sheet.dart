import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../model/on_start.dart';
import 'haptics.dart';
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

  static const countInHint =
      'Beats only, before the song. Not counted in the steps or the limit.';
  static const speedUpHint = 'Each change lands on a bar line.';
  static const stopAfterHint = 'Stops at the next bar line after the limit.';

  static const changeLabel = 'Change by';
  static const everyLabel = 'Every';
  static const untilLabel = 'Until';
  static const lengthLabel = 'Length';

  /// The first + from "No limit": the current tempo + 20.
  static const untilJump = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = TextStyle(fontSize: 14, color: colors.muted);
    final hint = label.copyWith(fontSize: 13, height: 1.4);
    const segmentStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ListenableBuilder(
          listenable: metronome,
          builder: (context, _) {
            final on = metronome.onStart;
            void set(OnStart next) => metronome.setOnStart(next);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 18),
                  child: Text(
                    'When I press Start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Count-in', style: label),
                const SizedBox(height: 8),
                Segmented<int>(
                  key: countInKey,
                  options: const {0: 'Off', 1: '1 bar', 2: '2 bars'},
                  selected: on.countIn,
                  style: segmentStyle,
                  onSelected: (bars) {
                    Haptics.tick();
                    set(on.copyWith(countIn: bars));
                  },
                ),
                const SizedBox(height: 8),
                Text(countInHint, style: hint),
                const SizedBox(height: 20),
                // The switch row is the label, like the reference.
                MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(child: Text('Speed up', style: label)),
                      Switch(
                        key: speedUpKey,
                        value: on.speedUp,
                        onChanged: (v) {
                          Haptics.tick();
                          set(on.copyWith(speedUp: v));
                        },
                      ),
                    ],
                  ),
                ),
                if (on.speedUp) ...[
                  ..._speedUp(on, set),
                  const SizedBox(height: 4),
                  Text(speedUpHint, style: hint),
                ],
                const SizedBox(height: 20),
                Text('Stop after', style: label),
                const SizedBox(height: 8),
                Segmented<StopAfter>(
                  key: stopAfterKey,
                  options: const {
                    StopAfter.off: 'Off',
                    StopAfter.bars: 'Bars',
                    StopAfter.time: 'Time',
                  },
                  selected: on.stopAfter,
                  style: segmentStyle,
                  onSelected: (v) {
                    Haptics.tick();
                    set(on.copyWith(stopAfter: v));
                  },
                ),
                if (on.stopAfter != StopAfter.off) ...[
                  const SizedBox(height: 4),
                  _length(on, set),
                  const SizedBox(height: 4),
                  Text(stopAfterHint, style: hint),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _speedUp(OnStart on, void Function(OnStart) set) {
    final until = on.until;
    return [
      ValueStepper(
        label: changeLabel,
        signed: true,
        display: OnStart.changeLabel(on.changeBy),
        editText: '${on.changeBy}',
        onMinus: on.changeBy > OnStart.minChange
            ? () => set(on.copyWith(changeBy: OnStart.changeDown(on.changeBy)))
            : null,
        onPlus: on.changeBy < OnStart.maxChange
            ? () => set(on.copyWith(changeBy: OnStart.changeUp(on.changeBy)))
            : null,
        onTyped: (text) {
          final v = int.tryParse(text.replaceAll('−', '-'));
          if (v == null) return;
          // 0 does nothing: the nearest allowed is +1.
          set(
            on.copyWith(
              changeBy: v == 0
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
        label: untilLabel,
        display: until == null ? 'No limit' : '$until',
        editText: until == null ? '' : '$until',
        // − from the lowest tempo goes back to "No limit".
        onMinus: until == null
            ? null
            : () => set(
                on.withUntil(
                  until <= MetronomeController.minBpm
                      ? null
                      : OnStart.stepDown(
                          until,
                          OnStart.untilGrid,
                          MetronomeController.minBpm,
                        ),
                ),
              ),
        onPlus: until != null && until >= MetronomeController.maxBpm
            ? null
            : () => set(
                on.withUntil(
                  until == null
                      ? OnStart.clampInt(
                          metronome.startBpm + untilJump,
                          MetronomeController.minBpm,
                          MetronomeController.maxBpm,
                        )
                      : OnStart.stepUp(
                          until,
                          OnStart.untilGrid,
                          MetronomeController.maxBpm,
                        ),
                ),
              ),
        // An empty field is "No limit".
        onTyped: (text) {
          final v = int.tryParse(text);
          set(
            on.withUntil(
              v == null
                  ? null
                  : OnStart.clampInt(
                      v,
                      MetronomeController.minBpm,
                      MetronomeController.maxBpm,
                    ),
            ),
          );
        },
      ),
    ];
  }

  Widget _length(OnStart on, void Function(OnStart) set) {
    if (on.stopAfter == StopAfter.bars) {
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
