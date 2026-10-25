import 'package:flutter/material.dart';

import 'theme.dart';

/// Options side by side in one 2px frame; the selected one is filled with
/// the text color (ui-spec.md: 4 | 8, the theme setting). With [icon],
/// each option draws that instead of its label (still its spoken name).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.height = 48,
    this.style,
    this.icon,
  });

  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;
  final TextStyle? style;
  final Widget Function(T value)? icon;

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
                  label: icon == null ? null : label,
                  child: Material(
                    color: value == selected ? colors.text : colors.background,
                    child: InkWell(
                      key: ValueKey('segment-$value'),
                      onTap: () => onSelected(value),
                      child: SizedBox(
                        height: height,
                        child: Center(
                          child: icon != null
                              ? IconTheme.merge(
                                  data: IconThemeData(
                                    color: value == selected
                                        ? colors.background
                                        : colors.text,
                                  ),
                                  child: icon!(value),
                                )
                              // Long labels with large text shrink to fit
                              // the fixed height instead of overflowing.
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      label,
                                      style: (style ?? const TextStyle())
                                          .copyWith(
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
                ),
              ),
          ],
        ),
      ),
    );
  }
}
