import 'package:flutter/material.dart';

import 'theme.dart';

/// Options side by side in one 2px frame; the selected one is filled with
/// the text color (ui-spec.md: 4 | 8, the theme setting).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.height = 44,
    this.style,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Row(
          children: [
            for (final MapEntry(key: value, value: label) in options.entries)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == selected,
                  child: Material(
                    color: value == selected ? colors.text : colors.background,
                    child: InkWell(
                      key: ValueKey('segment-$value'),
                      onTap: () => onSelected(value),
                      child: SizedBox(
                        height: height,
                        child: Center(
                          child: Text(
                            label,
                            style: (style ?? const TextStyle()).copyWith(
                              color: value == selected
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
}
