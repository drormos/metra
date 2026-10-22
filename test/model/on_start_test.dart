import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/on_start.dart';

void main() {
  group('speed up', () {
    const up = OnStart(speedUp: true, changeBy: 5, every: 4);

    test('steps only on bar lines, every N bars, never at bar 0', () {
      expect(up.tempoAt(0, 0, 100), isNull);
      expect(up.tempoAt(3, 0, 100), isNull);
      expect(up.tempoAt(4, 1, 100), isNull, reason: 'not mid-bar');
      expect(up.tempoAt(4, 0, 100), 105);
      expect(up.tempoAt(8, 0, 117), 122, reason: 'from the tempo so far');
      expect(const OnStart().tempoAt(4, 0, 100), isNull, reason: 'off');
    });

    test('stops at Until and holds; slowing down too', () {
      final to = up.withUntil(112);
      expect(to.tempoAt(4, 0, 110), 112);
      expect(to.tempoAt(8, 0, 112), isNull);
      expect(to.tempoAt(8, 0, 130), isNull, reason: 'past it by hand');
      final down = up.copyWith(changeBy: -10).withUntil(95);
      expect(down.tempoAt(4, 0, 100), 95);
      expect(down.tempoAt(8, 0, 95), isNull);
      expect(up.copyWith(changeBy: 20).tempoAt(4, 0, 290), 300);
    });
  });

  test('stop after: the first bar line at or past the limit', () {
    const bars = OnStart(stopAfter: StopAfter.bars, stopBars: 8);
    expect(bars.endsAt(7, Duration.zero), isFalse);
    expect(bars.endsAt(8, Duration.zero), isTrue);
    const time = OnStart(
      stopAfter: StopAfter.time,
      stopTime: Duration(seconds: 30),
    );
    expect(time.endsAt(9, const Duration(seconds: 29)), isFalse);
    expect(time.endsAt(10, const Duration(seconds: 31)), isTrue);
    expect(const OnStart().endsAt(999, const Duration(hours: 1)), isFalse);
  });

  test('− / + grids', () {
    int up(int v, List<(int, int)> g, int max) => OnStart.stepUp(v, g, max);
    int down(int v, List<(int, int)> g, int min) => OnStart.stepDown(v, g, min);
    // Every: ±1 to 16, then ±4.
    expect(up(15, OnStart.everyGrid, 64), 16);
    expect(up(16, OnStart.everyGrid, 64), 20);
    expect(up(18, OnStart.everyGrid, 64), 20, reason: 'onto the grid');
    expect(down(20, OnStart.everyGrid, 1), 16);
    expect(down(16, OnStart.everyGrid, 1), 15);
    expect(up(64, OnStart.everyGrid, 64), 64);
    // Bars: ±1 to 16, ±4 to 64, then ±8.
    expect(up(64, OnStart.barsGrid, 999), 72);
    expect(down(72, OnStart.barsGrid, 1), 64);
    expect(down(64, OnStart.barsGrid, 1), 60);
    expect(up(996, OnStart.barsGrid, 999), 999);
    // Time: ±15 s to 2:00, ±30 s to 10:00, then ±1 min.
    expect(up(105, OnStart.timeGrid, 5940), 120);
    expect(up(120, OnStart.timeGrid, 5940), 150);
    expect(up(600, OnStart.timeGrid, 5940), 660);
    expect(down(660, OnStart.timeGrid, 15), 600);
    expect(down(125, OnStart.timeGrid, 15), 120);
    expect(down(15, OnStart.timeGrid, 15), 15);
    // Until: the ruler's grid of 5.
    expect(up(123, OnStart.untilGrid, 300), 125);
    expect(down(123, OnStart.untilGrid, 30), 120);
    // Change by skips 0.
    expect(OnStart.changeUp(-1), 1);
    expect(OnStart.changeDown(1), -1);
    expect(OnStart.changeUp(20), 20);
  });

  test('typed time fills from the right; seconds over 59 carry', () {
    expect(
      OnStart.parseTimeDigits('1230'),
      const Duration(minutes: 12, seconds: 30),
    );
    expect(
      OnStart.parseTimeDigits('12:30'),
      const Duration(minutes: 12, seconds: 30),
    );
    expect(OnStart.parseTimeDigits('45'), const Duration(seconds: 45));
    expect(
      OnStart.parseTimeDigits('175'),
      const Duration(minutes: 2, seconds: 15),
    );
    expect(OnStart.parseTimeDigits(''), isNull);
    expect(OnStart.clampTime(const Duration(seconds: 3)), OnStart.minTime);
    expect(OnStart.timeLabel(const Duration(minutes: 10)), '10:00');
  });

  test('progress line', () {
    const both = OnStart(
      speedUp: true,
      changeBy: 5,
      every: 8,
      until: 160,
      stopAfter: StopAfter.time,
      stopTime: Duration(minutes: 10),
    );
    expect(
      both.progress(
        bpm: 120,
        bar: 5,
        elapsed: const Duration(minutes: 5, seconds: 47, milliseconds: 200),
      ),
      '↗ +5 every 8 bars · next in 3 · 4:13 left',
    );
    expect(
      both.progress(bpm: 160, bar: 40, elapsed: Duration.zero),
      '↗ holding at 160 · 10:00 left',
    );
    expect(
      const OnStart(
        stopAfter: StopAfter.bars,
        stopBars: 16,
      ).progress(bpm: 100, bar: -1, elapsed: Duration.zero),
      '16 bars left',
    );
    expect(
      const OnStart(
        speedUp: true,
        changeBy: -2,
        every: 1,
      ).progress(bpm: 100, bar: 3, elapsed: Duration.zero),
      '↘ −2 every bar · next in 1',
    );
  });

  test('JSON round trip; bad values fall back', () {
    const all = OnStart(
      countIn: 2,
      speedUp: true,
      changeBy: -3,
      every: 12,
      until: 90,
      stopAfter: StopAfter.bars,
      stopBars: 100,
      stopTime: Duration(minutes: 7, seconds: 30),
    );
    expect(OnStart.fromJson(all.toJson()), all);
    expect(
      OnStart.fromJson({'countIn': 5, 'changeBy': 0, 'every': 500, 'until': 9}),
      const OnStart(every: 64, until: 30),
    );
  });
}
