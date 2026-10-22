import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../model/on_start.dart';
import 'haptics.dart';
import 'motion.dart';
import 'theme.dart';
import 'top_panel.dart';
import 'value_stepper.dart';

/// The "When I press Start" panel (ui-spec.md, `on-start-sheet.reference
/// .html`), dropping from the stopwatch button (which also closes it):
/// Count-in, Speed up, Stop after. Changes apply at once and belong to the
/// loaded song like its tempo.
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

  static const countInHint =
      'Beats only, before the song. Not counted in the steps or the limit.';
  static const speedUpHint = 'Each change lands on a bar line.';
  static const stopAfterHint = 'Stops at the next bar line after the limit.';

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
                    _Choices<int>(
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
                    _Choices<StopBy>(
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

/// Quiet choices laid out like a stepper row (ui-spec.md "Choices inside
/// a part"): a label on the left, 36px pill chips sized to their text on
/// the right. Selected: the tick-resting grey (#2A2A2A) with a 2px text
/// color border and semibold text; the others clear with a 2px border and
/// muted text. Each chip is a 48dp touch target.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        for (final (i, MapEntry(key: value, value: text))
            in options.entries.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          _chip(colors, value, text, selected: value == selected),
        ],
      ],
    );
  }

  Widget _chip(
    MetraColors colors,
    T value,
    String text, {
    required bool selected,
  }) {
    const shape = StadiumBorder();
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('chip-$value'),
        customBorder: shape,
        onTap: () {
          Haptics.tick();
          onSelected(value);
        },
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: selected ? colors.tickResting : null,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? colors.text : colors.border,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? colors.text : colors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
