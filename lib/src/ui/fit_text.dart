import 'dart:math';

import 'package:flutter/material.dart';

/// One line that never wraps: starts at [style]'s font size and shrinks to
/// fit, down to [minFontSize]; only then does it end in an ellipsis
/// (ui-spec.md "Top row", "Mode tabs and context row").
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    required this.style,
    required this.minFontSize,
    this.textAlign,
    this.textKey,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final TextAlign? textAlign;

  /// The inner [Text]'s key (tests read its data).
  final Key? textKey;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final resolved = DefaultTextStyle.of(context).style.merge(style);
      final painter = TextPainter(
        text: TextSpan(text: text, style: resolved),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final full = resolved.fontSize!;
      // Width grows in step with the font size, so scale it down to fit.
      final size = painter.width <= box.maxWidth
          ? full
          : max(minFontSize, full * box.maxWidth / painter.width);
      painter.dispose();
      return Text(
        text,
        key: textKey,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: resolved.copyWith(fontSize: size.floorToDouble()),
      );
    },
  );
}
