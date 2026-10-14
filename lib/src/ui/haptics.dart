import 'package:flutter/services.dart';

/// The app's haptic vocabulary (ui-spec.md "Haptics"): only for touches,
/// never on the beat or automatic events. Standard platform types, so the
/// phone's own vibration setting decides whether they're felt, and
/// [enabled] ("Vibrate on touch") can only turn them off.
abstract final class Haptics {
  /// The app's "Vibrate on touch" setting.
  static bool enabled = true;

  /// Important stage actions: Start/Stop, a song change, lifting a row.
  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// Small adjustments and selections. Not selectionClick: that is
  /// Android's CLOCK_TICK, too faint to feel on many phones.
  static void tick() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Firmer than [medium]: the tempo ruler locking an exact value.
  static void firm() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  /// Whether going from [from] to [to] lands on or passes a multiple of 5
  /// (counting [to], not [from]), in either direction.
  static bool reachesFive(num from, num to) => to > from
      ? (to / 5).floor() > (from / 5).floor()
      : (to / 5).ceil() < (from / 5).ceil();
}
