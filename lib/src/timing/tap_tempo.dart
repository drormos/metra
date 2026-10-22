/// Tap tempo from monotonic tap times (pass a `Stopwatch.elapsed`).
///
/// Uses the intervals between the last 4 taps, drops any more than 30% off
/// their median, and averages the rest. A gap over 2 s, or over twice the
/// last interval if that's longer (slow tempos near 30 bpm), starts over.
class TapTempo {
  TapTempo({required this.minBpm, required this.maxBpm});

  final int minBpm;
  final int maxBpm;

  static const _maxTaps = 4;
  static const _outlierRatio = 0.3;
  static const _resetAfter = Duration(seconds: 2);

  final List<Duration> _taps = [];

  Duration get _resetWindow {
    if (_taps.length < 2) return _resetAfter;
    final last = _taps[_taps.length - 1] - _taps[_taps.length - 2];
    return last * 2 > _resetAfter ? last * 2 : _resetAfter;
  }

  /// Records a tap at [time]; returns the tapped tempo, or null after the
  /// first tap of a sequence.
  int? tap(Duration time) {
    if (_taps.isNotEmpty && time - _taps.last > _resetWindow) _taps.clear();
    _taps.add(time);
    if (_taps.length > _maxTaps) _taps.removeAt(0);
    if (_taps.length < 2) return null;

    final intervals = [
      for (var i = 1; i < _taps.length; i++)
        (_taps[i] - _taps[i - 1]).inMicroseconds,
    ];
    final sorted = [...intervals]..sort();
    final mid = sorted.length ~/ 2;
    final median = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    final kept = intervals
        .where((i) => (i - median).abs() <= median * _outlierRatio)
        .toList();
    // Nothing agrees: trust the latest interval (the player changed tempo).
    final average = kept.isEmpty
        ? intervals.last.toDouble()
        : kept.reduce((a, b) => a + b) / kept.length;

    final bpm = (Duration.microsecondsPerMinute / average).round();
    return bpm.clamp(minBpm, maxBpm);
  }
}
