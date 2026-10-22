import 'dart:math';

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

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

  /// The size [text] in [resolved] fits [maxWidth] at: its own, or
  /// smaller down to [minFontSize] (whole sizes).
  static double fitSize(
    BuildContext context,
    String text,
    TextStyle resolved,
    double minFontSize,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: resolved),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final full = resolved.fontSize!;
    // Width grows in step with the font size, so scale it down to fit.
    final size = painter.width <= maxWidth
        ? full
        : max(minFontSize, full * maxWidth / painter.width);
    painter.dispose();
    return size.floorToDouble();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final resolved = DefaultTextStyle.of(context).style.merge(style);
      final size = fitSize(context, text, resolved, minFontSize, box.maxWidth);
      return Text(
        text,
        key: textKey,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: resolved.copyWith(fontSize: size),
      );
    },
  );
}

/// Text that changes in place (ui-spec.md "Text that changes in place"):
/// names and tempos. On a real change only the characters that changed are
/// touched: the old text is gone at once and the changed part snaps in at
/// ~60%, brightening to full ([BrightenGate]); the unchanged start (or end,
/// for end-aligned text) stays at full opacity. Sized to fit first, down to
/// [minFontSize]: a new size counts as all changed. With [baseline], it
/// sits on that baseline (from the top), so sizes never move it.
class BrightenText extends StatefulWidget {
  const BrightenText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize,
    this.baseline,
    this.textAlign,
    this.textKey,
  });

  final String text;
  final TextStyle style;

  /// Null: never shrinks.
  final double? minFontSize;
  final double? baseline;
  final TextAlign? textAlign;

  /// The [Text]'s key (tests read it).
  final Key? textKey;

  @override
  State<BrightenText> createState() => _BrightenTextState();
}

class _BrightenTextState extends State<BrightenText>
    with SingleTickerProviderStateMixin {
  late final _brighten = AnimationController(vsync: this, value: 1);
  final _gate = BrightenGate();
  String? _old;
  double? _oldSize;
  double? _size; // as last laid out

  @override
  void didUpdateWidget(BrightenText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    final duration = _gate.next(context);
    if (duration == Duration.zero) {
      _brighten.value = 1;
      return;
    }
    _old = old.text;
    _oldSize = _size;
    _brighten
      ..duration = duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _brighten.dispose();
    super.dispose();
  }

  bool get _endAligned =>
      widget.textAlign == TextAlign.right || widget.textAlign == TextAlign.end;

  /// How many characters at the anchored side are the same.
  int _same(String old, String text) {
    var n = 0;
    final max = old.length < text.length ? old.length : text.length;
    while (n < max &&
        (_endAligned
            ? old.codeUnitAt(old.length - 1 - n) ==
                  text.codeUnitAt(text.length - 1 - n)
            : old.codeUnitAt(n) == text.codeUnitAt(n))) {
      n++;
    }
    return n;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final resolved = DefaultTextStyle.of(context).style.merge(widget.style);
      final min = widget.minFontSize;
      final size = _size = min == null
          ? resolved.fontSize!
          : FitText.fitSize(context, widget.text, resolved, min, box.maxWidth);
      final style = resolved.copyWith(fontSize: size);
      return AnimatedBuilder(
        animation: _brighten,
        builder: (context, _) {
          final text = widget.text;
          final t = _brighten.value;
          final old = _old;
          Widget line = Text(
            text,
            key: widget.textKey,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
            style: style,
          );
          if (t < 1 && old != null) {
            final same = _oldSize == size ? _same(old, text) : 0;
            final color = style.color ?? context.colors.text;
            final fresh = TextStyle(
              color: color.withValues(alpha: color.a * BrightenGate.opacity(t)),
            );
            final span = _endAligned
                ? TextSpan(
                    children: [
                      TextSpan(
                        text: text.substring(0, text.length - same),
                        style: fresh,
                      ),
                      TextSpan(text: text.substring(text.length - same)),
                    ],
                  )
                : TextSpan(
                    children: [
                      TextSpan(text: text.substring(0, same)),
                      TextSpan(text: text.substring(same), style: fresh),
                    ],
                  );
            line = Semantics(
              label: text,
              excludeSemantics: true,
              child: Text.rich(
                span,
                key: widget.textKey,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.textAlign,
                style: style,
              ),
            );
          }
          final baseline = widget.baseline;
          return baseline == null
              ? line
              : Baseline(
                  baseline: baseline,
                  baselineType: TextBaseline.alphabetic,
                  child: line,
                );
        },
      );
    },
  );
}
