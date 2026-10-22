import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Text whose digits each sit in a fixed slot, as wide as the widest digit
/// and centred in it, so a changing number never changes width or shakes
/// (ui-spec.md "No jitter"). Saira Extra Condensed has no tabular figures
/// (`FontFeature.tabularFigures()` changes nothing), so the slots are laid
/// out here. Other characters keep their own width.
class TabularText extends StatelessWidget {
  const TabularText(
    this.text, {
    super.key,
    this.style,
    this.fade = Duration.zero,
  });

  final String text;
  final TextStyle? style;

  /// A digit that changes cross-fades in its slot over this long
  /// ([MetraMotion.swap]); the others stay as they are.
  final Duration fade;

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

  /// Tests that load a real font after measuring with the test font.
  @visibleForTesting
  static void clearCache() => _slots.clear();

  static bool isDigit(String c) => '0123456789'.contains(c);

  /// Instant ([fade] zero): just the digit, never a lingering old one.
  Widget _digit(String c, TextStyle style) {
    final text = Text(
      c,
      key: ValueKey(c),
      style: style,
      textAlign: TextAlign.center,
    );
    if (fade == Duration.zero) return text;
    return AnimatedSwitcher(
      duration: fade,
      switchInCurve: MetraMotion.swapCurve,
      switchOutCurve: MetraMotion.swapCurve,
      child: text,
    );
  }

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
          for (final (i, c) in text.split('').indexed)
            isDigit(c)
                ? SizedBox(
                    // By place from the right, so 99 → 100 keeps the units.
                    key: ValueKey(text.length - i),
                    width: slot,
                    child: _digit(c, resolved),
                  )
                : Text(c, style: resolved),
        ],
      ),
    );
  }
}
