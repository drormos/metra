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

    test('simple() accents the downbeat; subdivisions are soft', () {
      final pattern = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 2);
      expect(pattern.stepsPerBar, 6);
      expect(pattern.steps, [
        StepLevel.accent,
        StepLevel.soft,
        StepLevel.normal,
        StepLevel.soft,
        StepLevel.normal,
        StepLevel.soft,
      ]);
      expect(pattern.beatLevels, [
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
      ]);
    });

    test('time signature label', () {
      expect(const MetronomePattern.standard().timeSignature, '4/4');
      expect(
        MetronomePattern.simple(
          beatsPerBar: 7,
          stepsPerBeat: 1,
          beatUnit: 8,
        ).timeSignature,
        '7/8',
      );
    });

    test('cycleBeat goes normal, accent, silent, normal', () {
      var pattern = MetronomePattern.simple(beatsPerBar: 2, stepsPerBeat: 2);
      pattern = pattern.cycleBeat(1); // normal -> accent
      expect(pattern.beatLevels, [StepLevel.accent, StepLevel.accent]);
      pattern = pattern.cycleBeat(1); // accent -> silent
      expect(pattern.beatLevels, [StepLevel.accent, StepLevel.silent]);
      expect(pattern.steps[3], StepLevel.soft, reason: 'subdivision kept');
      pattern = pattern.cycleBeat(1); // silent -> normal
      expect(pattern.beatLevels, [StepLevel.accent, StepLevel.normal]);
    });

    test('withSubdivision keeps custom beat levels', () {
      final groupings = MetronomePattern.simple(
        beatsPerBar: 7,
        stepsPerBeat: 1,
        beatUnit: 8,
      ).cycleBeat(2).cycleBeat(4); // 2+2+3: accents on 1, 3, 5
      expect(
        groupings.beatLevels.where((l) => l == StepLevel.accent),
        hasLength(3),
      );
      final triplets = groupings.withSubdivision(3);
      expect(triplets.stepsPerBar, 21);
      expect(triplets.beatLevels, groupings.beatLevels);
      expect(triplets.timeSignature, '7/8');
    });

    test('JSON keeps the beat unit; old files default to 4', () {
      final sevenEight = MetronomePattern.simple(
        beatsPerBar: 7,
        stepsPerBeat: 1,
        beatUnit: 8,
      );
      expect(MetronomePattern.fromJson(sevenEight.toJson()), sevenEight);
      final old = const MetronomePattern.standard().toJson()
        ..remove('beatUnit');
      expect(MetronomePattern.fromJson(old), const MetronomePattern.standard());
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
