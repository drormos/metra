import 'package:flutter/foundation.dart';

import '../audio/click_scheduler.dart';

/// "Stop after": off, after a number of bars, or after a length of time.
enum StopAfter { off, bars, time }

/// What happens over time after Start (ui-spec.md "When I press Start"):
/// a count-in, speed up, stop after. Belongs to a song like its tempo
/// (Free play has its own). Speed up and stop after make a "run": each
/// tempo change and the stop land on bar lines, counted from the song's
/// beat 1 (count-in bars don't count).
@immutable
class OnStart implements RunPlan {
  const OnStart({
    this.countIn = 0,
    this.speedUp = false,
    this.changeBy = 5,
    this.every = 8,
    this.until,
    this.stopAfter = StopAfter.off,
    this.stopBars = 32,
    this.stopTime = const Duration(minutes: 5),
  });

  static const off = OnStart();

  /// Bars of count-in: 0 (off), 1 or 2.
  final int countIn;
  static const countInChoices = [0, 1, 2];

  final bool speedUp;

  /// Bpm added at each step: −20 … −1 or 1 … 20 (negative slows down).
  final int changeBy;

  /// Bars between steps, 1–64.
  final int every;

  /// The tempo speed up stops at and holds; null is "No limit".
  final int? until;

  final StopAfter stopAfter;

  /// Stop after this many bars (1–999) or this long (0:15–99:00).
  final int stopBars;
  final Duration stopTime;

  static const minChange = -20, maxChange = 20;
  static const minEvery = 1, maxEvery = 64;
  static const minBars = 1, maxBars = 999;
  static const minTime = Duration(seconds: 15);
  static const maxTime = Duration(minutes: 99);

  /// Anything on: the stopwatch button is red.
  bool get anyOn => countIn > 0 || runs;

  /// Speed up or stop after: a run, with progress under the BPM.
  bool get runs => speedUp || stopAfter != StopAfter.off;

  OnStart copyWith({
    int? countIn,
    bool? speedUp,
    int? changeBy,
    int? every,
    StopAfter? stopAfter,
    int? stopBars,
    Duration? stopTime,
  }) => OnStart(
    countIn: countIn ?? this.countIn,
    speedUp: speedUp ?? this.speedUp,
    changeBy: changeBy ?? this.changeBy,
    every: every ?? this.every,
    until: until,
    stopAfter: stopAfter ?? this.stopAfter,
    stopBars: stopBars ?? this.stopBars,
    stopTime: stopTime ?? this.stopTime,
  );

  /// [until] may be null ("No limit"), so it has its own copy.
  OnStart withUntil(int? until) => OnStart(
    countIn: countIn,
    speedUp: speedUp,
    changeBy: changeBy,
    every: every,
    until: until,
    stopAfter: stopAfter,
    stopBars: stopBars,
    stopTime: stopTime,
  );

  /// The tempo from beat [beat] of song bar [bar] (both from 0) on, given
  /// the tempo so far, or null to keep it. Speed up steps only on bar
  /// lines, every [every] bars, toward [until], where it holds.
  @override
  double? tempoAt(int bar, int beat, double bpm) {
    if (!speedUp || beat != 0 || bar == 0 || bar % every != 0) return null;
    var next = bpm + changeBy;
    final limit = until;
    if (limit != null) {
      if (changeBy > 0 ? bpm >= limit : bpm <= limit) return null; // holds
      next = changeBy > 0
          ? (next > limit ? limit.toDouble() : next)
          : (next < limit ? limit.toDouble() : next);
    }
    next = next.clamp(30, 300).toDouble();
    return next == bpm ? null : next;
  }

  /// Whether the run ends at the line starting song bar [bar] (from 0),
  /// [elapsed] after the song's beat 1: the first bar line at or past the
  /// limit, never mid-bar.
  @override
  bool endsAt(int bar, Duration elapsed) => switch (stopAfter) {
    StopAfter.off => false,
    StopAfter.bars => bar >= stopBars,
    StopAfter.time => elapsed >= stopTime,
  };

  /// The line under the BPM during a run (ui-spec.md "While playing"):
  /// "↗ +5 every 8 bars · next in 3 · 4:12 left", at tempo [bpm], in song
  /// bar [bar] (from 0; −1 before beat 1), [elapsed] after beat 1.
  String progress({
    required int bpm,
    required int bar,
    required Duration elapsed,
  }) {
    final at = bar < 0 ? 0 : bar;
    final arrow = changeBy > 0 ? '↗' : '↘';
    final limit = until;
    return [
      if (speedUp)
        if (limit != null && (changeBy > 0 ? bpm >= limit : bpm <= limit))
          '$arrow holding at $limit'
        else
          '$arrow ${changeLabel(changeBy)} every '
              '${every == 1 ? 'bar' : '$every bars'} · '
              'next in ${every - at % every}',
      if (stopAfter == StopAfter.bars) '${barsLabel(stopBars - at)} left',
      if (stopAfter == StopAfter.time)
        '${timeLabel(_ceilSeconds(stopTime - elapsed))} left',
    ].join(' · ');
  }

