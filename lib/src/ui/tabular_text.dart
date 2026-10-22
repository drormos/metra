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
    this.roll = Duration.zero,
    this.rollUp = true,
  });

  final String text;
  final TextStyle? style;

  /// A digit that changes rolls in its own slot over this long
  /// ([MetraMotion.roll]), upward when [rollUp] (the number rose); the
  /// others don't move. Zero: instant.
  final Duration roll;
  final bool rollUp;

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
                    child: _RollingDigit(
                      c,
                      style: resolved,
                      duration: roll,
                      up: rollUp,
                    ),
                  )
                : Text(c, style: resolved),
        ],
      ),
    );
  }
}

/// One digit in its slot (ui-spec.md "Motion", rolling digits): when it
/// changes, the old one slides ~12% of its height in the direction of
/// change while fading out and the new one slides in from the other side
/// while fading in, clipped to the slot's width so nothing spills sideways.
class _RollingDigit extends StatefulWidget {
  const _RollingDigit(
    this.digit, {
    required this.style,
    required this.duration,
    required this.up,
  });

  final String digit;
  final TextStyle style;
  final Duration duration;
  final bool up;

  static const travel = 0.12;

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  late final _roll = AnimationController(vsync: this, value: 1);
  String? _old;
  bool _up = true;

  @override
  void didUpdateWidget(_RollingDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    if (widget.duration == Duration.zero) {
      _roll.value = 1;
      _old = null;
      return;
    }
    _old = old.digit;
    _up = widget.up;
    _roll
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  Text _text(String c) =>
      Text(c, style: widget.style, textAlign: TextAlign.center);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _roll,
    builder: (context, _) {
      final old = _old;
      if (old == null || _roll.value >= 1) return _text(widget.digit);
      final p = MetraMotion.rollCurve.transform(_roll.value);
      // Up: the old leaves upward and the new comes from below.
      final away = _up ? -1.0 : 1.0;
      const t = _RollingDigit.travel;
      return ClipRect(
        clipper: const _SlotClip(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            FractionalTranslation(
              translation: Offset(0, away * t * p),
              child: Opacity(opacity: 1 - p, child: _text(old)),
            ),
            FractionalTranslation(
              translation: Offset(0, -away * t * (1 - p)),
              child: Opacity(opacity: p, child: _text(widget.digit)),
            ),
          ],
        ),
      );
    },
  );
}

/// The slot's width, with room above and below for the glyphs (the line
/// is shorter than they are) and the short roll.
class _SlotClip extends CustomClipper<Rect> {
  const _SlotClip();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -size.height * 0.4, size.width, size.height * 1.4);

  @override
  bool shouldReclip(_SlotClip old) => false;
}
