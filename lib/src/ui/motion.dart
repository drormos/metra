import 'package:flutter/material.dart';

import 'theme.dart';

/// Text that changes in place (ui-spec.md "Motion", swap): the old fades
/// out while the new fades in, aligned the same way, with no slide and no
/// size change. A change of [value] starts it.
class Swap extends StatelessWidget {
  const Swap({
    super.key,
    required this.value,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Object? value;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => MetraMotion.reduced(context)
      ? child
      : AnimatedSwitcher(
          duration: MetraMotion.swap,
          switchInCurve: MetraMotion.swapCurve,
          switchOutCurve: MetraMotion.swapCurve,
          layoutBuilder: (current, previous) =>
              Stack(alignment: alignment, children: [...previous, ?current]),
          child: KeyedSubtree(key: ValueKey(value), child: child),
        );
}

/// Something that appears and goes away (ui-spec.md "Motion"): it
/// arrives fading in with a 6px rise, and leaves fading out while its
/// height closes, so what's below flows into the space ([closes]; false
/// for something over empty space, which just fades). Give each [child]
/// its own key; null shows nothing.
class ArriveLeave extends StatelessWidget {
  const ArriveLeave({super.key, this.child, this.closes = true});

  final Widget? child;
  final bool closes;

  static const _none = ValueKey('arrive-leave-none');

  @override
  Widget build(BuildContext context) {
    if (MetraMotion.reduced(context)) return child ?? const SizedBox.shrink();
    final current = child?.key ?? _none;
    return AnimatedSwitcher(
      duration: MetraMotion.arrive,
      reverseDuration: MetraMotion.leave,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = animation.value;
          if (child!.key == current) {
            final p = MetraMotion.arriveCurve.transform(t);
            return Opacity(
              opacity: p,
              child: Transform.translate(
                offset: Offset(0, MetraMotion.arriveRise * (1 - p)),
                child: child,
              ),
            );
          }
          // Leaving (the animation runs back from 1 to 0): no longer
          // something to touch or read.
          final gone = 1 - t;
          final faded = IgnorePointer(
            child: ExcludeSemantics(
              child: Opacity(
                opacity: 1 - MetraMotion.leaveFade.transform(gone),
                child: child,
              ),
            ),
          );
          if (!closes) return faded;
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1 - MetraMotion.leaveSize.transform(gone),
              child: faded,
            ),
          );
        },
      ),
      child: child ?? const SizedBox.shrink(key: _none),
    );
  }
}

/// Content that replaces other content in place (the panel's lists): the
/// new one arrives (fade in, 6px rise) and the old one is simply gone, so
/// no two copies ever share a scroll position. A change of [value] plays it.
class Arrive extends StatelessWidget {
  const Arrive({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(value),
    tween: Tween(begin: MetraMotion.reduced(context) ? 1 : 0, end: 1),
    duration: MetraMotion.arrive,
    curve: MetraMotion.arriveCurve,
    child: child,
    builder: (context, p, child) => p == 1
        ? child!
        : Opacity(
            opacity: p,
            child: Transform.translate(
              offset: Offset(0, MetraMotion.arriveRise * (1 - p)),
              child: child,
            ),
          ),
  );
}

/// The title and set name (ui-spec.md "Motion", fade-through): when
/// [value] changes, the old text fades out fully ([MetraMotion.fadeOut]),
/// then the new one fades in ([MetraMotion.fadeIn]), already laid out at
/// its final size; the two are never visible together. Rebuilds with the
/// same [value] update in place without animating.
class FadeThrough extends StatefulWidget {
  const FadeThrough({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<FadeThrough> createState() => _FadeThroughState();
}

class _FadeThroughState extends State<FadeThrough>
    with SingleTickerProviderStateMixin {
  static final _total = MetraMotion.fadeOut + MetraMotion.fadeIn;
  late final _fade = AnimationController(
    vsync: this,
    duration: _total,
    value: 1,
  );
  late Widget _shown = widget.child;

  /// The fade-out's share of [_total].
  static final _split =
      MetraMotion.fadeOut.inMicroseconds / _total.inMicroseconds;

  @override
  void didUpdateWidget(FadeThrough old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) {
      if (_fade.value >= _split) _shown = widget.child;
      return;
    }
    if (MetraMotion.reduced(context)) {
      _fade.value = 1;
      _shown = widget.child;
      return;
    }
    // Mid-way already faded out: go straight to fading the new one in.
    _fade.forward(from: _fade.value < _split ? _fade.value : 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    builder: (context, _) {
      final t = _fade.value;
      if (t >= 1) return _shown = widget.child;
      if (t < _split) return Opacity(opacity: 1 - t / _split, child: _shown);
      _shown = widget.child;
      return Opacity(opacity: (t - _split) / (1 - _split), child: _shown);
    },
  );
}
