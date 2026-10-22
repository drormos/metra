import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import 'haptics.dart';
import 'segmented.dart';
import 'theme.dart';
import 'time_signature_sheet.dart';

/// The "When I press Start" sheet (ui-spec.md, `on-start.reference.html`
/// column 2), opened from the stopwatch button. Step 1: Count-in only.
/// Changes apply at once and belong to the loaded song like its tempo.
Future<void> showOnStartSheet(
  BuildContext context,
  MetronomeController metronome,
) => showDragSheet(context, child: OnStartSheet(metronome: metronome));

class OnStartSheet extends StatelessWidget {
  const OnStartSheet({super.key, required this.metronome});

  final MetronomeController metronome;

  static const countInKey = Key('count-in');

  static const countInHint =
      'Beats only, before the song. Not counted in the steps or the limit.';

  @override
  Widget build(BuildContext context) {
    final label = TextStyle(fontSize: 14, color: context.colors.muted);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ListenableBuilder(
          listenable: metronome,
          builder: (context, _) => Column(
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
                selected: metronome.countIn,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (bars) {
                  Haptics.tick();
                  metronome.setCountIn(bars);
                },
              ),
              const SizedBox(height: 8),
              Text(
                countInHint,
                style: label.copyWith(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
