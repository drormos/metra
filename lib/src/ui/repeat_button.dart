import 'dart:async';

import 'package:flutter/material.dart';

/// A filled button that fires once on tap and repeats while held
/// (ui-spec.md: tempo buttons and the song editor's −/+). Repeats start
/// after the platform long-press delay, every [interval].
class RepeatButton extends StatefulWidget {
  const RepeatButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.style,
    this.interval = const Duration(milliseconds: 100),
  });

  /// Null disables the button (and stops a running repeat).
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  final Duration interval;

  @override
  State<RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<RepeatButton> {
  Timer? _repeat;

  void _start() {
    widget.onPressed?.call();
    _repeat = Timer.periodic(widget.interval, (_) {
      final onPressed = widget.onPressed;
      // Hitting a limit disables the button: stop instead of firing on.
      onPressed == null ? _stop() : onPressed();
    });
  }

  void _stop() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void didUpdateWidget(RepeatButton old) {
    super.didUpdateWidget(old);
    if (widget.onPressed == null) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPressStart: widget.onPressed == null ? null : (_) => _start(),
    onLongPressEnd: (_) => _stop(),
    onLongPressCancel: _stop,
    child: FilledButton(
      style: widget.style,
      onPressed: widget.onPressed,
      child: widget.child,
    ),
  );
}