  static Duration _ceilSeconds(Duration d) => d <= Duration.zero
      ? Duration.zero
      : Duration(seconds: (d.inMilliseconds + 999) ~/ 1000);

  // Value grids for − / + (ui-spec.md "Editing the values").
  static const everyGrid = [(16, 1), (maxEvery, 4)];
  static const barsGrid = [(16, 1), (64, 4), (maxBars, 8)];
  static const untilGrid = [(300, 5)];
  // In seconds.
  static const timeGrid = [(120, 15), (600, 30), (5940, 60)];

  /// The next value up on [grid] (each entry: the step used below its
  /// limit), at most [max].
  static int stepUp(int v, List<(int, int)> grid, int max) {
    final step = grid.firstWhere((g) => v < g.$1, orElse: () => grid.last).$2;
    final next = (v ~/ step + 1) * step;
    return next > max ? max : next;
  }

  /// The next value down on [grid], at least [min].
  static int stepDown(int v, List<(int, int)> grid, int min) {
    final step = grid.firstWhere((g) => v <= g.$1, orElse: () => grid.last).$2;
    final next = ((v - 1) ~/ step) * step;
    return next < min ? min : next;
  }

  /// Change by skips 0: −1 ↔ +1.
  static int changeUp(int v) =>
      v >= maxChange ? maxChange : (v == -1 ? 1 : v + 1);
  static int changeDown(int v) =>
      v <= minChange ? minChange : (v == 1 ? -1 : v - 1);

  /// "+5", "−5".
  static String changeLabel(int v) => v > 0 ? '+$v' : '−${-v}';

  /// "1 bar", "8 bars".
  static String barsLabel(int n) => n == 1 ? '1 bar' : '$n bars';

  /// "10:00", "0:45".
  static String timeLabel(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Typed time digits, filled from the right like a microwave:
  /// "1230" → 12:30 (seconds past 59 carry over), or null with no digits.
  static Duration? parseTimeDigits(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    final last = digits.length > 4
        ? digits.substring(digits.length - 4)
        : digits;
    final n = int.parse(last);
    return Duration(minutes: n ~/ 100, seconds: n % 100);
  }

  static int clampInt(int v, int min, int max) =>
      v < min ? min : (v > max ? max : v);

  static Duration clampTime(Duration d) =>
      d < minTime ? minTime : (d > maxTime ? maxTime : d);

  Map<String, Object?> toJson() => {
    'countIn': countIn,
    'speedUp': speedUp,
    'changeBy': changeBy,
    'every': every,
    'until': until,
    'stopAfter': stopAfter.name,
    'stopBars': stopBars,
    'stopTimeS': stopTime.inSeconds,
  };

  /// Missing or bad fields fall back to their defaults.
  factory OnStart.fromJson(Map<String, Object?> json) {
    T read<T>(String key, T fallback) =>
        json[key] is T ? json[key] as T : fallback;
    const d = OnStart.off;
    final change = read('changeBy', d.changeBy);
    return OnStart(
      countIn: countInChoices.contains(json['countIn'])
          ? read('countIn', 0)
          : 0,
      speedUp: read('speedUp', false),
      changeBy: change == 0
          ? d.changeBy
          : clampInt(change, minChange, maxChange),
      every: clampInt(read('every', d.every), minEvery, maxEvery),
      until: switch (json['until']) {
        final int v => clampInt(v, 30, 300),
        _ => null,
      },
      stopAfter:
          StopAfter.values.asNameMap()[json['stopAfter']] ?? StopAfter.off,
      stopBars: clampInt(read('stopBars', d.stopBars), minBars, maxBars),
      stopTime: clampTime(
        Duration(seconds: read('stopTimeS', d.stopTime.inSeconds)),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnStart &&
      other.countIn == countIn &&
      other.speedUp == speedUp &&
      other.changeBy == changeBy &&
      other.every == every &&
      other.until == until &&
      other.stopAfter == stopAfter &&
      other.stopBars == stopBars &&
      other.stopTime == stopTime;

  @override
  int get hashCode => Object.hash(
    countIn,
    speedUp,
    changeBy,
    every,
    until,
    stopAfter,
    stopBars,
    stopTime,
  );
}
