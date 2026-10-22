import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

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
  static const liftPress = Duration(milliseconds: 200);

  /// How long a finger rests to rename (Songs list, sets view): longer,
  /// since an accidental one opens the keyboard.
  static const renamePress = Duration(milliseconds: 400);

  /// Vertical movement past this before a long-press fires is a scroll
  /// (the lists' scroll slop; Android's normal touch slop).
  static const scrollSlop = 8.0;

  /// A dropped row settling into its slot; a cancelled swipe springing
  /// back (ease-out, no bounce).
  static const settle = Duration(milliseconds: 150);
  static const springBack = Duration(milliseconds: 180);

  /// A committed swipe: the row slides the rest of the way off, then the
  /// gap closes as the rows below move up.
  static const slideOff = Duration(milliseconds: 120);
  static const collapse = Duration(milliseconds: 150);

  /// A release faster than this (dp/s) commits in its direction even short
  /// of [swipeCommit]; one back toward the start cancels.
  static const flickVelocity = 1000.0;

  /// Past [swipeCommit] the label and trash icon grow to this, and the
  /// red deepens, over [armTransition].
  static const armedScale = 1.1;
  static const armTransition = Duration(milliseconds: 100);

  /// A new touch finishes a running animation this fast, then is handled.
  static const catchUp = Duration(milliseconds: 80);

  /// Released past this share of the row's width, a swipe acts; earlier,
  /// the row springs back.
  static const swipeCommit = 0.4;

  /// How far the one-time hint slides a row.
  static const hintSlide = 56.0;

  /// The time signature sheet and the ☰ panel close when dragged past this
  /// share of their size, or flicked faster than [closeFlick] (dp/s)
  /// toward closing; otherwise they spring back ([springBack]).
  static const closeFraction = 1 / 3;
  static const closeFlick = 700.0;

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

/// Where a committed row leaves the list (ui-spec.md "Swipe feel"): the
/// data has already changed, so the row is gone from the list; the host
/// draws a copy sliding the rest of the way off ([RowGestures.slideOff])
/// while the rows below ([ExitShift]) keep the gap, then closes it
/// ([RowGestures.collapse]). A new touch finishes it all in
/// [RowGestures.catchUp].
class RowExitHost extends StatefulWidget {
  const RowExitHost({super.key, required this.child});

  final Widget child;

  static RowExitHostState? of(BuildContext context) =>
      context.findAncestorStateOfType<RowExitHostState>();

  @override
  State<RowExitHost> createState() => RowExitHostState();
}

