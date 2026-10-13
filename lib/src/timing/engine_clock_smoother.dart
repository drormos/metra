/// Smooths the engine clock for visuals.
///
/// `getEngineTime()` only advances once per mix buffer (~46 ms at 2048
/// frames), so read per frame it moves in jumps. Between jumps this
/// extrapolates with a local monotonic clock (the frame time), capped so a
/// stalled engine doesn't run away, and never moves backwards.
class EngineClockSmoother {
  /// Longer than any mix buffer we use; beyond this the engine is stalled.
  static const maxExtrapolation = Duration(milliseconds: 100);

  Duration? _base;
  Duration _baseAt = Duration.zero;
  Duration _last = Duration.zero;

  /// Estimated engine time, given the current engine clock reading and a
  /// local monotonic time.
  Duration estimate(Duration engineTime, Duration localTime) {
    if (engineTime != _base) {
      _base = engineTime;
      _baseAt = localTime;
    }
    var since = localTime - _baseAt;
    if (since > maxExtrapolation) since = maxExtrapolation;
    final estimate = engineTime + since;
    if (estimate > _last) _last = estimate;
    return _last;
  }
}
