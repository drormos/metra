import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';
import 'theme.dart';

/// Long-press vs swipe in every list (ui-spec.md "Long-press vs swipe (all
/// lists)", "Never wait for an animation"): every timing and threshold, in
/// one place.
abstract final class RowGestures {
  /// A swipe starts only after this much horizontal movement; below it,
  /// the row doesn't move and a pending long-press survives.
  static const swipeStart = 32.0;

  /// ...and only when mostly sideways: |dx| ≥ this × |dy|.
  static const swipeRatio = 2.0;

  /// How long a finger rests to lift a set's song for reordering.
  static const liftPress = Duration(milliseconds: 250);

  /// How long a finger rests to rename (Songs list, sets view): longer,
  /// since an accidental one opens the keyboard.
  static const renamePress = Duration(milliseconds: 400);

  /// Vertical movement past this before a long-press fires is a scroll
  /// (the lists' scroll slop; Android's normal touch slop).
  static const scrollSlop = 8.0;

  /// A dropped row settling into its slot; a swipe springing back.
  static const settle = Duration(milliseconds: 150);
  static const springBack = Duration(milliseconds: 200);

  /// A new touch finishes a running animation this fast, then is handled.
  static const catchUp = Duration(milliseconds: 80);

  /// Released past this share of the row's width, a swipe acts; earlier,
  /// the row springs back.
  static const swipeCommit = 0.4;

  /// How far the one-time hint slides a row.
  static const hintSlide = 56.0;

  /// The long-press tolerance for the reorder lift too (see
  /// [HoldToReorder]).
  static const settings = DeviceGestureSettings(touchSlop: swipeStart);

  /// The lists' own scroll slop.
  static const listSettings = DeviceGestureSettings(touchSlop: scrollSlop);
}

/// Running row animations that a new touch hurries along: each registers a
/// catch-up while it runs ([RowGestures.catchUp]). A list calls [now] on
/// every pointer down, so no animation ever holds up a touch.
class CatchUp {
  final _running = <Object, VoidCallback>{};

  void add(Object owner, VoidCallback hurry) => _running[owner] = hurry;
  void remove(Object owner) => _running.remove(owner);

  void now() {
    for (final hurry in [..._running.values]) {
      hurry();
    }
  }
}

/// Makes a [CatchUp] available to the rows below, and calls it on every
/// touch that lands in [child].
class CatchUpScope extends InheritedWidget {
  CatchUpScope({super.key, required this.catchUp, required Widget child})
    : super(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => catchUp.now(),
          child: child,
        ),
      );

  final CatchUp catchUp;

  static CatchUp? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CatchUpScope>()?.catchUp;

  @override
  bool updateShouldNotify(CatchUpScope old) => old.catchUp != catchUp;
}

/// A dropped row settling into its slot: from the global top it was let go
/// at ([fromTop]) to where it now sits, in [RowGestures.settle]. The order
/// changed already; this only shows it.
class SettleIn extends StatefulWidget {
  const SettleIn({super.key, this.fromTop, required this.child});

  final double? fromTop;
  final Widget child;

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn>
    with SingleTickerProviderStateMixin {
  late final _settle = AnimationController(
    vsync: this,
    duration: RowGestures.settle,
    value: 1,
  );
  double _from = 0;
  CatchUp? _catchUp;

  @override
  void initState() {
    super.initState();
    final fromTop = widget.fromTop;
    if (fromTop == null) return;
    _settle.value = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = context.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.attached) return;
      setState(() => _from = fromTop - box.localToGlobal(Offset.zero).dy);
      final catchUp = _catchUp = CatchUpScope.of(context);
      catchUp?.add(
        this,
        () => _settle.animateTo(1, duration: RowGestures.catchUp),
      );
      _settle
          .animateTo(1, curve: Curves.easeOut)
          .whenCompleteOrCancel(() => catchUp?.remove(this));
    });
  }

  @override
  void dispose() {
    _catchUp?.remove(this);
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _settle,
    builder: (context, child) => Transform.translate(
      offset: Offset(0, _from * (1 - _settle.value)),
      child: child,
    ),
    child: widget.child,
  );
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

/// A long-press (rename) after [RowGestures.renamePress] that movement under
/// [RowGestures.swipeStart] doesn't cancel. Once it fires it owns the
/// touch (no swipe, no tap); lifting earlier leaves the tap to the row.
class HoldGestureRecognizer extends PrimaryPointerGestureRecognizer {
  HoldGestureRecognizer({super.debugOwner})
    : super(
        deadline: RowGestures.renamePress,
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

/// The reorder lift for a set's songs: the list's long-press drag after
/// [RowGestures.liftPress], tolerating 32dp sideways like everything else
/// (vertical movement past the scroll slop goes to the list's scroll).
class HoldToReorder extends ReorderableDelayedDragStartListener {
  const HoldToReorder({super.key, required super.index, required super.child});

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        debugOwner: this,
        delay: RowGestures.liftPress,
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

  // Held, since the scope can't be looked up while disposing.
  CatchUp? _catchUp;

  @override
  void dispose() {
    _catchUp?.remove(this);
    _offset.dispose();
    super.dispose();
  }

  /// Springs back; a new touch anywhere in the list finishes it quickly.
  void _back() {
    final catchUp = _catchUp = CatchUpScope.of(context);
    catchUp?.add(
      this,
      () => _offset.animateTo(0, duration: RowGestures.catchUp),
    );
    _offset
        .animateTo(0, duration: RowGestures.springBack, curve: Curves.easeOut)
        .whenCompleteOrCancel(() => catchUp?.remove(this));
  }

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
    // The change happens now; the row leaves the list at once rather than
    // finishing a slide that would hold up the next touch.
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
