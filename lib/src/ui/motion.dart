import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

/// Decides how a change of text in place shows (ui-spec.md "Text that
/// changes in place"): brightening from ~60% over [MetraMotion.brighten],
/// or at full at once when it comes within [MetraMotion.brightenSkip] of
/// the last change (fast tapping never pulses), while a ±button is held
/// or the ruler moves, or with "Remove animations" on. Call [next] once
/// per real change.
class BrightenGate {
  Duration? _last;

  Duration next(BuildContext context) {
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final last = _last;
    _last = now;
    if (last != null && now - last < MetraMotion.brightenSkip) {
      return Duration.zero;
    }
    if (MetraMotion.tempoMoving.value > 0) return Duration.zero;
    return MetraMotion.of(context, MetraMotion.brighten);
  }

  /// The new text's opacity [t] (0 → 1) into its brightening.
  static double opacity(double t) =>
      MetraMotion.brightenFrom +
      (1 - MetraMotion.brightenFrom) * MetraMotion.brightenCurve.transform(t);
}

/// A whole state that replaces another in place (the line under the BPM:
/// tempo name ↔ Revert · Save · Save as new ↔ hints ↔ "✓ Saved"): the
/// old is gone at once and the new snaps in at ~60%, brightening to full
/// ([BrightenGate]). A change of [value] plays it.
class BrightenSwap extends StatefulWidget {
  const BrightenSwap({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<BrightenSwap> createState() => _BrightenSwapState();
}

class _BrightenSwapState extends State<BrightenSwap>
    with SingleTickerProviderStateMixin {
  late final _brighten = AnimationController(vsync: this, value: 1);
  final _gate = BrightenGate();

  @override
  void didUpdateWidget(BrightenSwap old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    final duration = _gate.next(context);
    if (duration == Duration.zero) {
      _brighten.value = 1;
    } else {
      _brighten
        ..duration = duration
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _brighten.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _brighten,
    child: widget.child,
    builder: (context, child) => _brighten.value >= 1
        ? child!
        : Opacity(opacity: BrightenGate.opacity(_brighten.value), child: child),
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
