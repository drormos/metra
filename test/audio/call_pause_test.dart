import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/call_pause.dart';
import 'package:metra/src/controller/metronome_controller.dart';

import 'fake_click_output.dart';

void main() {
  late MetronomeController controller;
  late CallPause calls;

  setUp(() {
    controller = MetronomeController(FakeClickOutput());
    calls = CallPause(controller);
  });
  tearDown(() => controller.dispose());

  test('a call stops the click; its end starts it again', () async {
    await controller.play();
    await calls.callChanged(active: true);
    expect(controller.isPlaying, isFalse);
    await calls.callChanged(active: false);
    expect(controller.isPlaying, isTrue);
  });

  test('stopped before the call: stays stopped after', () async {
    await calls.callChanged(active: true);
    await calls.callChanged(active: false);
    expect(controller.isPlaying, isFalse);
  });

  test('started and stopped during the call: no resume', () async {
    await controller.play();
    await calls.callChanged(active: true);
    await controller.play();
    controller.stop();
    await calls.callChanged(active: false);
    expect(controller.isPlaying, isFalse);
  });

  test('repeated call states change nothing', () async {
    await controller.play();
    await calls.callChanged(active: true);
    await calls.callChanged(active: true);
    await calls.callChanged(active: false);
    expect(controller.isPlaying, isTrue);
  });
}
