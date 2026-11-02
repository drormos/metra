import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/mic_input.dart';
import 'package:metra/src/controller/tuner_controller.dart';

import '../audio/fake_mic_input.dart';
import '../audio/pitch_detector_test.dart' show tone;

void main() {
  late FakeMicInput mic;
  late List<String> said;
  late TunerController tuner;

  TunerController make({int a4 = 440}) =>
      TunerController(mic, referenceA4: () => a4, announce: said.add);

  setUp(() {
    mic = FakeMicInput(state: MicPermission.granted);
    said = [];
    tuner = make();
  });

  tearDown(() => tuner.dispose());

  /// [seconds] of [hz] (or silence) in 1024-sample chunks; one unbroken
  /// wave across calls.
  var played = 0;
  void play(double? hz, double seconds) {
    final length = (48000 * seconds).round();
    final samples = hz == null
        ? Float32List(length)
        : tone(hz, 48000, length, start: played);
    played += length;
    for (var i = 0; i < samples.length; i += 1024) {
      final end = (i + 1024).clamp(0, samples.length);
      mic.push(Float32List.sublistView(samples, i, end));
    }
  }

  group('permission', () {
    test('first open asks once; allowed starts listening', () async {
      mic
        ..state = MicPermission.unknown
        ..answer = MicPermission.granted;
      await tuner.open();
      expect(mic.requests, 1);
      expect(tuner.permission, MicPermission.granted);
      expect(mic.running, isTrue);
    });

    test('refused: no microphone; Allow asks again', () async {
      mic
        ..state = MicPermission.unknown
        ..answer = MicPermission.denied;
      await tuner.open();
      expect(tuner.permission, MicPermission.denied);
      expect(mic.running, isFalse);
      mic.answer = MicPermission.granted;
      await tuner.allow();
      expect(mic.requests, 2);
      expect(mic.running, isTrue);
    });

    test('blocked: Allow opens the app settings; allowed there, it '
        'listens on return', () async {
      mic.state = MicPermission.blocked;
      await tuner.open();
      expect(mic.requests, 0, reason: 'only asks the first time');
      await tuner.allow();
      expect(mic.settingsOpened, 1);
      expect(mic.requests, 0);
      await tuner.paused();
      mic.state = MicPermission.granted;
      await tuner.resumed();
      expect(tuner.permission, MicPermission.granted);
      expect(mic.running, isTrue);
    });

    test('allowed before: no dialog', () async {
      await tuner.open();
      expect(mic.requests, 0);
      expect(mic.running, isTrue);
    });
  });

  group('the microphone runs only while the page is in front', () {
    test('stops on close and in the background, restarts on return', () async {
      await tuner.open();
      expect(TunerController.isOpen.value, isTrue);
      await tuner.paused();
      expect(mic.running, isFalse);
      await tuner.resumed();
      expect(mic.running, isTrue);
      await tuner.close();
      expect(mic.running, isFalse);
      expect(TunerController.isOpen.value, isFalse);
      await tuner.resumed();
      expect(mic.running, isFalse, reason: 'closed stays closed');
    });

    test('dispose stops it', () async {
      final other = make();
      await other.open();
      other.dispose();
      expect(mic.running, isFalse);
      expect(TunerController.isOpen.value, isFalse);
    });
  });

  group('reading', () {
    test('a note reads its name, octave and cents against A4', () async {
      await tuner.open();
      play(110, 0.3);
      expect(tuner.note!.name, 'A');
      expect(tuner.note!.octave, 2);
      expect(tuner.note!.inTune, isTrue);
      final sharp = make(a4: 430);
      await sharp.open();
      play(110, 0.3);
      expect(sharp.note!.cents, closeTo(39.8, 1));
      sharp.dispose();
    });

    test('silence holds the last note for a second, then "–"', () async {
      await tuner.open();
      play(110, 0.3);
      expect(tuner.note, isNotNull);
      play(null, 0.8);
      expect(tuner.note?.name, 'A', reason: 'a short gap holds the note');
      play(null, 0.4);
      expect(tuner.note, isNull);
    });

    test('nothing before a full frame; leaving clears the note', () async {
      await tuner.open();
      play(110, 0.05);
      expect(tuner.note, isNull);
      play(110, 0.3);
      await tuner.paused();
      expect(tuner.note, isNull);
    });
  });

  test('TalkBack hears a settled note, at most once a second', () async {
    await tuner.open();
    play(110, 0.4);
    expect(said, isEmpty, reason: 'not settled yet');
    play(110, 0.3);
    expect(said, ['A, in tune']);
    play(110, 2);
    expect(said, ['A, in tune'], reason: 'the same line once');
    play(146.83, 0.3);
    play(146.83, 0.4);
    expect(said, ['A, in tune', 'D, in tune']);
  });
}
