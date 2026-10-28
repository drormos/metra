import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import '../controller/rhythm_target.dart';
import '../model/metronome_pattern.dart';
import 'haptics.dart';
import 'meter_control.dart';
import 'segmented.dart';
import 'subdivision_icon.dart';
import 'theme.dart';
import 'top_panel.dart';

/// The Rhythm sheet (ui-spec.md, `on-start.reference.html`): the quick
/// picks apply with one tap and close it; the time signature editor,
/// Subdivision and
/// Polyrhythm apply as they change and keep it open. Through
/// [MetronomeController.setMeter], so beat states are kept and, while
/// playing, the next beat starts a bar; a subdivision lands on the next
/// beat.
/// Opens (or, open already, closes) the Rhythm panel under the top row.
/// [header] goes right under the heading (the main screen's "Song parts"
/// row, ui-spec.md "The row explains itself and comes first").
Future<void> showTimeSignatureSheet(
  BuildContext context,
  MetronomeController metronome, {
  Widget? header,
}) => TopPanel.toggle(
  context,
  id: TimeSignatureSheet,
  child: TimeSignatureSheet(rhythm: metronome, header: header),
);

class TimeSignatureSheet extends StatelessWidget {
  const TimeSignatureSheet({super.key, required this.rhythm, this.header});

  final RhythmTarget rhythm;
  final Widget? header;

  static const subdivisionKey = Key('subdivision');

  /// Spoken names of the subdivisions, by clicks per beat.
  static const subdivisionNames = {
    1: 'Quarter notes',
    2: 'Eighth notes',
    3: 'Triplets',
    4: 'Sixteenth notes',
  };

  /// The quick picks under the editor, always in the same place.
  static const quickPicks = [(3, 4), (4, 4), (6, 8), (12, 8)];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = TextStyle(fontSize: 14, color: colors.muted);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ListenableBuilder(
          listenable: rhythm,
          builder: (context, _) {
            final pattern = rhythm.pattern;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 18),
                  child: Text(
                    'Rhythm',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                if (header case final header?) ...[
                  header,
                  const SizedBox(height: 16),
                ],
                // One editor, and one row of quick picks under it
                // (ui-spec.md "Time signature: one editor + one row of quick
                // picks").
                Text('Time signature', style: label),
                const SizedBox(height: 8),
                MeterControl(
                  size: 52,
                  beats: pattern.beatsPerBar,
                  unit: pattern.beatUnit,
                  onChanged: (beats, unit) {
                    Haptics.tick();
                    rhythm.setMeter(beats, unit);
                  },
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    for (final (i, (beats, unit)) in quickPicks.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _quickPick(
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
                const SizedBox(height: 24),
                Text('Subdivision', style: label),
                const SizedBox(height: 8),
                Segmented<int>(
                  key: subdivisionKey,
                  options: subdivisionNames,
                  selected: pattern.stepsPerBeat,
                  icon: (steps) => SubdivisionIcon(steps, size: 24),
                  onSelected: (steps) {
                    Haptics.tick();
                    rhythm.setSubdivision(steps);
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
                rhythm.setPolyrhythm(n);
              }
            : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
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
                    : colors.disabledText,
              ),
            ),
          ),
        ),
      ),
    ),
  );

  /// A pill chip (36px in a 48dp touch target): the current one filled
  /// and outlined in the text color; tap applies it and closes the sheet.
  Widget _quickPick(
    BuildContext context,
    MetraColors colors,
    int beats,
    int unit, {
    required bool selected,
  }) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      key: ValueKey('quick-$beats-$unit'),
      customBorder: const StadiumBorder(),
      onTap: () {
        Haptics.tick();
        rhythm.setMeter(beats, unit);
        Navigator.pop(context);
      },
      child: SizedBox(
        height: 48,
        child: Center(
          child: Container(
            height: 36,
            decoration: ShapeDecoration(
              color: selected ? colors.tickResting : null,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected ? colors.text : colors.border,
                  width: 2,
                ),
              ),
            ),
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$beats/$unit',
                style: TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.text : colors.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
