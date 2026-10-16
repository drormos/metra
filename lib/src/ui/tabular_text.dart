import 'dart:math';

import 'package:flutter/material.dart';

/// Text whose digits each sit in a fixed slot, as wide as the widest digit
/// and centred in it, so a changing number never changes width or shakes
/// (ui-spec.md "No jitter"). Saira Extra Condensed has no tabular figures
/// (`FontFeature.tabularFigures()` changes nothing), so the slots are laid
/// out here. Other characters keep their own width.
class TabularText extends StatelessWidget {
  const TabularText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  static final _slots = <TextStyle, double>{};

  /// The widest digit in [style] (unscaled), measured once per style.
  static double slotWidth(TextStyle style) => _slots.putIfAbsent(style, () {
    var widest = 0.0;
    for (var d = 0; d < 10; d++) {
      final painter = TextPainter(
        text: TextSpan(text: '$d', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  });

  static bool isDigit(String c) => '0123456789'.contains(c);

  @override
  Widget build(BuildContext context) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    final slot = MediaQuery.textScalerOf(context).scale(slotWidth(resolved));
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          for (final c in text.split(''))
            isDigit(c)
                ? SizedBox(
                    width: slot,
                    child: Text(
                      c,
                      style: resolved,
                      textAlign: TextAlign.center,
                    ),
                  )
                : Text(c, style: resolved),
        ],
      ),
    );
  }
}
