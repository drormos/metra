import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/keep_awake.dart';
import 'package:metra/src/controller/metronome_controller.dart';

import '../audio/fake_click_output.dart';

void main() {
  test('awake only while playing, toggled once per change', () async {
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    final calls = <bool>[];
    keepAwakeWhilePlaying(metronome, (awake) async => calls.add(awake));

    metronome.setBpm(100); // not a start/stop change
    await metronome.play();
    metronome.setBpm(110);
    metronome.stop();
    expect(calls, [true, false]);
  });

  test('a failing platform call does not throw', () async {
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    keepAwakeWhilePlaying(metronome, (_) => Future.error('unsupported'));
    await metronome.play();
    metronome.stop();
  });
}
