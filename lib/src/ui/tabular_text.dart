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
    this.brighten = Duration.zero,
  });

  final String text;
  final TextStyle? style;

  /// A digit that changes snaps in and brightens to full over this long
  /// ([MetraMotion.brighten]); the others are untouched. Zero: instant at
  /// full opacity.
  final Duration brighten;

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
                    child: _BrightenDigit(
                      c,
                      style: resolved,
                      duration: brighten,
                    ),
                  )
                : Text(c, style: resolved),
        ],
      ),
    );
  }
}

/// One digit in its slot (ui-spec.md "BPM: snap in, soft brighten"): when
/// it changes, the old one is gone at once and the new one appears in the
/// same frame at [MetraMotion.brightenFrom], rising to full. Never two
/// shapes, never an empty slot, no movement.
class _BrightenDigit extends StatefulWidget {
  const _BrightenDigit(
    this.digit, {
    required this.style,
    required this.duration,
  });

  final String digit;
  final TextStyle style;
  final Duration duration;

  @override
  State<_BrightenDigit> createState() => _BrightenDigitState();
}

class _BrightenDigitState extends State<_BrightenDigit>
    with SingleTickerProviderStateMixin {
  late final _brighten = AnimationController(vsync: this, value: 1);

  @override
  void didUpdateWidget(_BrightenDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    if (widget.duration == Duration.zero) {
      _brighten.value = 1;
      return;
    }
    _brighten
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _brighten.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      widget.digit,
      style: widget.style,
      textAlign: TextAlign.center,
    );
    return AnimatedBuilder(
      animation: _brighten,
      child: text,
      builder: (context, child) {
        final t = _brighten.value;
        if (t >= 1) return child!;
        const from = MetraMotion.brightenFrom;
        return Opacity(
          opacity: from + (1 - from) * MetraMotion.brightenCurve.transform(t),
          child: child,
        );
      },
    );
  }
}
