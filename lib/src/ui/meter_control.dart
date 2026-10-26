import 'package:flutter/material.dart';

import 'repeat_button.dart';
import 'segmented.dart';
import 'theme.dart';
import 'value_stepper.dart';

/// A filled square −/+ (a vector icon) that steps on a tap and repeats
/// while held, accelerating like the tempo buttons: the buttons of
/// [ValueStepper], the app's one stepper.
class StepButton extends StatelessWidget {
  const StepButton(
    this.icon, {
    super.key,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final double size;

  /// Null disables it (at the end of the range).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: RepeatButton(
      style: FilledButton.styleFrom(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text,
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      child: Icon(icon, size: size * 0.5),
    ),
  );
}

/// Beats −/+ (1–[maxBeats], the app's stepper: tap the number to type),
/// "/", and a 4 | 8 segmented control: the Rhythm panel's Custom row.
/// [onChanged] gets every step.
class MeterControl extends StatelessWidget {
  const MeterControl({
    super.key,
    required this.beats,
    required this.unit,
    required this.onChanged,
    this.size = 48,
  });

  static const maxBeats = 16;

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
        ValueStepper(
          label: 'Beats',
          showLabel: false,
          display: '$beats',
          editText: '$beats',
          fieldWidth: size * 1.1,
          buttonSize: size,
          fontSize: size * 0.6,
          onMinus: beats > 1 ? () => onChanged(beats - 1, unit) : null,
          onPlus: beats < maxBeats ? () => onChanged(beats + 1, unit) : null,
          onTyped: (text) {
            final v = int.tryParse(text);
            if (v != null) onChanged(v.clamp(1, maxBeats), unit);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '/',
            // Sized with the number, not the system text size.
            textScaler: TextScaler.noScaling,
            style: big.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.muted,
            ),
          ),
        ),
        Expanded(
          child: Segmented(
            options: const {4: '4', 8: '8'},
            selected: unit,
            onSelected: (option) => onChanged(beats, option),
            height: size - 4,
            style: const TextStyle(
              fontFamily: MetraFonts.condensed,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
