import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/metronome_audio_handler.dart';
import 'package:metra/src/controller/metronome_controller.dart';

import 'fake_click_output.dart';

void main() {
  late MetronomeController controller;
  late MetronomeAudioHandler handler;

  setUp(() {
    controller = MetronomeController(FakeClickOutput());
    handler = MetronomeAudioHandler(controller);
  });

  tearDown(() => controller.dispose());

  test('starts idle with a play control', () {
    final state = handler.playbackState.value;
    expect(state.playing, isFalse);
    expect(state.processingState, AudioProcessingState.idle);
    expect(state.controls, [MediaControl.play]);
  });

  test('notification play/stop drive the controller', () async {
    await handler.play();
    expect(controller.isPlaying, isTrue);
    await handler.pause();
    expect(controller.isPlaying, isFalse);
    await handler.play();
    await handler.stop();
    expect(controller.isPlaying, isFalse);
  });

  test('mirrors playback started from the app UI', () async {
    await controller.play();
    final state = handler.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.controls, [MediaControl.stop]);

    controller.stop();
    expect(handler.playbackState.value.playing, isFalse);
  });

  test('shows the tempo in the media item', () {
    expect(handler.mediaItem.value?.artist, '120 BPM');
    controller.setBpm(96);
    expect(handler.mediaItem.value?.artist, '96 BPM');
  });

  test('removing the task stops playback', () async {
    await controller.play();
    await handler.onTaskRemoved();
    expect(controller.isPlaying, isFalse);
  });
}
