import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'panel_motion.dart';
import 'swipe_row.dart';
import 'theme.dart';

/// A panel that drops down from the top row (ui-spec.md "Top panels"):
/// the stopwatch's "When I press Start" and the "4/4" button's Rhythm. It
/// sits just under the top row, 12px from the screen edges, fits its
/// content, down to 16px above the screen's bottom (over the dimmed
/// context row; taller content scrolls inside); the screen below the top
/// row is dimmed, the top row stays sharp. It grows out of its button
/// ([PanelMotion]); the same button again or Back shrinks it back into it;
/// a tap anywhere else (the dim, or anything above the panel: nothing
/// there opens) closes it with the plain leave motion; a swipe up flings
/// it off. The click keeps playing.
abstract final class TopPanel {
  /// The main screen's top row, which the panel hangs under.
  static final topRowKey = GlobalKey(debugLabel: 'top-row');

  static const surfaceKey = Key('top-panel');
  static const handleKey = Key('top-panel-handle');

  static _TopPanelRoute? _open;

  /// Opens the panel [id] with [child] out of the button [context]
  /// belongs to; if a panel is open it closes, and when it was this one,
  /// that's all (the button toggles it).
  static Future<void> toggle(
    BuildContext context, {
    required Object id,
    required Widget child,
  }) async {
    final open = _open;
    final same = open != null && open.isActive && open.id == id;
    close();
    if (same) return;
    final box = context.findRenderObject()! as RenderBox;
    final route = _TopPanelRoute(
      id: id,
      child: child,
      button: box.localToGlobal(Offset.zero) & box.size,
      reduced: RowGestures.reduceMotion(context),
      dim: context.colors.dim,
    );
    _open = route;
    await Navigator.of(context).push(route);
    if (_open == route) _open = null;
  }

  /// Closes the open panel, if any (another top-row button was used).
  static void close() {
    final open = _open;
    if (open == null) return;
    _open = null;
    final navigator = open.navigator;
    if (navigator == null || !open.isActive) return;
    open.isCurrent ? navigator.pop() : navigator.removeRoute(open);
  }
}

class _TopPanelRoute extends PopupRoute<void> {
  _TopPanelRoute({
    required this.id,
    required this.child,
    required this.button,
    required this.reduced,
    required this.dim,
  });

  final Object id;
  final Widget child;
  // The button that opened it (global).
  final Rect button;
  final bool reduced;
  final Color dim;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  // No touch barrier: the top row above the panel stays visible and sharp
  // (the page catches taps on it and dims the rest). A screen reader stays
  // in the panel, as with a sheet (the dimmed area is its Close).
  @override
  Widget buildModalBarrier() =>
      const BlockSemantics(child: IgnorePointer(child: SizedBox.expand()));

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : MetraMotion.arrive;

  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : PanelMotion.settle;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PanelMotion(
    route: this,
    origin: button.center,
    edge: PanelEdge.top,
    leaveOnOutsideTap: true,
    builder: (context, motion) =>
        _TopPanelPage(motion: motion, dim: dim, button: button, child: child),
  );
}

class _TopPanelPage extends StatelessWidget {
  const _TopPanelPage({
    required this.motion,
    required this.dim,
    required this.button,
    required this.child,
  });

  final PanelMotionState motion;
  final Color dim;
  final Rect button;
  final Widget child;

  static double? _bottomOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy + box.size.height;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final top = _bottomOf(TopPanel.topRowKey) ?? padding.top + 62;
    // Down to 16px above the screen's bottom (above the gesture bar),
    // over the dimmed context row and tabs; above the keyboard while a
    // value is typed.
    final bottom =
        screen.height -
        [
          MediaQuery.viewPaddingOf(context).bottom,
          MediaQuery.viewInsetsOf(context).bottom,
        ].reduce((a, b) => a > b ? a : b) -
        16;
    final t = motion.dim;
    return Stack(
      children: [
        // Above the panel (ui-spec.md "Above a top panel closes it too"): a
        // tap only closes it, back into the button when it's the panel's
        // own; long-presses and drags here do nothing.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapUp: (d) => button.contains(d.globalPosition)
                ? Navigator.of(context).maybePop()
                : motion.closeOutside(),
            onLongPress: () {},
            onPanStart: (_) {},
          ),
        ),
        // Below the top row: dimmed; a touch starting here closes.
        Positioned(
          left: 0,
          right: 0,
          top: top,
          bottom: 0,
          child: CloseOnTouch(
            child: ColoredBox(color: dim.withValues(alpha: dim.a * t)),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: top,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // The grab strip reaches past the panel's bottom edge.
              maxHeight: (bottom - top + PanelMotionState.grabOut).clamp(
                120.0,
                screen.height,
              ),
            ),
            // Swiped up (on the panel or its grab strip) it follows 1:1;
            // past a third, or on a flick, it flies off the top; otherwise
            // it springs back.
            child: GestureDetector(
              dragStartBehavior: DragStartBehavior.down,
              onVerticalDragUpdate: (d) => motion.dragBy(d.delta.dy),
              onVerticalDragEnd: (d) => _release(motion, d),
              child: motion.panel(
                _surface(context, colors),
                onGrabUpdate: (d) => motion.dragBy(d.delta.dy),
                onGrabEnd: (d) => _release(motion, d),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static void _release(PanelMotionState motion, DragEndDetails d) {
    // Up is negative.
    final v = d.velocity.pixelsPerSecond.dy;
    motion.release(
      velocity: v,
      close:
          -v > RowGestures.closeFlick ||
          (motion.dragged > RowGestures.closeFraction * motion.panelHeight &&
              v <= RowGestures.closeFlick),
    );
  }

  Widget _surface(BuildContext context, MetraColors colors) => Container(
    key: TopPanel.surfaceKey,
    decoration: BoxDecoration(
      color: colors.sheet,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: colors.border),
      boxShadow: [
        BoxShadow(
          color: colors.dim,
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      type: MaterialType.transparency,
      // The panel is inside the screen: no system insets of its own.
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 18),
            Flexible(child: child),
            Center(
              child: Container(
                key: TopPanel.handleKey,
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.beatResting,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A panel's dimmed area (ui-spec.md "Top panels"): any touch that starts
/// on it, a tap or a swipe in any direction, closes the panel on touch-up,
/// like Back. It absorbs those touches: nothing reaches the screen below
/// (no ruler drags, no button taps). Read as "Close" by screen readers.
class CloseOnTouch extends StatelessWidget {
  const CloseOnTouch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Close',
    onTap: () => _close(context),
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerUp: (_) => _close(context),
      // Claims the gesture, so no recognizer elsewhere takes it.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: () {},
        onPanStart: (_) {},
        child: child,
      ),
    ),
  );

  /// Once: a second finger lifting while the panel leaves pops nothing.
  static void _close(BuildContext context) {
    final motion = context.findAncestorStateOfType<PanelMotionState>();
    if (motion != null) return motion.closeOutside();
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }
}
