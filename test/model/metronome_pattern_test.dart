import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/metronome_pattern.dart';

void main() {
  group('MetronomePattern', () {
    test('default is 4/4 quarters with accent on beat 1', () {
      const pattern = MetronomePattern.standard();
      expect(pattern.beatsPerBar, 4);
      expect(pattern.stepsPerBeat, 1);
      expect(pattern.stepsPerBar, 4);
      expect(pattern.steps, [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
        StepLevel.normal,
      ]);
    });

    test('simple() accents the downbeat and fills subdivisions', () {
      final pattern = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 2);
      expect(pattern.stepsPerBar, 6);
      expect(pattern.steps.first, StepLevel.accent);
      expect(pattern.steps.skip(1), everyElement(StepLevel.normal));
    });

    test('levelAt wraps absolute step indices into the bar', () {
      final pattern = MetronomePattern(
        beatsPerBar: 2,
        stepsPerBeat: 1,
        steps: const [StepLevel.accent, StepLevel.silent],
      );
      expect(pattern.levelAt(0), StepLevel.accent);
      expect(pattern.levelAt(1), StepLevel.silent);
      expect(pattern.levelAt(2), StepLevel.accent);
      expect(pattern.levelAt(7), StepLevel.silent);
    });

    test('isBeatStart marks the first step of each beat', () {
      final pattern = MetronomePattern.simple(beatsPerBar: 2, stepsPerBeat: 3);
      expect(List.generate(6, pattern.isBeatStart), [
        true,
        false,
        false,
        true,
        false,
        false,
      ]);
    });

    test('rejects step lists that do not fill the bar', () {
      expect(
        () => MetronomePattern(
          beatsPerBar: 4,
          stepsPerBeat: 1,
          steps: const [StepLevel.accent],
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive sizes', () {
      expect(
        () => MetronomePattern.simple(beatsPerBar: 0, stepsPerBeat: 1),
        throwsArgumentError,
      );
      expect(
        () => MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 0),
        throwsArgumentError,
      );
    });

    test('value equality', () {
      expect(
        MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 1),
        const MetronomePattern.standard(),
      );
      expect(
        MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 1).hashCode,
        const MetronomePattern.standard().hashCode,
      );
    });
  });
}
