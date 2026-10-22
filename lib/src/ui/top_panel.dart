import 'package:flutter/material.dart';

import 'swipe_row.dart';
import 'theme.dart';

/// A panel that drops down from the top row (ui-spec.md "Top panels"):
/// the stopwatch's "When I press Start" and the "4/4" button's Rhythm. It
/// sits just under the top row, 12px from the screen edges, fits its
/// content, down to 16px above the screen's bottom (over the dimmed
/// context row; taller content scrolls inside); the screen below the top
/// row is dimmed, the top row stays sharp
/// and usable. Tap outside, the same button again, Back, or a swipe up
/// closes it. The click keeps playing.
abstract final class TopPanel {
  /// The main screen's top row, which the panel hangs under.
  static final topRowKey = GlobalKey(debugLabel: 'top-row');

  static const surfaceKey = Key('top-panel');
  static const handleKey = Key('top-panel-handle');

  static _TopPanelRoute? _open;

  /// Opens the panel [id] with [child]; if a panel is open it closes, and
  /// when it was this one, that's all (the button toggles it).
  static Future<void> toggle(
    BuildContext context, {
    required Object id,
    required Widget child,
  }) async {
    final open = _open;
    final same = open != null && open.isActive && open.id == id;
    close();
    if (same) return;
    final route = _TopPanelRoute(
      id: id,
      child: child,
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
    required this.reduced,
    required this.dim,
  });

  final Object id;
  final Widget child;
  final bool reduced;
  final Color dim;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  // No touch barrier: the top row above the panel stays usable (its
  // buttons toggle the panel); the page dims and closes on the rest. A
  // screen reader stays in the panel, as with a sheet (the dimmed area is
  // its Close).
  @override
  Widget buildModalBarrier() =>
      const BlockSemantics(child: IgnorePointer(child: SizedBox.expand()));

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : MetraMotion.arrive;

  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : MetraMotion.leave;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _TopPanelPage(
    animation: animation,
    dim: dim,
    onClose: () => Navigator.of(context).maybePop(),
    child: child,
  );
}

class _TopPanelPage extends StatelessWidget {
  const _TopPanelPage({
    required this.animation,
    required this.dim,
    required this.onClose,
    required this.child,
  });

  final Animation<double> animation;
  final Color dim;
  final VoidCallback onClose;
  final Widget child;

  static double? _edge(GlobalKey key, {required bool bottom}) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final at = box.localToGlobal(Offset.zero);
    return bottom ? at.dy + box.size.height : at.dy;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final top = _edge(TopPanel.topRowKey, bottom: true) ?? padding.top + 62;
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
    return AnimatedBuilder(
      animation: animation,
      builder: (context, panel) {
        final t = animation.status == AnimationStatus.reverse
            ? 1 - MetraMotion.leaveFade.transform(1 - animation.value)
            : MetraMotion.arriveCurve.transform(animation.value);
        return Stack(
          children: [
            // Below the top row: dimmed, a tap closes.
            Positioned(
              left: 0,
              right: 0,
              top: top,
              bottom: 0,
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: ColoredBox(color: dim.withValues(alpha: dim.a * t)),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: top,
              child: Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, -MetraMotion.arriveRise * (1 - t)),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: (bottom - top).clamp(120.0, screen.height),
                    ),
                    child: panel,
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: DragToClose(
        axis: Axis.vertical,
        reverse: true,
        onClose: onClose,
        child: Container(
          key: TopPanel.surfaceKey,
          decoration: BoxDecoration(
            color: colors.sheet,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.dim,
                blurRadius: 24,
                offset: Offset(0, 8),
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
        ),
      ),
    );
  }
}
