import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/tuner_note.dart';

void main() {
  test('names the nearest note and octave', () {
    final a = TunerNote.fromHz(440);
    expect((a.name, a.octave), ('A', 4));
    expect(a.cents, closeTo(0, 1e-9));
    final e = TunerNote.fromHz(82.41);
    expect((e.name, e.octave), ('E', 2));
    expect(e.cents, closeTo(0, 0.1));
    expect(TunerNote.fromHz(261.63).name, 'C');
    expect(TunerNote.fromHz(261.63).octave, 4);
    expect(TunerNote.fromHz(116.54).name, 'A');
    expect(TunerNote.fromHz(116.54).sharp, isTrue);
    expect(TunerNote.fromHz(110).sharp, isFalse);
  });

  test('cents against the reference A4', () {
    expect(TunerNote.fromHz(442).cents, closeTo(7.85, 0.01));
    expect(TunerNote.fromHz(442, a4: 442).cents, closeTo(0, 1e-9));
    expect(TunerNote.fromHz(111.2).cents, closeTo(18.78, 0.01));
    // Halfway between A and A♯ rounds up to A♯ at −50.
    final mid = TunerNote.fromHz(440 * 1.0293022366);
    expect(mid.cents.abs(), closeTo(50, 0.01));
  });

  test('the cents line and what TalkBack says', () {
    final sharp = TunerNote.fromHz(110 * 1.00695555); // +12 cents
    expect(sharp.line, '+12 cents · 110.8 Hz');
    expect(sharp.spoken, 'A, 12 cents sharp');
    final flat = TunerNote.fromHz(110 / 1.00231316); // −4 cents
    expect(flat.line, '−4 cents · 109.7 Hz');
    expect(flat.spoken, 'A, 4 cents flat');
    final near = TunerNote.fromHz(110 * 1.0017); // +2.9 cents
    expect(near.inTune, isTrue);
    expect(near.line, 'In tune');
    expect(near.spoken, 'A, in tune');
    expect(TunerNote.fromHz(116.54).spoken, startsWith('A sharp, '));
  });
}
