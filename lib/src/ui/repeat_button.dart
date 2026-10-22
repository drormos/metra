import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';
import 'theme.dart';

/// A filled button that fires once on tap and repeats while held
/// (ui-spec.md "Hold to repeat": tempo buttons, and the song editor's and
/// time signature sheet's −/+). Holding fires after [holdDelay], then
/// repeats at [startRate] steps per second; with [accelerate] it speeds up
/// to [maxRate] by [fullSpeedAfter] of holding. Releasing stops at once.
/// Reaching the end of the range (the caller disables the button) stops the
/// repeat with a medium haptic bump.
class RepeatButton extends StatefulWidget {
  const RepeatButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.accelerate = true,
  });

  /// Starting values from the spec; tune on a phone.
  static const holdDelay = Duration(milliseconds: 400);
  static const startRate = 6.0;
  static const maxRate = 15.0;
  static const fullSpeedAfter = Duration(milliseconds: 1500);

  /// Null disables the button (and stops a running repeat).
  final VoidCallback? onPressed;

  final Widget child;
  final ButtonStyle? style;

  /// Speed up while held (tempo); false keeps [startRate] (beats).
  final bool accelerate;

  @override
  State<RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<RepeatButton> {
  Timer? _repeat;
  bool _holding = false;
  // How long the button has been held, summed from the scheduled steps.
  Duration _held = Duration.zero;

  void _start() {
    if (!_holding) MetraMotion.moving(1);
    _holding = true;
    widget.onPressed?.call();
    _held = RepeatButton.holdDelay;
    _scheduleNext();
  }

  void _scheduleNext() {
    final interval = Duration(microseconds: (1e6 / _rate()).round());
    _repeat = Timer(interval, () {
      _held += interval;
      final onPressed = widget.onPressed;
      if (onPressed == null) return _stop();
      onPressed();
      if (_repeat != null) _scheduleNext(); // not stopped by the step
    });
  }

  /// Steps per second, ramping linearly from the first repeat until
  /// [RepeatButton.fullSpeedAfter] of holding.
  double _rate() {
    if (!widget.accelerate) return RepeatButton.startRate;
    final ramp =
        ((_held - RepeatButton.holdDelay).inMicroseconds /
                (RepeatButton.fullSpeedAfter - RepeatButton.holdDelay)
                    .inMicroseconds)
            .clamp(0.0, 1.0);
    return RepeatButton.startRate +
        (RepeatButton.maxRate - RepeatButton.startRate) * ramp;
  }

  void _stop() {
    if (_holding) MetraMotion.moving(-1);
    _holding = false;
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void didUpdateWidget(RepeatButton old) {
    super.didUpdateWidget(old);
    if (widget.onPressed == null && _repeat != null) {
      _stop();
      Haptics.medium(); // the hold hit the end of the range
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    // The button is the screen reader's target; holding is touch only.
    excludeFromSemantics: true,
    gestures: {
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: RepeatButton.holdDelay,
              debugOwner: this,
            ),
            (recognizer) => recognizer
              ..onLongPressStart = (widget.onPressed == null
                  ? null
                  : (_) => _start())
              ..onLongPressEnd = ((_) => _stop())
              ..onLongPressCancel = _stop,
          ),
    },
    child: FilledButton(
      style: widget.style,
      onPressed: widget.onPressed,
      child: widget.child,
    ),
  );
}
