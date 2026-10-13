import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/timing/engine_clock_smoother.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late EngineClockSmoother smoother;

  setUp(() => smoother = EngineClockSmoother());

  test('extrapolates between engine clock steps', () {
    expect(smoother.estimate(_ms * 1000, _ms * 0), _ms * 1000);
    expect(smoother.estimate(_ms * 1000, _ms * 16), _ms * 1016);
    expect(smoother.estimate(_ms * 1000, _ms * 33), _ms * 1033);
    // Engine clock jumps a buffer; re-base on the new reading.
    expect(smoother.estimate(_ms * 1046, _ms * 50), _ms * 1046);
    expect(smoother.estimate(_ms * 1046, _ms * 66), _ms * 1062);
  });

  test('never runs backwards', () {
    smoother.estimate(_ms * 1000, Duration.zero);
    expect(smoother.estimate(_ms * 1000, _ms * 40), _ms * 1040);
    // New reading lower than what we extrapolated: hold.
    expect(smoother.estimate(_ms * 1030, _ms * 41), _ms * 1040);
    expect(smoother.estimate(_ms * 1030, _ms * 60), _ms * 1049);
  });

  test('caps extrapolation when the engine clock stalls', () {
    smoother.estimate(_ms * 1000, Duration.zero);
    expect(
      smoother.estimate(_ms * 1000, _ms * 5000),
      _ms * 1000 + EngineClockSmoother.maxExtrapolation,
    );
  });
}