class RowExitHostState extends State<RowExitHost>
    with SingleTickerProviderStateMixin {
  static final _total = RowGestures.slideOff + RowGestures.collapse;
  late final _exit = AnimationController(
    vsync: this,
    duration: _total,
    value: 1,
  );
  ({int index, Rect rect, Widget ghost, double from, double to})? _leaving;
  CatchUp? _catchUp;

  /// How far the gap has closed (0 → 1), after the slide.
  double get _closed => Curves.easeOut.transform(
    ((_exit.value * _total.inMicroseconds -
                RowGestures.slideOff.inMicroseconds) /
            RowGestures.collapse.inMicroseconds)
        .clamp(0.0, 1.0),
  );

  /// The row at list position [index] (drawn as [ghost], in [box], [from]
  /// pixels sideways) was just removed from the data: show it leaving.
  void leave({
    required int index,
    required RenderBox box,
    required Widget ghost,
    required double from,
  }) {
    final host = context.findRenderObject() as RenderBox?;
    if (host == null || !box.attached) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: host);
    setState(
      () => _leaving = (
        index: index,
        rect: topLeft & box.size,
        ghost: ghost,
        from: from,
        to: from.sign * box.size.width,
      ),
    );
    final catchUp = _catchUp = CatchUpScope.of(context);
    catchUp?.add(this, () => _exit.animateTo(1, duration: RowGestures.catchUp));
    _exit.forward(from: 0).whenCompleteOrCancel(() {
      catchUp?.remove(this);
      if (mounted) setState(() => _leaving = null);
    });
  }

  @override
  void dispose() {
    _catchUp?.remove(this);
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    return _RowExitScope(
      host: this,
      leaving: leaving == null
          ? null
          : (index: leaving.index, height: leaving.rect.height),
      child: Stack(
        children: [
          widget.child,
          if (leaving != null)
            Positioned.fromRect(
              rect: leaving.rect,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _exit,
                    builder: (context, child) {
                      final slid =
                          (_exit.value *
                                  _total.inMicroseconds /
                                  RowGestures.slideOff.inMicroseconds)
                              .clamp(0.0, 1.0);
                      if (slid >= 1) return const SizedBox.shrink();
                      final x =
                          leaving.from + (leaving.to - leaving.from) * slid;
                      return Transform.translate(
                        offset: Offset(x, 0),
                        child: child,
                      );
                    },
                    child: leaving.ghost,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowExitScope extends InheritedWidget {
  const _RowExitScope({
    required this.host,
    required this.leaving,
    required super.child,
  });

  final RowExitHostState host;
  final ({int index, double height})? leaving;

  @override
  bool updateShouldNotify(_RowExitScope old) => old.leaving != leaving;
}

/// A list row at position [index]: while a row above it is leaving, it
/// holds the gap and then moves up with the others.
class ExitShift extends StatelessWidget {
  const ExitShift({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_RowExitScope>();
    final leaving = scope?.leaving;
    if (scope == null || leaving == null || index < leaving.index) {
      return child;
    }
    final host = scope.host;
    return AnimatedBuilder(
      animation: host._exit,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, leaving.height * (1 - host._closed)),
        child: child,
      ),
      child: child,
    );
  }
}

/// A list row that swipes either way to act (ui-spec.md "Swipe feel"):
/// it follows the finger 1:1 after the 32dp start; past
/// [RowGestures.swipeCommit] it arms (one light tick, deeper red, the
/// label and trash icon grow) and disarms going back (another tick).
/// Release armed, or flick faster than [RowGestures.flickVelocity] in the
/// swipe's direction, to commit; a flick back cancels. Commit: [onSwiped]
/// at once and the row leaves via [RowExitHost] (as list position
/// [index]). With [ask] (a delete) the row holds open at the threshold
/// while it asks; no = it springs back. Off unless [enabled] (a reorder
/// drag, a rename). [actionLabel] is the same action for TalkBack.
/// [onHold] is the row's long-press; [hint] drives the one-time hint.
class SwipeRow extends StatefulWidget {
  const SwipeRow({
    super.key,
    required this.index,
    required this.label,
    required this.actionLabel,
    required this.onSwiped,
    required this.child,
    this.ask,
    this.onHold,
    this.hint,
    this.enabled = true,
    this.moreActions = const {},
  });

  final int index;
  final String label;
  final String actionLabel;
  final VoidCallback onSwiped;
  final Future<bool> Function()? ask;
  final VoidCallback? onHold;
  final Animation<double>? hint;
  final bool enabled;

  /// More TalkBack custom actions for the row ("Move up" / "Move down").
  final Map<String, VoidCallback> moreActions;
  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow>
    with SingleTickerProviderStateMixin {
  // The row's sideways offset in pixels, following the finger.
  late final _offset = AnimationController.unbounded(vsync: this);
  double _width = 0;
  bool _busy = false; // asking, or gone
  bool _armed = false;

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

  double get _threshold => RowGestures.swipeCommit * _width;

  void _move(double delta) {
    if (_busy) return;
    final skipped = min(_skip, delta.abs());
    _skip -= skipped;
    _offset.value += delta - delta.sign * skipped;
    final armed = _offset.value.abs() > _threshold;
    if (armed != _armed) {
      Haptics.tick(); // the only haptic of a swipe
      setState(() => _armed = armed);
    }
  }

  /// Springs back; a new touch anywhere in the list finishes it quickly.
  void _back() {
    if (_armed) setState(() => _armed = false);
    final catchUp = _catchUp = CatchUpScope.of(context);
    catchUp?.add(
      this,
      () => _offset.animateTo(0, duration: RowGestures.catchUp),
    );
    _offset
        .animateTo(0, duration: RowGestures.springBack, curve: Curves.easeOut)
        .whenCompleteOrCancel(() => catchUp?.remove(this));
  }

  Future<void> _end(double velocity) async {
    final offset = _offset.value;
    final flick = velocity.abs() > RowGestures.flickVelocity;
    final commit = flick
        ? velocity.sign == offset.sign && offset != 0
        : offset.abs() > _threshold;
    if (!commit) return _back();
    final ask = widget.ask;
    if (ask != null) {
      _busy = true;
      // Held open at the threshold while the dialog is up.
      if (!_armed) setState(() => _armed = true);
      _offset.animateTo(
        offset.sign * _threshold,
        duration: RowGestures.springBack,
        curve: Curves.easeOut,
      );
      final ok = await ask();
      if (!mounted) return;
      _busy = false;
      if (!ok) return _back();
    }
    _commit();
  }

  /// The change happens now; the row leaves through the host.
  void _commit() {
    _busy = true;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.attached) {
      RowExitHost.of(context)?.leave(
        index: widget.index,
        box: box,
        ghost: _surface(context),
        from: _offset.value,
      );
    }
    widget.onSwiped();
  }

  /// TalkBack's custom action: the same, without the swipe.
  Future<void> _act() async {
    final ask = widget.ask;
    if (ask != null && !await ask()) return;
    if (mounted) widget.onSwiped();
  }

  /// What's behind the row: red, with the trash icon and label on the
  /// revealed side; deeper and slightly larger once armed.
  Widget _behind(BuildContext context, double offset) {
    final colors = context.colors;
    return AnimatedContainer(
      duration: RowGestures.armTransition,
      color: _armed ? colors.accent : colors.accentResting,
      alignment: offset > 0 ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: AnimatedScale(
        duration: RowGestures.armTransition,
        scale: _armed ? RowGestures.armedScale : 1,
        alignment: offset > 0 ? Alignment.centerLeft : Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline, size: 18, color: colors.text),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The row with its revealed background, as it sits now (also the ghost
  /// that slides off).
  Widget _surface(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: _behind(context, _offset.value)),
      widget.child,
    ],
  );

  @override
  Widget build(BuildContext context) {
    final onHold = widget.onHold;
    final hint = widget.hint;
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: widget.actionLabel): _act,
        for (final MapEntry(key: label, value: action)
            in widget.moreActions.entries)
          CustomSemanticsAction(label: label): action,
      },
      child: LayoutBuilder(
        builder: (context, box) {
          _width = box.maxWidth;
          return RawGestureDetector(
            gestures: {
              if (widget.enabled)
                SwipeGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      SwipeGestureRecognizer
                    >(
                      () => SwipeGestureRecognizer(debugOwner: this),
                      (r) => r
                        ..onStart = (_) {
                          _skip = RowGestures.swipeStart;
                          // One row in motion: others settle now.
                          CatchUpScope.of(context)?.now();
                        }
                        ..onUpdate = (d) {
                          _move(d.primaryDelta ?? 0);
                        }
                        ..onEnd = (d) {
                          if (!_busy) _end(d.primaryVelocity ?? 0);
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
                      Positioned.fill(
                        child: _behind(context, offset == 0 ? -1 : offset),
                      ),
                    Transform.translate(
                      offset: Offset(offset, 0),
                      child: child,
                    ),
                  ],
                );
              },
              child: widget.child,
            ),
          );
        },
      ),
    );
  }
}

/// Drag to close (ui-spec.md "Sheet behavior", "Panel behavior"): [child]
/// follows the finger along [axis] toward closing (down, or right), and
/// closes ([onClose]) past [RowGestures.closeFraction] of its size or on a
/// flick faster than [RowGestures.closeFlick]; otherwise it springs back.
class DragToClose extends StatefulWidget {
  const DragToClose({
    super.key,
    required this.axis,
    required this.onClose,
    required this.child,
  });

  final Axis axis;
  final VoidCallback onClose;
  final Widget child;

  @override
  State<DragToClose> createState() => _DragToCloseState();
}

class _DragToCloseState extends State<DragToClose>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  bool _closing = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  double get _size {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 1;
    return widget.axis == Axis.vertical ? box.size.height : box.size.width;
  }

  void _update(double delta) {
    if (!_closing) _offset.value = max(0, _offset.value + delta);
  }

  void _end(double velocity) {
    if (_closing) return;
    final past = _offset.value > RowGestures.closeFraction * _size;
    if (velocity > RowGestures.closeFlick ||
        (past && velocity >= -RowGestures.closeFlick)) {
      _closing = true;
      widget.onClose();
    } else {
      _offset.animateTo(
        0,
        duration: RowGestures.springBack,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    return GestureDetector(
      onVerticalDragUpdate: vertical ? (d) => _update(d.delta.dy) : null,
      onVerticalDragEnd: vertical
          ? (d) => _end(d.velocity.pixelsPerSecond.dy)
          : null,
      onHorizontalDragUpdate: vertical ? null : (d) => _update(d.delta.dx),
      onHorizontalDragEnd: vertical
          ? null
          : (d) => _end(d.velocity.pixelsPerSecond.dx),
      child: AnimatedBuilder(
        animation: _offset,
        builder: (context, child) => Transform.translate(
          offset: vertical
              ? Offset(0, _offset.value)
              : Offset(_offset.value, 0),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
