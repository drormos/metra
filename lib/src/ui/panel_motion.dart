import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// The edge a panel leaves through when swiped: top panels go up, the
/// context row's lists go down.
enum PanelEdge { top, bottom }

/// How every panel moves (ui-spec.md "Top panels": "Open and close from
/// the button", "Predictive back", "Swipe to close never pauses"):
/// - It grows out of the button that opened it ([origin], global): 0.96 →
///   1 scale about that point with opacity 0 → 1 over the route's own
///   transition (~200ms in, ~180ms out); the dim follows.
/// - [dragBy] moves it 1:1 toward [edge]; [release] either springs back
///   (~180ms ease-out) or flings it on from where it is, at least as fast
///   as the finger, off the edge in ~180ms with its opacity (and the dim)
///   tied to the distance left, then removes the route: no pause, no
///   second fade.
/// - An Android back gesture scales it 1 → 0.9 toward the button and dims
///   it slightly; commit closes it as Back does, cancel springs back.
/// With Remove animations on, all of it is instant.
class PanelMotion extends StatefulWidget {
  const PanelMotion({
    super.key,
    required this.route,
    required this.origin,
    required this.edge,
    required this.builder,
  });

  final ModalRoute<void> route;
  final Offset origin;
  final PanelEdge edge;

  /// Builds the page from the motion's current state: [PanelMotionState.dim]
  /// for the dimmed area, [PanelMotionState.panel] around the panel.
  final Widget Function(BuildContext context, PanelMotionState motion) builder;

  static const backScale = 0.9;
  static const backFade = 0.15;
  static const openScale = 0.96;
  static const settle = Duration(milliseconds: 180);

  static PanelMotionState of(BuildContext context) =>
      context.findAncestorStateOfType<PanelMotionState>()!;

  @override
  State<PanelMotion> createState() => PanelMotionState();
}

class PanelMotionState extends State<PanelMotion>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _panelKey = GlobalKey();
  // Offset along the swipe (px, toward the edge positive), and the
  // predictive back progress (0–1).
  late final _swipe = AnimationController.unbounded(vsync: this);
  late final _back = AnimationController(vsync: this);
  // While flung: the distance left to go when released (for the fade).
  double? _flungFrom;
  bool _gone = false;

  bool get _reduced => MetraMotion.reduced(context);
  double get _sign => widget.edge == PanelEdge.top ? -1 : 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _swipe.dispose();
    _back.dispose();
    super.dispose();
  }

  Rect? get _panelRect {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// How far the panel still has to travel to be off its edge.
  double get _toGo {
    final rect = _panelRect;
    if (rect == null) return 0;
    // The layout rect: the swipe moves it on top of that.
    return max(
      0,
      widget.edge == PanelEdge.top
          ? rect.bottom - _swipe.value
          : MediaQuery.sizeOf(context).height - rect.top - _swipe.value,
    );
  }

  /// The swipe so far (toward the edge, px).
  double get dragged => _swipe.value;

  /// The panel's height (0 before its first layout).
  double get panelHeight => _panelRect?.height ?? 0;

  /// Follows the finger: [delta] is the finger's move along the screen's
  /// y axis; only movement toward the edge (or back) counts.
  void dragBy(double delta) {
    if (_flungFrom != null || _gone) return;
    _swipe.stop();
    _swipe.value = max(0, _swipe.value + delta * _sign);
  }

  /// The finger lifted at [velocity] (screen y, px/s): [close] flings it
  /// off, otherwise it springs back.
  void release({required double velocity, required bool close}) {
    if (_gone) return;
    if (!close) {
      if (_reduced) {
        _swipe.value = 0;
      } else {
        _swipe.animateTo(
          0,
          duration: PanelMotion.settle,
          curve: Curves.easeOut,
        );
      }
      return;
    }
    final toGo = _toGo;
    if (_reduced || toGo <= 0) return _remove();
    _flungFrom = toGo;
    final speed = max(0.0, velocity * _sign);
    _swipe
        .animateWith(
          _Fling(
            from: _swipe.value,
            to: _swipe.value + toGo,
            speed: speed,
            time: PanelMotion.settle.inMicroseconds / 1e6,
          ),
        )
        .whenComplete(_remove);
  }

  void _remove() {
    if (_gone || !mounted) return;
    _gone = true;
    final route = widget.route;
    if (route.isActive) route.navigator?.removeRoute(route);
  }

  // Predictive back: only while this panel is the current route.
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!widget.route.isCurrent || _gone) return false;
    _back.value = _reduced ? 0 : backEvent.progress;
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (!_reduced) _back.value = backEvent.progress;
  }

  @override
  void handleCancelBackGesture() {
    if (_reduced) {
      _back.value = 0;
    } else {
      _back.animateTo(0, duration: PanelMotion.settle, curve: Curves.easeOut);
    }
  }

  @override
  void handleCommitBackGesture() {
    final route = widget.route;
    if (route.isCurrent) route.navigator?.pop();
  }

  /// The route's open / close progress, eased (in: ease-out; out: the
  /// reverse of it, so it shrinks back the way it came).
  double get _shown {
    final a = widget.route.animation!;
    return Curves.easeOut.transform(a.value);
  }

  /// Opacity of the dim (and of everything that fades with the panel).
  double get dim {
    final flung = _flungFrom;
    final swipe = flung == null || flung <= 0 ? 1.0 : (_toGo / flung);
    return (_shown * swipe.clamp(0.0, 1.0)).clamp(0.0, 1.0);
  }

  /// [child] (the panel's box) with the motion applied.
  Widget panel(Widget child) {
    final shown = _shown;
    final back = _back.value;
    final scale =
        (PanelMotion.openScale + (1 - PanelMotion.openScale) * shown) *
        (1 - (1 - PanelMotion.backScale) * back);
    final rect = _panelRect;
    // About the button: as a fraction of the panel (the first frame, at
    // opacity 0, uses its centre).
    final alignment = rect == null || rect.isEmpty
        ? Alignment.center
        : Alignment(
            (widget.origin.dx - rect.left) / rect.width * 2 - 1,
            (widget.origin.dy - rect.top) / rect.height * 2 - 1,
          );
    // Measured outside the transforms: its layout rect.
    return KeyedSubtree(
      key: _panelKey,
      child: Opacity(
        opacity: (dim * (1 - PanelMotion.backFade * back)).clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, _swipe.value * _sign),
          child: Transform.scale(
            scale: scale,
            alignment: alignment,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.route.animation, _swipe, _back]),
    builder: (context, _) => widget.builder(context, this),
  );
}

/// From [from] to [to] in [time] seconds, starting at [speed] (px/s) and
/// speeding up (ease-in); a flick fast enough to get there sooner keeps
/// its own speed.
class _Fling extends Simulation {
  _Fling({
    required this.from,
    required this.to,
    required double speed,
    required double time,
  }) : _v = speed,
       _t = speed * time >= to - from ? (to - from) / max(speed, 1) : time {
    final d = to - from;
    // x(t) = v t + a t² / 2, reaching d at _t.
    _a = speed * time >= d ? 0 : 2 * (d - speed * _t) / (_t * _t);
  }

  final double from;
  final double to;
  final double _v;
  final double _t;
  late final double _a;

  @override
  double x(double time) {
    final t = min(time, _t);
    return min(to, from + _v * t + _a * t * t / 2);
  }

  @override
  double dx(double time) => time >= _t ? 0 : _v + _a * time;

  @override
  bool isDone(double time) => time >= _t;
}
