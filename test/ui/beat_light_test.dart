import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/beat_indicator.dart';

void main() {
  Duration ms(num v) => Duration(microseconds: (v * 1000).round());
  double at(num since, num interval) =>
      beatPulse(ms(since), ms(interval), reduced: false);

  test('up: starts 15 ms before the click, full 15 ms after it', () {
    expect(at(-16, 1000), 0);
    expect(at(-5, 1000), inExclusiveRange(0, 1));
    expect(at(0, 1000), greaterThan(0.8), reason: 'near full on the sound');
    expect(at(15, 1000), 1);
  });

  for (final (label, interval, lit) in [
    ('40 bpm quarters', 1500, 250),
    ('60 bpm quarters', 1000, 250),
    ('120 bpm quarters', 500, 175),
    ('120 bpm eighths', 250, 87.5),
    ('300 bpm 16ths', 50, 17.5),
  ]) {
    test('$label: lit ${lit}ms, down as long, then resting before the next '
        'click', () {
      // Full from 15 ms after the click for the lit time.
      expect(at(15 + lit * 0.99, interval), 1);
      // Then down over the same time (ease-in-out), never up again.
      final mid = at(15 + lit * 1.5, interval);
      expect(mid, inExclusiveRange(0, 1));
      expect(at(15 + lit * 2, interval), 0);
      // At rest before the next light rises.
      expect(15 + lit * 2, lessThanOrEqualTo(interval));
    });
  }

  test('"Remove animations": fully on from the click for the same time, '
      'then off, no ramp', () {
    double r(num since) => beatPulse(ms(since), ms(1000), reduced: true);
    expect(r(-1), 0);
    expect(r(0), 1);
    expect(r(264), 1);
    expect(r(266), 0);
  });
}
