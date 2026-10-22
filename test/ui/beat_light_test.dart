import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/beat_indicator.dart';

void main() {
  Duration ms(num v) => Duration(microseconds: (v * 1000).round());

  test('fully on at the click, never before (no fade-in)', () {
    expect(beatLight(Duration.zero, ms(500), reduced: false), 1);
    expect(beatLight(ms(-1), ms(500), reduced: false), 0);
  });

  test('slow tempo: back to rest over 90 ms, falling all the way', () {
    expect(beatLight(ms(45), ms(500), reduced: false), inExclusiveRange(0, 1));
    expect(beatLight(ms(89), ms(500), reduced: false), lessThan(0.05));
    expect(beatLight(ms(90), ms(500), reduced: false), 0);
  });

  test('300 bpm in 16ths (50 ms apart): gone within a third of the gap, '
      'so it never blurs into the next click', () {
    expect(beatLight(ms(10), ms(50), reduced: false), greaterThan(0));
    expect(beatLight(ms(50 / 3 + 0.1), ms(50), reduced: false), 0);
  });

  test('"Remove animations": on until the next click, then off', () {
    expect(beatLight(ms(49), ms(50), reduced: true), 1);
    expect(beatLight(ms(50), ms(50), reduced: true), 0);
  });
}
