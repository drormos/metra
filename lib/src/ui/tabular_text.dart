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
    this.dissolve = Duration.zero,
  });

  final String text;
  final TextStyle? style;

  /// A digit that changes dissolves in its own slot over this long
  /// ([MetraMotion.dissolve]); the others stay still at full opacity.
  /// Zero: instant.
  final Duration dissolve;

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
                    child: _DissolveDigit(
                      c,
                      style: resolved,
                      duration: dissolve,
                    ),
                  )
                : Text(c, style: resolved),
        ],
      ),
    );
  }
}

/// One digit in its slot (ui-spec.md "Motion", steady dissolve): when it
/// changes, old and new are drawn in the same place, the old going 1 → 0
/// while the new goes 0 → 1 on the same linear curve, so together they
/// are always fully bright.
class _DissolveDigit extends StatefulWidget {
  const _DissolveDigit(
    this.digit, {
    required this.style,
    required this.duration,
  });

  final String digit;
  final TextStyle style;
  final Duration duration;

  @override
  State<_DissolveDigit> createState() => _DissolveDigitState();
}

class _DissolveDigitState extends State<_DissolveDigit>
    with SingleTickerProviderStateMixin {
  late final _dissolve = AnimationController(vsync: this, value: 1);
  String? _old;

  @override
  void didUpdateWidget(_DissolveDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    if (widget.duration == Duration.zero) {
      _dissolve.value = 1;
      _old = null;
      return;
    }
    _old = old.digit;
    _dissolve
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _dissolve.dispose();
    super.dispose();
  }

  Text _text(String c) =>
      Text(c, style: widget.style, textAlign: TextAlign.center);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _dissolve,
    builder: (context, _) {
      final old = _old;
      final t = _dissolve.value;
      if (old == null || t >= 1) return _text(widget.digit);
      return Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: 1 - t, child: _text(old)),
          Opacity(opacity: t, child: _text(widget.digit)),
        ],
      );
    },
  );
}
