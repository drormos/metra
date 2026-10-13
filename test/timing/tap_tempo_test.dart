import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/timing/tap_tempo.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late TapTempo tapTempo;

  setUp(() => tapTempo = TapTempo(minBpm: 30, maxBpm: 300));

  /// Taps at the given absolute times (ms); returns the last result.
  int? tapAt(List<int> times) {
    int? bpm;
    for (final t in times) {
      bpm = tapTempo.tap(_ms * t);
    }
    return bpm;
  }

  test('first tap gives no tempo', () {
    expect(tapTempo.tap(Duration.zero), isNull);
  });

  test('second tap gives the tempo of one interval', () {
    expect(tapAt([0, 500]), 120);
  });

  test('averages the last 3 intervals (4 taps)', () {
    // Intervals 600, 500, 500, 520: only the last three count.
    // 60000 / 506.67 = 118.4
    expect(tapAt([0, 600, 1100, 1600, 2120]), 118);
  });

  test('drops an outlier interval', () {
    // 500, 500, 900 (a hesitation): 900 is >30% off the median.
    expect(tapAt([0, 500, 1000, 1900]), 120);
  });

  test('follows a deliberate tempo change once taps agree', () {
    expect(tapAt([0, 500, 1000, 1500]), 120);
    expect(tapAt([2250, 3000, 3750]), 80);
  });

  test('when intervals all disagree, uses the latest', () {
    // 300 and 950 are both >30% off their median: 60000 / 950 = 63.2
    expect(tapAt([0, 300, 1250]), 63);
  });

  test('resets after 2 s without a tap', () {
    expect(tapAt([0, 500, 1000]), 120);
    expect(tapTempo.tap(_ms * 3100), isNull);
    expect(tapTempo.tap(_ms * 3850), 80);
  });

  test('clamps to the tempo range', () {
    expect(tapAt([0, 50]), 300);
    tapTempo = TapTempo(minBpm: 30, maxBpm: 300);
    expect(tapAt([0, 1999]), 30);
  });

  test('rounds to the nearest bpm', () {
    // 60000 / 461 = 130.15
    expect(tapAt([0, 461]), 130);
  });
}
