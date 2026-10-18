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

  group('per-step editing', () {
    final sixteenths = MetronomePattern.simple(beatsPerBar: 2, stepsPerBeat: 4);

    test('toggleCell switches one subdivision soft <-> silent', () {
      final gallop = sixteenths.toggleCell(0, 1);
      expect(gallop.steps.take(4), [
        StepLevel.accent,
        StepLevel.silent,
        StepLevel.soft,
        StepLevel.soft,
      ]);
      expect(gallop.toggleCell(0, 1), sixteenths);
      expect(() => sixteenths.toggleCell(0, 0), throwsRangeError);
      expect(() => sixteenths.toggleCell(0, 4), throwsRangeError);
    });

    test('cycleBeat leaves the beat\'s cells alone', () {
      final gallop = sixteenths.toggleCell(1, 2).cycleBeat(1);
      expect(gallop.steps.skip(4), [
        StepLevel.accent,
        StepLevel.soft,
        StepLevel.silent,
        StepLevel.soft,
      ]);
    });

    test('withBeats keeps existing beats and cells; new beats regular', () {
      final edited = sixteenths.toggleCell(0, 1).cycleBeat(1);
      final longer = edited.withBeats(3);
      expect(longer.steps.take(8), edited.steps);
      expect(longer.steps.skip(8), [
        StepLevel.normal,
        StepLevel.soft,
        StepLevel.soft,
        StepLevel.soft,
      ]);
      expect(longer.withBeats(1).steps, edited.steps.take(4));
      expect(edited.withBeats(2, beatUnit: 8).timeSignature, '2/8');
    });

    test('withSubdivision: same value keeps cells, a new one starts on', () {
      final gallop = sixteenths.toggleCell(0, 1);
      expect(gallop.withSubdivision(4), same(gallop));
      final triplets = gallop.withSubdivision(3);
      expect(triplets.steps.take(3), [
        StepLevel.accent,
        StepLevel.soft,
        StepLevel.soft,
      ]);
    });

    test('isDefault: accent on 1, everything else plain', () {
      expect(sixteenths.isDefault, isTrue);
      expect(sixteenths.toggleCell(1, 3).isDefault, isFalse);
      expect(sixteenths.cycleBeat(1).isDefault, isFalse);
    });
  });

  group('polyrhythm', () {
    final four = MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2);

    test('off by default; on with all pulses regular', () {
      expect(four.polyrhythm, 0);
      final three = four.withPolyrhythm(3);
      expect(three.polyStates, List.filled(3, StepLevel.normal));
      expect(three.meterLabel, '4/4 · 3');
      expect(four.meterLabel, '4/4');
      expect(three.pulseOffset(1), 8 / 3, reason: '4/3 beats, in steps');
    });

    test('the beat count itself is not a choice', () {
      expect(() => four.withPolyrhythm(4), throwsArgumentError);
      expect(() => four.withPolyrhythm(8), throwsArgumentError);
    });

    test('beats changed to equal the pulse count turn it off', () {
      final three = four.withPolyrhythm(3);
      expect(three.withBeats(3).polyrhythm, 0);
      expect(three.withBeats(5).polyrhythm, 3);
      expect(three.withSubdivision(3).polyrhythm, 3);
      expect(three.cycleBeat(1).polyrhythm, 3);
    });

    test('pulse taps cycle regular → accent → muted', () {
      final three = four.withPolyrhythm(3);
      expect(three.cyclePulse(1).polyStates[1], StepLevel.accent);
      expect(three.cyclePulse(1).cyclePulse(1).polyStates[1], StepLevel.silent);
      expect(three.cyclePulse(1).cyclePulse(1).cyclePulse(1), three);
    });

    test('survives JSON; older patterns load as off', () {
      final p = four.withPolyrhythm(5).cyclePulse(2);
      expect(MetronomePattern.fromJson(p.toJson()), p);
      final old = four.toJson()
        ..remove('polyrhythm')
        ..remove('polyStates');
      expect(MetronomePattern.fromJson(old).polyrhythm, 0);
      expect(MetronomePattern.fromJson(old), four);
    });
  });
}
