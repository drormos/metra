import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'haptics.dart';
import 'meter_control.dart';
import 'motion.dart';
import 'theme.dart';

/// The app's one −/+ stepper (ui-spec.md "Editing the values", "Song
/// parts" fixes): a label, then − / the value / +. − and + step on a tap
/// and repeat while held, accelerating (a medium bump at a limit). The
/// value sits in an outlined field: tapping it opens the number keyboard
/// with the value selected; Done or tapping outside hands the text to
/// [onTyped], which snaps it into range. No drag-to-scrub. Without
/// [showLabel] the label only names it for TalkBack; [fieldWidth] null
/// stretches the field between the buttons.
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
    this.showLabel = true,
    this.fieldWidth = 92,
    this.buttonSize = 48,
    this.fontSize = 24,
    this.leading,
  });

  /// Before − with a small gap (the parts page's ✕ on "Ends at").
  final Widget? leading;

  final String label;
  final bool showLabel;
  final double? fieldWidth;
  final double buttonSize;
  final double fontSize;

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
    final field = SizedBox(
      width: widget.fieldWidth,
      height: widget.buttonSize,
      // The 40px outline is drawn inside; the field takes the whole
      // box, so it's a full-size touch target.
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
              style: TextStyle(
                fontFamily: MetraFonts.condensed,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w700,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration.collapsed(hintText: null),
              onSubmitted: (_) => _focus.unfocus(),
              onTapOutside: (_) => _focus.unfocus(),
            ),
          ),
        ),
      ),
    );
    return Row(
      children: [
        if (widget.showLabel)
          // A new label swaps in (snap in, soft brighten).
          Expanded(
            child: BrightenSwap(
              value: label,
              child: Text(label, style: const TextStyle(fontSize: 15)),
            ),
          ),
        if (widget.leading case final leading?) ...[
          leading,
          const SizedBox(width: 10),
        ],
        Semantics(
          label: 'Less $label',
          button: true,
          excludeSemantics: true,
          child: StepButton(
            Icons.remove,
            key: ValueStepper.minusKey(label),
            size: widget.buttonSize,
            onPressed: _step(widget.onMinus),
          ),
        ),
        const SizedBox(width: 6),
        if (widget.fieldWidth == null) Expanded(child: field) else field,
        const SizedBox(width: 6),
        Semantics(
          label: 'More $label',
          button: true,
          excludeSemantics: true,
          child: StepButton(
            Icons.add,
            key: ValueStepper.plusKey(label),
            size: widget.buttonSize,
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
