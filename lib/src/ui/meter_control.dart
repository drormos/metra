import 'package:flutter/material.dart';

import 'repeat_button.dart';
import 'theme.dart';

/// A filled square −/+ that repeats while held (song editor, time
/// signature sheet).
class StepButton extends StatelessWidget {
  const StepButton(
    this.label, {
    super.key,
    required this.size,
    required this.fontSize,
    required this.onPressed,
    this.accelerate = true,
  });

  final String label;
  final double size;
  final double fontSize;

  /// Null disables it (at the end of the range).
  final VoidCallback? onPressed;
  final bool accelerate;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: RepeatButton(
      accelerate: accelerate,
      style: FilledButton.styleFrom(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text,
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: MetraFonts.condensed,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Beats −/+ (1–[maxBeats], held: ~6 per second, no acceleration), "/",
/// and a 4 | 8 segmented control. Shared by the song editor and the time
/// signature sheet; [onChanged] gets every step.
class MeterControl extends StatelessWidget {
  const MeterControl({
    super.key,
    required this.beats,
    required this.unit,
    required this.onChanged,
    this.size = 48,
  });

  static const maxBeats = 16;
  static const beatsKey = Key('meter-beats');

  final int beats;
  final int unit;
  final void Function(int beats, int unit) onChanged;

  /// The −/+ size; the number and the segmented control scale with it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final big = TextStyle(
      fontFamily: MetraFonts.condensed,
      fontSize: size * 0.82,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        StepButton(
          '−',
          size: size,
          fontSize: size * 0.55,
          accelerate: false,
          onPressed: beats > 1 ? () => onChanged(beats - 1, unit) : null,
        ),
        SizedBox(
          width: size * 0.85,
          child: Text(
            '$beats',
            key: beatsKey,
            textAlign: TextAlign.center,
            style: big,
          ),
        ),
        StepButton(
          '+',
          size: size,
          fontSize: size * 0.55,
          accelerate: false,
          onPressed: beats < maxBeats ? () => onChanged(beats + 1, unit) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '/',
            style: big.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.muted,
            ),
          ),
        ),
        Expanded(child: _units(colors)),
      ],
    );
  }

  /// 4 | 8 in one 2px frame; the selected one filled with the text color.
  Widget _units(MetraColors colors) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: colors.border, width: 2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Row(
        children: [
          for (final option in const [4, 8])
            Expanded(
              child: Semantics(
                button: true,
                selected: unit == option,
                child: Material(
                  color: unit == option ? colors.text : colors.background,
                  child: InkWell(
                    key: ValueKey('meter-unit-$option'),
                    onTap: () => onChanged(beats, option),
                    child: SizedBox(
                      height: size - 4,
                      child: Center(
                        child: Text(
                          '$option',
                          style: TextStyle(
                            fontFamily: MetraFonts.condensed,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: unit == option
                                ? colors.background
                                : colors.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
