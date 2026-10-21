import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';
import 'theme.dart';

/// Long-press vs swipe in every list (ui-spec.md "Long-press vs swipe (all
/// lists)"), in one place.
abstract final class RowGestures {
  /// A swipe starts only after this much horizontal movement; below it,
  /// the row doesn't move and a pending long-press survives.
  static const swipeStart = 32.0;

  /// ...and only when mostly sideways: |dx| ≥ this × |dy|.
  static const swipeRatio = 2.0;

  /// How long a finger rests for a long-press (rename, or lift to reorder).
  static const longPress = Duration(milliseconds: 400);

  /// Released past this share of the row's width, a swipe acts; earlier,
  /// the row springs back.
  static const swipeCommit = 0.4;

  /// How far the one-time hint slides a row.
  static const hintSlide = 56.0;

  /// The long-press tolerance for the reorder lift too (see
  /// [HoldToReorder]).
  static const settings = DeviceGestureSettings(touchSlop: swipeStart);
}

/// A horizontal drag that accepts only past [RowGestures.swipeStart] of
/// mostly sideways movement, so a slightly moving long-press still wins,
/// and vertical movement leaves the touch to the list's scroll.
class SwipeGestureRecognizer extends HorizontalDragGestureRecognizer {
  // From the touch-down, so the movement that wins the swipe is reported
  // too (with `start`, the event that crosses 32dp would be dropped).
  SwipeGestureRecognizer({super.debugOwner}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  Offset _moved = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _moved += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      _moved.dx.abs() > RowGestures.swipeStart &&
      _moved.dx.abs() >= RowGestures.swipeRatio * _moved.dy.abs();
}

/// A long-press after [RowGestures.longPress] that movement under
/// [RowGestures.swipeStart] doesn't cancel. Once it fires it owns the
/// touch (no swipe, no tap); lifting earlier leaves the tap to the row.
class HoldGestureRecognizer extends PrimaryPointerGestureRecognizer {
  HoldGestureRecognizer({super.debugOwner})
    : super(
        deadline: RowGestures.longPress,
        preAcceptSlopTolerance: RowGestures.swipeStart,
        postAcceptSlopTolerance: null,
      );

  VoidCallback? onHold;

  @override
  void didExceedDeadline() {
    resolve(GestureDisposition.accepted);
    onHold?.call();
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (state == GestureRecognizerState.possible) {
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  String get debugDescription => 'hold';
}

/// The reorder lift for a set's songs: the list's long-press drag, with
/// the same [RowGestures.longPress] and 32dp tolerance as everything else.
class HoldToReorder extends ReorderableDelayedDragStartListener {
  const HoldToReorder({super.key, required super.index, required super.child});

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        debugOwner: this,
        delay: RowGestures.longPress,
      );

  // The list hands the recognizer the gesture settings found above the
  // listener, so the 32dp tolerance goes in here.
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(gestureSettings: RowGestures.settings),
    child: Builder(builder: super.build),
  );
}

/// A list row that swipes either way to act ([onSwiped], light haptic),
/// with a red [label] behind it. With [ask] (a delete), the row stays open
/// while it asks;
/// no = it slides back. [onHold] is the row's long-press. [hint] drives
/// the one-time hint (0 → 1: out and back).
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.label,
    required this.onSwiped,
    required this.child,
    this.ask,
    this.onHold,
    this.hint,
  });

  final String label;
  final VoidCallback onSwiped;
  final Future<bool> Function()? ask;
  final VoidCallback? onHold;
  final Animation<double>? hint;
  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  // The row's sideways offset in pixels, following the finger.
  late final _offset = AnimationController.unbounded(vsync: this);
  double _width = 0;
  bool _busy = false; // asking, or sliding out

  // The first [RowGestures.swipeStart] of a swipe doesn't move the row, so
  // it doesn't jump when the swipe starts.
  double _skip = 0;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _back() => _offset.animateTo(
    0,
    duration: const Duration(milliseconds: 200),
    curve: Curves.easeOut,
  );

  Future<void> _end() async {
    final past = _offset.value.abs() > RowGestures.swipeCommit * _width;
    if (!past) return _back();
    _busy = true;
    final ask = widget.ask;
    if (ask != null && !await ask()) {
      _busy = false;
      if (mounted) _back();
      return;
    }
    if (!mounted) return;
    await _offset.animateTo(
      _offset.value.sign * _width,
      duration: const Duration(milliseconds: 150),
    );
    if (!mounted) return;
    Haptics.tick();
    widget.onSwiped();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final onHold = widget.onHold;
    final hint = widget.hint;
    Widget behind(double offset) => Container(
      color: colors.accentResting,
      alignment: offset > 0 ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        widget.label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.text,
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        return RawGestureDetector(
          gestures: {
            SwipeGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<SwipeGestureRecognizer>(
                  () => SwipeGestureRecognizer(debugOwner: this),
                  (r) => r
                    ..onStart = (_) {
                      _skip = RowGestures.swipeStart;
                    }
                    ..onUpdate = (d) {
                      if (_busy) return;
                      var delta = d.primaryDelta ?? 0;
                      final skipped = min(_skip, delta.abs());
                      _skip -= skipped;
                      delta -= delta.sign * skipped;
                      _offset.value += delta;
                    }
                    ..onEnd = (_) {
                      if (!_busy) _end();
                    }
                    ..onCancel = () {
                      if (!_busy) _back();
                    },
                ),
            if (onHold != null)
              HoldGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<HoldGestureRecognizer>(
                    () => HoldGestureRecognizer(debugOwner: this),
                    (r) => r.onHold = onHold,
                  ),
          },
          child: AnimatedBuilder(
            animation: Listenable.merge([_offset, ?hint]),
            builder: (context, child) {
              final slide = hint == null
                  ? 0.0
                  : -RowGestures.hintSlide * sin(pi * hint.value);
              final offset = _offset.value + slide;
              return Stack(
                children: [
                  if (offset != 0 || hint != null)
                    Positioned.fill(child: behind(offset == 0 ? -1 : offset)),
                  Transform.translate(offset: Offset(offset, 0), child: child),
                ],
              );
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}
