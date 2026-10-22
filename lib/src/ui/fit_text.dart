import 'dart:math';

import 'package:flutter/material.dart';

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

/// A name that changes in place (ui-spec.md "Motion", steady dissolve):
/// the title and set name. On a real change of [text], old and new are
/// drawn in the same place, the old going 1 → 0 while the new goes 0 → 1
/// on one linear curve, so nothing dims. At the same size, the characters
/// they share at the start stay still at full opacity and only the rest
/// dissolves; at a different size (sized to fit first, down to
/// [minFontSize]) the whole name dissolves. Both sit on [baseline] (from
/// the top) at the left edge, so nothing moves.
class DissolveText extends StatefulWidget {
  const DissolveText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize,
    this.baseline,
    this.textKey,
  });

  final String text;
  final TextStyle style;

  /// Null: never shrinks.
  final double? minFontSize;
  final double? baseline;

  /// The current [Text]'s key (tests read it).
  final Key? textKey;

  @override
  State<DissolveText> createState() => _DissolveTextState();
}

class _DissolveTextState extends State<DissolveText>
    with SingleTickerProviderStateMixin {
  late final _dissolve = AnimationController(
    vsync: this,
    duration: MetraMotion.dissolve,
    value: 1,
  );
  String? _old;
  double? _oldSize;
  double? _size; // as last laid out

  @override
  void didUpdateWidget(DissolveText old) {
    super.didUpdateWidget(old);
    if (old.text == widget.text) return;
    if (MetraMotion.reduced(context)) {
      _dissolve.value = 1;
      _old = null;
      return;
    }
    _old = old.text;
    _oldSize = _size;
    _dissolve.forward(from: 0);
  }

  @override
  void dispose() {
    _dissolve.dispose();
    super.dispose();
  }

  Widget _layer(Widget text) {
    final baseline = widget.baseline;
    return baseline == null
        ? text
        : Baseline(
            baseline: baseline,
            baselineType: TextBaseline.alphabetic,
            child: text,
          );
  }

  Text _line(InlineSpan span, TextStyle style, {Key? key}) => Text.rich(
    span,
    key: key,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: style,
  );

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
        animation: _dissolve,
        builder: (context, _) {
          final old = _old;
          final t = _dissolve.value;
          final current = Text(
            widget.text,
            key: widget.textKey,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
          if (old == null || t >= 1) return _layer(current);
          final oldSize = _oldSize ?? size;
          if (oldSize != size) {
            return Stack(
              children: [
                _layer(
                  ExcludeSemantics(
                    child: Opacity(
                      opacity: 1 - t,
                      child: _line(
                        TextSpan(text: old),
                        resolved.copyWith(fontSize: oldSize),
                      ),
                    ),
                  ),
                ),
                _layer(Opacity(opacity: t, child: current)),
              ],
            );
          }
          // Same size: the shared start is drawn once, at full opacity.
          var shared = 0;
          final text = widget.text;
          while (shared < old.length &&
              shared < text.length &&
              old.codeUnitAt(shared) == text.codeUnitAt(shared)) {
            shared++;
          }
          final color = style.color ?? context.colors.text;
          Color alpha(double a) => color.withValues(alpha: color.a * a);
          return Stack(
            children: [
              _layer(
                ExcludeSemantics(
                  child: _line(
                    TextSpan(
                      children: [
                        TextSpan(text: old.substring(0, shared)),
                        TextSpan(
                          text: old.substring(shared),
                          style: TextStyle(color: alpha(1 - t)),
                        ),
                      ],
                    ),
                    style,
                  ),
                ),
              ),
              _layer(
                Semantics(
                  label: text,
                  excludeSemantics: true,
                  child: _line(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: text.substring(0, shared),
                          style: TextStyle(color: alpha(0)),
                        ),
                        TextSpan(
                          text: text.substring(shared),
                          style: TextStyle(color: alpha(t)),
                        ),
                      ],
                    ),
                    style,
                    key: widget.textKey,
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
