import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../model/metronome_pattern.dart';
import 'haptics.dart';
import 'meter_control.dart';
import 'swipe_row.dart';
import 'theme.dart';

/// The time signature sheet (ui-spec.md, `time-signature.reference.html`):
/// "Common" meters apply with one tap and close it; "Custom" applies as
/// it changes and keeps it open. Through [MetronomeController.setMeter], so
/// beat states are kept and, while playing, the next beat starts a bar.
Future<void> showTimeSignatureSheet(
  BuildContext context,
  MetronomeController metronome,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // Our own drag (closes past a third, or on a flick down; Flutter's
  // closes past half), so the sheet draws its own surface and handle.
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: context.colors.sheet.withAlpha(0),
  elevation: 0,
  builder: (context) => DragToClose(
    axis: Axis.vertical,
    onClose: () => Navigator.pop(context),
    child: Material(
      color: context.colors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            key: TimeSignatureSheet.handleKey,
            margin: const EdgeInsets.symmetric(vertical: 22),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.beatResting,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(child: TimeSignatureSheet(metronome: metronome)),
        ],
      ),
    ),
  ),
);

class TimeSignatureSheet extends StatelessWidget {
  const TimeSignatureSheet({super.key, required this.metronome});

  final MetronomeController metronome;

  static const handleKey = Key('sheet-handle');

  static const common = [
    (2, 4),
    (3, 4),
    (4, 4),
    (5, 4),
    (6, 8),
    (7, 8),
    (9, 8),
    (12, 8),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = TextStyle(fontSize: 14, color: colors.muted);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ListenableBuilder(
          listenable: metronome,
          builder: (context, _) {
            final pattern = metronome.pattern;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 18),
                  child: Text(
                    'Time signature',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Common', style: label),
                const SizedBox(height: 8),
                for (final row in [common.sublist(0, 4), common.sublist(4)])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        for (final (i, (beats, unit)) in row.indexed) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _commonButton(
                              context,
                              colors,
                              beats,
                              unit,
                              selected:
                                  pattern.beatsPerBar == beats &&
                                  pattern.beatUnit == unit,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Custom', style: label),
                const SizedBox(height: 8),
                MeterControl(
                  size: 52,
                  beats: pattern.beatsPerBar,
                  unit: pattern.beatUnit,
                  onChanged: (beats, unit) {
                    Haptics.tick();
                    metronome.setMeter(beats, unit);
                  },
                ),
                const SizedBox(height: 24),
                Text('Polyrhythm', style: label),
                const SizedBox(height: 8),
                _polyrhythm(colors, pattern.polyrhythm, pattern.beatsPerBar),
                const SizedBox(height: 8),
                Text(
                  polyrhythmHint(pattern.polyrhythm, pattern.beatsPerBar),
                  style: label.copyWith(height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The muted line under the Polyrhythm row, in plain words.
  static String polyrhythmHint(int n, int beats) => n == 0
      ? 'Add a second pulse across each bar'
      : '$n against $beats: ${_words[n]} even clicks per bar, in their own '
            'sound';

  static const _words = [
    '',
    '',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
  ];

  /// "Off · 2 … 7" in one frame; the beat count itself is dimmed and can't
  /// be chosen (n against n is just the beat). Applies at once (while
  /// playing, from the next beat; Off stops at once); the sheet stays.
  Widget _polyrhythm(MetraColors colors, int selected, int beats) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: colors.border, width: 2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Row(
        children: [
          for (var n = 0; n <= MetronomePattern.maxPolyrhythm; n++)
            if (n != 1)
              Expanded(
                flex: n == 0 ? 14 : 10,
                child: _polySegment(
                  colors,
                  n,
                  selected: n == selected,
                  enabled: n != beats,
                ),
              ),
        ],
      ),
    ),
  );

  Widget _polySegment(
    MetraColors colors,
    int n, {
    required bool selected,
    required bool enabled,
  }) => Semantics(
    button: true,
    selected: selected,
    enabled: enabled,
    label: n == 0 ? 'Polyrhythm off' : 'Polyrhythm $n',
    excludeSemantics: true,
    child: Material(
      color: selected ? colors.text : colors.background,
      child: InkWell(
        key: ValueKey('poly-$n'),
        onTap: enabled
            ? () {
                Haptics.tick();
                metronome.setPolyrhythm(n);
              }
            : null,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              n == 0 ? 'Off' : '$n',
              style: TextStyle(
                fontFamily: n == 0 ? null : MetraFonts.condensed,
                fontSize: n == 0 ? 15 : 24,
                fontWeight: n == 0 ? FontWeight.w600 : FontWeight.w700,
                color: selected
                    ? colors.background
                    : enabled
                    ? colors.text
                    : colors.beatResting,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _commonButton(
    BuildContext context,
    MetraColors colors,
    int beats,
    int unit, {
    required bool selected,
  }) => SizedBox(
    height: 56,
    child: OutlinedButton(
      key: ValueKey('common-$beats-$unit'),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: selected ? colors.text : null,
        foregroundColor: selected ? colors.background : colors.text,
        side: selected ? BorderSide.none : null,
      ),
      onPressed: () {
        Haptics.tick();
        metronome.setMeter(beats, unit);
        Navigator.pop(context);
      },
      child: Text(
        '$beats/$unit',
        style: const TextStyle(
          fontFamily: MetraFonts.condensed,
          fontSize: 26,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
