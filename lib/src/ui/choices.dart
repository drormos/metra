import 'package:flutter/material.dart';

import 'haptics.dart';
import 'theme.dart';

/// Quiet choices laid out like a stepper row (ui-spec.md "Choices inside
/// a part"): a label on the left, 36px pill chips sized to their text on
/// the right. Selected: the tick-resting grey (#2A2A2A) with a 2px text
/// color border and semibold text; the others clear with a 2px border and
/// muted text. Each chip is a 48dp touch target.
class Choices<T> extends StatelessWidget {
  const Choices({
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
    final chips = Wrap(
      spacing: 8,
      children: [
        for (final MapEntry(key: value, value: text) in options.entries)
          _chip(colors, value, text, selected: value == selected),
      ],
    );
    // With large text the chips go under the label rather than off screen.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        chips,
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
          // As wide as its text: a full-width chip would take a line.
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: ShapeDecoration(
                color: selected ? colors.tickResting : null,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: selected ? colors.text : colors.border,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                widthFactor: 1,
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
      ),
    );
  }
}
