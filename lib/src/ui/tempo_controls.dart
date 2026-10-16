import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/metronome_controller.dart';
import 'haptics.dart';
import 'repeat_button.dart';
import 'tabular_text.dart';
import 'theme.dart';

/// The BPM number with "bpm" hanging off its right: the number alone is
/// centred (main screen 172–240px, song editor 84px).
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

  static TextStyle numberStyle(double fontSize) => TextStyle(
    fontFamily: MetraFonts.condensed,
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    height: 0.85,
  );

  static TextStyle _unitStyle(double unitSize) =>
      TextStyle(fontFamily: MetraFonts.body, fontSize: unitSize);

  /// The largest font size at which three digits, with "bpm" and its
  /// balancing twin, fit [area], up to [max]. It depends on the area only,
  /// never on the value: 99 and 100 share it, two digits are just
  /// narrower.
  /// Measured with [context]'s default text style, as the widgets are.
  static double fit(
    BuildContext context,
    Size area, {
    double max = 240,
    double unitSize = 18,
  }) {
    final base = DefaultTextStyle.of(context).style;
    final unit = TextPainter(
      text: TextSpan(text: 'bpm', style: base.merge(_unitStyle(unitSize))),
      textDirection: TextDirection.ltr,
    )..layout();
    final sides = 2 * (unit.width + unitSize * 0.45);
    unit.dispose();
    // A digit slot is proportional to the font size.
    final slotPerPx = TabularText.slotWidth(base.merge(numberStyle(100))) / 100;
    // A pixel spare and a whole size keep layout rounding from overflowing.
    final byWidth = (area.width - sides - 1) / (3 * slotPerPx);
    final byHeight = area.height / 0.85;
    return math.max(
      1,
      math.min(max, math.min(byWidth, byHeight)).floorToDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unit = _unitStyle(unitSize).copyWith(color: context.colors.muted);
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
        // Fixed digit slots: the readout never changes width or shakes.
        TabularText('$bpm', key: numberKey, style: numberStyle(fontSize)),
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
