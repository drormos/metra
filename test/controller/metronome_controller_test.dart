import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
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

    test('setPattern while playing restarts with the new pattern', () async {
      await controller.play();
      output.time = _ms * 1050;
      await controller.setPattern(waltz);
      expect(controller.isPlaying, isTrue);
      expect(output.clicks.first.cancelled, isTrue);
      expect(output.live.single.at, _ms * 1170);
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
}
