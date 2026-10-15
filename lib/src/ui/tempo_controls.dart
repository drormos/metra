import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import 'haptics.dart';
import 'repeat_button.dart';
import 'theme.dart';

/// The BPM number with "bpm" hanging off its right: the number alone is
/// centred (main screen at 172px, song editor at 84px).
class BpmReadout extends StatelessWidget {
  const BpmReadout({
    super.key,
    required this.bpm,
    required this.fontSize,
    required this.unitSize,
    this.numberKey,
  });

  final int bpm;
  final double fontSize;
  final double unitSize;
  final Key? numberKey;

  @override
  Widget build(BuildContext context) {
    final unit = TextStyle(fontSize: unitSize, color: context.colors.muted);
    final gap = unitSize * 0.45;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        // An invisible twin of "bpm" balances the visible one, so the
        // number alone is centred and "bpm" hangs off its right side.
        ExcludeSemantics(
          child: Visibility.maintain(
            visible: false,
            child: Text('bpm', style: unit),
          ),
        ),
        SizedBox(width: gap),
        Text(
          '$bpm',
          key: numberKey,
          style: TextStyle(
            fontFamily: MetraFonts.condensed,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 0.85,
            // Fixed-width digits: the readout doesn't shift.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(width: gap),
        Text('bpm', style: unit),
      ],
    );
  }
}

/// −5 −1 +1 +5, filled; holding repeats with acceleration (ui-spec.md).
/// Each step ticks; [onStep] gets the delta.
class TempoSteps extends StatelessWidget {
  const TempoSteps({
    super.key,
    required this.bpm,
    required this.onStep,
    required this.height,
    this.fontSize = 28,
  });

  final int bpm;
  final ValueChanged<int> onStep;
  final double height;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    Widget step(String label, int delta) {
      final enabled = delta < 0
          ? bpm > MetronomeController.minBpm
          : bpm < MetronomeController.maxBpm;
      return Expanded(
        child: SizedBox(
          height: height,
          child: RepeatButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.surface,
              foregroundColor: context.colors.text,
              padding: EdgeInsets.zero,
            ),
            onPressed: enabled
                ? () {
                    Haptics.tick();
                    onStep(delta);
                  }
                : null,
            // Shrinks instead of wrapping on narrow phones.
            child: FittedBox(
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        step('−5', -5),
        const SizedBox(width: 8),
        step('−1', -1),
        const SizedBox(width: 8),
        step('+1', 1),
        const SizedBox(width: 8),
        step('+5', 5),
      ],
    );
  }
}
