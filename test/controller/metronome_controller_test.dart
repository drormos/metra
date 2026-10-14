import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/metronome_pattern.dart';

import '../audio/fake_click_output.dart';

const _ms = Duration(milliseconds: 1);

void main() {
  late FakeClickOutput output;
  late MetronomeController controller;
  late int notifications;

  setUp(() {
    output = FakeClickOutput()..time = _ms * 1000;
    controller = MetronomeController(output);
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  tearDown(() => controller.dispose());

  test('defaults', () {
    expect(controller.bpm, 120);
    expect(controller.isPlaying, isFalse);
    expect(controller.pattern, const MetronomePattern.standard());
    expect(controller.audioError, isNull);
  });

  group('bpm', () {
    test('setBpm clamps to 30..300 and notifies', () {
      controller.setBpm(500);
      expect(controller.bpm, MetronomeController.maxBpm);
      controller.setBpm(1);
      expect(controller.bpm, MetronomeController.minBpm);
      expect(notifications, 2);
    });

    test('nudge adds to the current tempo, clamped', () {
      controller.nudge(10);
      expect(controller.bpm, 130);
      controller.nudge(-1);
      expect(controller.bpm, 129);
      controller.setBpm(295);
      controller.nudge(10);
      expect(controller.bpm, 300);
    });

    test('an unchanged value does not notify', () {
      controller.setBpm(120);
      controller.setBpm(300);
      controller.nudge(1);
      expect(notifications, 1);
    });

    test('while playing reschedules at the new tempo', () async {
      await controller.play();
      output.time = _ms * 1050; // first click at 1120 still pending
      controller.setBpm(60);
      expect(output.clicks.first.cancelled, isTrue);
      expect(output.liveTimes, [_ms * 1120]);
    });
  });

  group('play / stop', () {
    test('play starts the scheduler and notifies immediately', () async {
      final future = controller.play();
      expect(controller.isPlaying, isTrue);
      expect(notifications, 1);
      await future;
      expect(output.prepared, isTrue);
      expect(output.clicks, isNotEmpty);
    });

    test('play while playing is a no-op', () async {
      await controller.play();
      final count = output.clicks.length;
      await controller.play();
      expect(output.clicks.length, count);
    });

    test('stop cancels pending clicks', () async {
      await controller.play();
      controller.stop();
      expect(controller.isPlaying, isFalse);
      expect(output.live, isEmpty);
      expect(output.releaseCount, 1);
    });

    test('toggle alternates', () async {
      await controller.toggle();
      expect(controller.isPlaying, isTrue);
      await controller.toggle();
      expect(controller.isPlaying, isFalse);
    });

    test('a device error on play reports and stays stopped', () async {
      output.deviceError = 'no device';
      await controller.play();
      expect(controller.isPlaying, isFalse);
      expect(controller.audioError, 'no device');

      output.deviceError = null;
      await controller.play();
      expect(controller.isPlaying, isTrue);
      expect(controller.audioError, isNull);
    });
  });

  group('pattern', () {
    final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

    test('setPattern while stopped just stores it', () {
      controller.setPattern(waltz);
      expect(controller.pattern, waltz);
      expect(output.clicks, isEmpty);
      expect(notifications, 1);
    });

    test('setPattern while playing switches at the next bar', () async {
      await controller.play(); // 1120, 1620, 2120, 2620 | 3120
      output.time = _ms * 1300;
      controller.setPattern(waltz);
      expect(controller.isPlaying, isTrue);
      expect(controller.pattern, waltz);
      expect(output.clicks.first.cancelled, isFalse);
    });

    test('switchTo loads tempo and pattern', () async {
      controller.switchTo(bpm: 90, pattern: waltz);
      expect(controller.bpm, 90);
      expect(controller.pattern, waltz);
      expect(notifications, 1);
      controller.switchTo(bpm: 999, pattern: waltz);
      expect(controller.bpm, MetronomeController.maxBpm);
    });
  });

  group('lifecycle', () {
    test('backgrounding extends the lookahead, resuming restores it', () async {
      await controller.play();
      controller.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(
        output.liveTimes.last,
        greaterThan(output.time + MetronomeController.foregroundLookahead),
      );

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(
        controller.lookaheadForTesting,
        MetronomeController.foregroundLookahead,
      );
    });

    test('the lookahead applies to sessions started in background', () async {
      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      await controller.play();
      expect(
        controller.lookaheadForTesting,
        MetronomeController.backgroundLookahead,
      );
    });
  });

  group('device failures', () {
    test('recovers automatically', () async {
      output.failures.add(null);
      await pumpEventQueue();
      expect(output.recoverCount, 1);
      expect(controller.audioError, isNull);
    });

    test('reports when recovery fails', () async {
      output.deviceError = 'gone';
      output.failures.add(null);
      await pumpEventQueue();
      expect(controller.audioError, 'gone');
      expect(notifications, greaterThan(0));
    });
  });

  test('dispose stops playback', () async {
    final local = MetronomeController(output);
    await local.play();
    local.dispose();
    expect(output.live, isEmpty);
  });

  group('visual sync', () {
    test('visual offset defaults to zero and clamps', () {
      expect(controller.visualOffset, Duration.zero);
      controller.setVisualOffset(_ms * 9999);
      expect(controller.visualOffset, MetronomeController.maxVisualOffset);
      controller.setVisualOffset(_ms * -9999);
      expect(controller.visualOffset, MetronomeController.minVisualOffset);
    });

    test('no step while stopped', () {
      expect(controller.visualStepAt(Duration.zero), isNull);
    });

    test('shows a step once engine time passes step time + offset', () async {
      controller.setVisualOffset(_ms * 50);
      await controller.play(); // first step at 1120
      output.time = _ms * 1150;
      expect(controller.visualStepAt(Duration.zero), isNull);
      output.time = _ms * 1170;
      expect(controller.visualStepAt(_ms * 20)?.index, 0);
    });

    test('extrapolates between engine clock updates', () async {
      controller.setVisualOffset(Duration.zero);
      await controller.play();
      output.time = _ms * 1100;
      expect(controller.visualStepAt(Duration.zero), isNull);
      // Engine clock hasn't moved, but 30 ms of frames have passed.
      expect(controller.visualStepAt(_ms * 30)?.index, 0);
    });
  });

  group('quick rhythm edits', () {
    test('cycleBeat changes the pattern at once', () {
      controller.cycleBeat(1);
      expect(controller.pattern.beatLevels[1], StepLevel.accent);
      expect(notifications, 1);
    });

    test('setSubdivision keeps accents; same value is a no-op', () {
      controller.cycleBeat(2);
      controller.setSubdivision(3);
      expect(controller.pattern.stepsPerBeat, 3);
      expect(controller.pattern.beatLevels[2], StepLevel.accent);
      final before = notifications;
      controller.setSubdivision(3);
      expect(notifications, before);
    });

    test('setMeter keeps beat states and the subdivision', () {
      controller.setSubdivision(2);
      controller.cycleBeat(1); // beat 2 accented
      controller.setMeter(7, 8);
      expect(controller.pattern.timeSignature, '7/8');
      expect(controller.pattern.stepsPerBeat, 2);
      expect(controller.pattern.beatLevels.take(3), [
        StepLevel.accent,
        StepLevel.accent,
        StepLevel.normal,
      ]);
      controller.setMeter(3, 4);
      expect(controller.pattern.beatLevels, [
        StepLevel.accent,
        StepLevel.accent,
        StepLevel.normal,
      ]);
    });

    test('while playing, a beat tap is heard from the next click', () async {
      await controller.play(); // first click at 1120, still open
      controller.cycleBeat(0); // accent -> silent
      expect(output.clicks.first.cancelled, isTrue);
      expect(output.live, isEmpty, reason: 'beat 1 is now silent');
    });
  });

  test('volumes reach the output and notify once', () {
    const quiet = ClickVolumes(accent: 0.6, beat: 0.5, subdivision: 0.2);
    controller.setVolumes(quiet);
    controller.setVolumes(quiet);
    expect(controller.volumes, quiet);
    expect(output.currentVolumes, quiet);
    expect(notifications, 1);
  });

  group('click sound', () {
    test('while stopped every tap plays the sample', () {
      controller.setClickSound(ClickSound.woodblock);
      expect(controller.clickSound, ClickSound.woodblock);
      expect(output.currentSound, ClickSound.woodblock);
      expect(output.previewCount, 1);
      expect(notifications, 1);
      controller.setClickSound(ClickSound.woodblock);
      expect(output.previewCount, 2, reason: 'the same sound plays again');
      expect(notifications, 1, reason: 'but nothing changed');
      controller.setClickSound(ClickSound.beep, preview: false);
      expect(output.previewCount, 2, reason: 'restoring a session: silent');
    });

    test('no preview while playing (the clicks are the preview)', () async {
      await controller.play();
      controller.setClickSound(ClickSound.beep);
      expect(output.currentSound, ClickSound.beep);
      expect(output.previewCount, 0);
    });
  });

  group('applyEdit (a saved song, while playing)', () {
    // Playing from 1120 at 120 bpm; at 1500 beat 2 is next, at 1620.
    Future<void> playUntil1500() async {
      await controller.play();
      output.time = _ms * 1500;
    }

    FakeClick? clickAt(int ms) =>
        output.live.where((c) => c.at == _ms * ms).firstOrNull;

    test('nothing changed: nothing happens', () async {
      await playUntil1500();
      final before = output.clicks.length;
      notifications = 0;
      controller.applyEdit(
        bpm: 120,
        pattern: const MetronomePattern.standard(),
      );
      expect(output.clicks, hasLength(before));
      expect(notifications, 0);
    });

    test('tempo: no restart on beat 1', () async {
      await playUntil1500();
      controller.applyEdit(
        bpm: 100,
        pattern: const MetronomePattern.standard(),
      );
      expect(controller.bpm, 100);
      expect(clickAt(1560), isNull, reason: 'no restart one guard later');
    });

    test('accents: from the next click, bar kept', () async {
      await playUntil1500();
      controller.applyEdit(
        bpm: 120,
        pattern: const MetronomePattern.standard().cycleBeat(1),
      );
      expect(clickAt(1620)?.level, StepLevel.accent, reason: 'beat 2');
    });

    test('subdivision: from the next beat, bar kept', () async {
      await playUntil1500();
      controller.applyEdit(
        bpm: 120,
        pattern: const MetronomePattern.standard().withSubdivision(2),
      );
      expect(controller.pattern.stepsPerBeat, 2);
      expect(clickAt(1620)?.level, StepLevel.normal, reason: 'still beat 2');
    });

    test('time signature: the next beat starts a bar', () async {
      await playUntil1500();
      controller.applyEdit(
        bpm: 120,
        pattern: const MetronomePattern.standard().withBeats(3),
      );
      expect(controller.pattern.timeSignature, '3/4');
      expect(clickAt(1620)?.level, StepLevel.accent, reason: 'beat 1');
    });
  });

  group('song editor preview', () {
    final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

    test('from stopped: plays the draft; ending stops and restores', () async {
      await controller.preview(bpm: 90, pattern: waltz);
      expect(controller.isPlaying, isTrue);
      expect(controller.bpm, 90);
      expect(controller.previewing, isTrue);
      controller.endPreview();
      expect(controller.isPlaying, isFalse);
      expect(controller.bpm, 120);
      expect(controller.pattern, const MetronomePattern.standard());
      expect(controller.previewing, isFalse);
    });

    test('from playing: ending resumes the main click', () async {
      await controller.play();
      await controller.preview(bpm: 90, pattern: waltz);
      controller.stop(); // the editor's Stop
      await controller.preview(bpm: 95, pattern: waltz); // again
      controller.endPreview();
      expect(controller.isPlaying, isTrue);
      expect(controller.bpm, 120, reason: 'the first snapshot is kept');
      expect(controller.pattern, const MetronomePattern.standard());
    });

    test('no preview: ending does nothing', () async {
      await controller.play();
      notifications = 0;
      controller.endPreview();
      expect(controller.isPlaying, isTrue);
      expect(notifications, 0);
    });
  });

  group('loadSong', () {
    final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

    test('while stopped only loads', () {
      controller.loadSong(bpm: 90, pattern: waltz);
      expect(controller.bpm, 90);
      expect(controller.pattern, waltz);
      expect(controller.isPlaying, isFalse);
      expect(output.clicks, isEmpty);
    });

    test('while playing restarts on beat 1 straight away', () async {
      await controller.play(); // first click at 1120
      output.time = _ms * 1500;
      controller.loadSong(bpm: 60, pattern: waltz);
      expect(controller.isPlaying, isTrue);
      final restart = output.live.last;
      expect(restart.at, _ms * 1560);
      expect(restart.level, StepLevel.accent);
    });
  });
}
