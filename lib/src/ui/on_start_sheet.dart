import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../model/on_start.dart';
import 'choices.dart';
import 'haptics.dart';
import 'motion.dart';
import 'theme.dart';
import 'top_panel.dart';
import 'value_stepper.dart';

/// The "When I press Start" panel (ui-spec.md, `on-start-sheet.reference
/// .html`), dropping from the stopwatch button (which also closes it):
/// Count-in, Speed up (Practice speed for a song with parts), Stop after.
/// Changes apply at once and belong to the loaded song like its tempo.
Future<void> showOnStartSheet(
  BuildContext context,
  MetronomeController metronome,
) => TopPanel.toggle(
  context,
  id: OnStartSheet,
  child: OnStartSheet(metronome: metronome),
);

class OnStartSheet extends StatelessWidget {
  const OnStartSheet({super.key, required this.metronome});

  final MetronomeController metronome;

  static const countInKey = Key('count-in');
  static const speedUpKey = Key('speed-up');
  static const stopAfterKey = Key('stop-after');
  static const countInBarsKey = Key('count-in-bars');
  static const stopByKey = Key('stop-by');
  static const practiceKey = Key('practice-speed');
  static const practiceFromKey = Key('practice-from');
  static const practiceStepKey = Key('practice-step');
  static const practiceUpToKey = Key('practice-up-to');

  static const countInHint =
      'Beats only, before the song. Not counted in the steps or the limit.';
  static const speedUpHint = 'Each change lands on a bar line.';
  static const stopAfterHint = 'Stops at the next bar line after the limit.';
  static const practiceHint =
      'Every part plays at this speed, ramps included. With "Loop song", '
      'it changes each time the song starts over.';

  static const changeLabel = 'Change by';
  static const everyLabel = 'Every';
  static const lengthLabel = 'Length';
  static const countByLabel = 'Count by';

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

  /// "80%, +5% each loop, up to 100%"; "80%" alone with +0%.
  static String practiceSummary(OnStart on) => on.practiceStep == 0
      ? '${on.practiceFrom}%'
      : '${on.practiceFrom}%, ${stepLabel(on.practiceStep)} each loop, '
            'up to ${on.practiceUpTo}%';

  /// "Stay", "+2.5%".
  static String stepLabel(num step) =>
      step == 0 ? 'Stay' : '+${OnStart.percentLabel(step)}';

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
                    Choices<int>(
                      key: countInBarsKey,
                      label: lengthLabel,
                      options: const {1: '1 bar', 2: '2 bars'},
                      selected: on.countInBars,
                      onSelected: (bars) => set(on.copyWith(countInBars: bars)),
                    ),
                    const SizedBox(height: 8),
                    Text(countInHint, style: hint),
                  ],
                ),
                // The parts decide the tempo, so a percentage of them
                // (ui-spec.md "Practice speed").
                if (metronome.playsParts)
                  _part(
                    context,
                    switchKey: practiceKey,
                    name: 'Practice speed',
                    on: on.practiceOn,
                    summary: practiceSummary(on),
                    onChanged: (v) => set(on.copyWith(practiceOn: v)),
                    controls: [
                      ..._practice(on, set),
                      const SizedBox(height: 4),
                      Text(practiceHint, style: hint),
                    ],
                  )
                else
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
                    Choices<StopBy>(
                      key: stopByKey,
                      label: countByLabel,
                      options: const {StopBy.bars: 'Bars', StopBy.time: 'Time'},
                      selected: on.stopBy,
                      onSelected: (v) => set(on.copyWith(stopBy: v)),
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
                      // The sheet's main headings.
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (on)
                        Text(
                          summary,
                          // Practice speed's is long; it wraps, never cut.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: colors.muted),
                        ),
                    ],
                  ),
                ),
                Switch(
                  key: switchKey,
                  value: on,
                  // Off is not disabled: a white outline and knob on a clear
                  // track; on, a white track and a black knob.
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? colors.text
                        : colors.sheet.withAlpha(0),
                  ),
                  trackOutlineColor: WidgetStatePropertyAll(colors.text),
                  trackOutlineWidth: const WidgetStatePropertyAll(2),
                  thumbColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? colors.background
                        : colors.text,
                  ),
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

  /// Start at, Each loop, and Up to while Each loop climbs.
  List<Widget> _practice(OnStart on, void Function(OnStart) set) {
    const min = OnStart.minPractice, max = OnStart.maxPractice;
    // Typed: any whole percent, within [lo]–[hi].
    int typed(String text, int lo, int hi) => OnStart.clampInt(
      int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? lo,
      lo,
      hi,
    );
    // − / + move on the 5% grid (83 → 85 / 80).
    int up(int v, int hi) => OnStart.stepUp(v, const [(max, 5)], hi);
    int down(int v, int lo) => OnStart.stepDown(v, const [(max, 5)], lo);

    final from = on.practiceFrom, step = on.practiceStep;
    final upTo = on.practiceUpTo;
    const steps = OnStart.practiceSteps;
    final at = steps.indexOf(step);
    return [
      ValueStepper(
        key: practiceFromKey,
        compact: true,
        onSheet: true,
        label: 'Start at',
        display: '$from%',
        editText: '$from',
        onMinus: from > min
            ? () => set(on.withPracticeFrom(down(from, min)))
            : null,
        onPlus: from < max
            ? () => set(on.withPracticeFrom(up(from, max)))
            : null,
        onTyped: (text) => set(on.withPracticeFrom(typed(text, min, max))),
      ),
      ValueStepper(
        key: practiceStepKey,
        compact: true,
        onSheet: true,
        label: 'Each loop',
        display: stepLabel(step),
        editText: step == 0 ? '0' : '$step',
        onMinus: at > 0
            ? () => set(on.copyWith(practiceStep: steps[at - 1]))
            : null,
        onPlus: at < steps.length - 1
            ? () => set(on.copyWith(practiceStep: steps[at + 1]))
            : null,
        // Snaps to the nearest step.
        onTyped: (text) {
          final v = num.tryParse(
            text.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''),
          );
          if (v != null) set(on.copyWith(practiceStep: OnStart.nearestStep(v)));
        },
      ),
      // Nothing to reach without a step.
      ArriveLeave(
        child: step == 0
            ? null
            : ValueStepper(
                key: practiceUpToKey,
                compact: true,
                onSheet: true,
                label: 'Up to',
                display: '$upTo%',
                editText: '$upTo',
                onMinus: upTo > from
                    ? () => set(on.copyWith(practiceUpTo: down(upTo, from)))
                    : null,
                onPlus: upTo < max
                    ? () => set(on.copyWith(practiceUpTo: up(upTo, max)))
                    : null,
                onTyped: (text) =>
                    set(on.copyWith(practiceUpTo: typed(text, from, max))),
              ),
      ),
    ];
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
        compact: true,
        onSheet: true,
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
        compact: true,
        onSheet: true,
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
        compact: true,
        onSheet: true,
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
        compact: true,
        onSheet: true,
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
      compact: true,
      onSheet: true,
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
