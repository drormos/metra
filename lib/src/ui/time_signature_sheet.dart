import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import 'haptics.dart';
import 'meter_control.dart';
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
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => TimeSignatureSheet(metronome: metronome),
);

class TimeSignatureSheet extends StatelessWidget {
  const TimeSignatureSheet({super.key, required this.metronome});

  final MetronomeController metronome;

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
              ],
            );
          },
        ),
      ),
    );
  }

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
