import 'package:flutter/material.dart';

import 'tabular_text.dart';
import 'theme.dart';

/// A song's position in a set list ("1" to "99"): one line in a column as
/// wide as "99" at the current text size, right-aligned with tabular
/// figures, so every position lines up and "10" never breaks in two
/// (ui-spec.md "Set ⌄" › "Rows"). The current song's red play icon sits in
/// the same column.
class PositionNumber extends StatelessWidget {
  const PositionNumber({
    super.key,
    required this.position,
    this.current = false,
  });

  /// From 1.
  final int position;
  final bool current;

  static const _fontSize = 13.0;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: _fontSize,
        color: context.colors.muted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    final scale = MediaQuery.textScalerOf(context).scale(_fontSize) / _fontSize;
    // Two of the widest digit, plus a hair against rounding.
    final width = TabularText.slotWidth(style) * 2 * scale + 1;
    return SizedBox(
      width: width < 16 ? 16 : width,
      child: current
          ? const Align(
              alignment: Alignment.centerRight,
              child: PlayMarker(current: true),
            )
          : Text(
              '$position',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: style,
            ),
    );
  }
}

/// The play triangle at the start of a song row (the lists):
/// outlined and muted, filled in the accent for the current song. Shows
/// that tapping the row plays it.
class PlayMarker extends StatelessWidget {
  const PlayMarker({super.key, required this.current});

  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: current ? 'Playing' : null,
      child: CustomPaint(
        size: const Size.square(16),
        painter: _Triangle(
          current ? colors.accent : colors.muted,
          filled: current,
        ),
      ),
    );
  }
}

class _Triangle extends CustomPainter {
  _Triangle(this.color, {required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    // song-library.reference.html: points 3,2 14,8 3,14 in a 16px box.
    canvas.scale(size.width / 16);
    canvas.drawPath(
      Path()
        ..moveTo(3, 2)
        ..lineTo(14, 8)
        ..lineTo(3, 14)
        ..close(),
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Triangle old) =>
      old.color != color || old.filled != filled;
}

/// The marking slot of a row while removing songs or deleting sets
/// (setlist-select.reference.html): an empty circle, or a filled accent
/// circle with a check.
class MarkCircle extends StatelessWidget {
  const MarkCircle({super.key, required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      checked: checked,
      child: CustomPaint(
        size: const Size.square(20),
        painter: _Circle(
          checked ? colors.accent : colors.muted,
          check: checked ? colors.background : null,
        ),
      ),
    );
  }
}

class _Circle extends CustomPainter {
  _Circle(this.color, {this.check});

  final Color color;

  /// The check's color; null draws an empty ring.
  final Color? check;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final check = this.check;
    if (check == null) {
      canvas.drawCircle(
        const Offset(10, 10),
        8,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    canvas
      ..drawCircle(const Offset(10, 10), 9, Paint()..color = color)
      ..drawPath(
        Path()
          ..moveTo(5.5, 10.5)
          ..lineTo(8.5, 13.5)
          ..lineTo(14.5, 7),
        Paint()
          ..color = check
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
  }

  @override
  bool shouldRepaint(_Circle old) => old.color != color || old.check != check;
}
