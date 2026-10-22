import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'meter_control.dart';
import 'theme.dart';

/// One value in the "When I press Start" sheet (ui-spec.md "Editing the
/// values"): a label, then − / the value / +. − and + step and repeat
/// while held, accelerating (a medium bump at a limit). The value sits in
/// an outlined field: tapping it opens the number keyboard with the value
/// selected; Done or tapping outside hands the text to [onTyped], which
/// snaps it into range. No drag-to-scrub.
class ValueStepper extends StatefulWidget {
  const ValueStepper({
    super.key,
    required this.label,
    required this.display,
    required this.editText,
    required this.onMinus,
    required this.onPlus,
    required this.onTyped,
    this.time = false,
    this.signed = false,
  });

  final String label;

  /// Shown at rest ("+5", "8 bars", "No limit", "10:00").
  final String display;

  /// What the field holds while typing ("5", "8", "", "1000").
  final String editText;

  /// Null disables (at the end of the range).
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final ValueChanged<String> onTyped;

  /// mm:ss, filled from the right as digits are typed.
  final bool time;

  /// The keyboard offers a minus sign.
  final bool signed;

  static Key fieldKey(String label) => ValueKey('field-$label');
  static Key minusKey(String label) => ValueKey('minus-$label');
  static Key plusKey(String label) => ValueKey('plus-$label');

  @override
  State<ValueStepper> createState() => _ValueStepperState();
}

class _ValueStepperState extends State<ValueStepper> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.text = widget.display;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(ValueStepper old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus) _text.text = widget.display;
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      final text = widget.time
          ? _MicrowaveTime.format(widget.editText)
          : widget.editText;
      _text.value = TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      );
    } else {
      widget.onTyped(_text.text);
      // The parent's new value comes back through didUpdateWidget; until
      // then (or if nothing changed) show the old one.
      setState(() => _text.text = widget.display);
    }
  }

  VoidCallback? _step(VoidCallback? change) => change == null
      ? null
      : () {
          Haptics.tick();
          change();
        };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = widget.label;
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        Semantics(
          label: 'Less $label',
          button: true,
          excludeSemantics: true,
          child: StepButton(
            '−',
            key: ValueStepper.minusKey(label),
            size: 48,
            fontSize: 24,
            onPressed: _step(widget.onMinus),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 92,
          height: 48,
          // The 40px outline is drawn inside; the field takes the whole
          // 48px box, so it's a full-size touch target.
          child: DecoratedBox(
            decoration: _OutlineInside(colors.controlOutline),
            child: Center(
              child: Semantics(
                label: label,
                textField: true,
                child: TextField(
                  key: ValueStepper.fieldKey(label),
                  controller: _text,
                  focusNode: _focus,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.numberWithOptions(
                    signed: widget.signed,
                  ),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    if (widget.time)
                      _MicrowaveTime()
                    else
                      FilteringTextInputFormatter.allow(
                        RegExp(widget.signed ? r'[-−0-9]' : r'[0-9]'),
                      ),
                  ],
                  // Fills the box; the number is display text already.
                  expands: true,
                  maxLines: null,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontFamily: MetraFonts.condensed,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                  decoration: const InputDecoration.collapsed(hintText: null),
                  onSubmitted: (_) => _focus.unfocus(),
                  onTapOutside: (_) => _focus.unfocus(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Semantics(
          label: 'More $label',
          button: true,
          excludeSemantics: true,
          child: StepButton(
            '+',
            key: ValueStepper.plusKey(label),
            size: 48,
            fontSize: 24,
            onPressed: _step(widget.onPlus),
          ),
        ),
      ],
    );
  }
}

/// mm:ss filled from the right like a microwave: typing 1, 2, 3, 0 shows
/// 0:01, 0:12, 1:23, 12:30 (at most four digits).
class _MicrowaveTime extends TextInputFormatter {
  static String format(String text) {
    var digits = text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    if (digits.length > 4) digits = digits.substring(digits.length - 4);
    final padded = digits.padLeft(3, '0');
    return '${int.parse(padded.substring(0, padded.length - 2))}:'
        '${padded.substring(padded.length - 2)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = format(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// A 2px rounded outline, 40px tall, centred in a taller box.
class _OutlineInside extends Decoration {
  const _OutlineInside(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _OutlinePainter(color);
}

class _OutlinePainter extends BoxPainter {
  _OutlinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = Rect.fromCenter(
      center: offset + size.center(Offset.zero),
      width: size.width - 2,
      height: 38,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }
}
