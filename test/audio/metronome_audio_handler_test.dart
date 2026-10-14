import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/metronome_audio_handler.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';

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

  group('with songs', () {
    late Directory dir;
    late LibraryController library;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('metra_handler_test');
      library = await LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      );
      handler = MetronomeAudioHandler(controller, library: library);
    });

    tearDown(() async {
      await library.flush();
      dir.deleteSync(recursive: true);
    });

    test('shows previous/next only with a setlist loaded', () {
      expect(handler.playbackState.value.controls, [MediaControl.play]);
      final song = library.addSong(
        name: 'Opener',
        bpm: 150,
        pattern: const MetronomePattern.standard(),
      );
      expect(handler.playbackState.value.controls, [
        MediaControl.play,
      ], reason: 'Free play');
      final gig = library.addSetlist('Gig');
      library
        ..addToSetlist(gig.id, song.id)
        ..setActiveSetlist(gig.id);
      expect(handler.playbackState.value.controls, [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ]);
    });

    test('skip buttons switch songs; title shows the song', () async {
      final gig = library.addSetlist('Gig');
      for (final (name, bpm) in [('One', 100), ('Two', 110)]) {
        final song = library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        );
        library.addToSetlist(gig.id, song.id);
      }
      library.setActiveSetlist(gig.id);
      await handler.skipToNext();
      await handler.skipToNext();
      expect(controller.bpm, 110);
      expect(handler.mediaItem.value?.title, 'Two');
      await handler.skipToPrevious();
      expect(handler.mediaItem.value?.title, 'One');
      expect(handler.mediaItem.value?.artist, '100 BPM');
    });
  });
}
