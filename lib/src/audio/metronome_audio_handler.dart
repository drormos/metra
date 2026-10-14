import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';

/// Bridges [MetronomeController] to audio_service: while playing, Android
/// keeps the app alive as a media foreground service (screen off or app in
/// background) and shows the transport in the notification and lock
/// screen, with previous/next song when a setlist is loaded.
class MetronomeAudioHandler extends BaseAudioHandler {
  MetronomeAudioHandler(this._controller, {this._library}) {
    Listenable.merge([_controller, ?_library]).addListener(_publish);
    _publish();
  }

  final MetronomeController _controller;
  final LibraryController? _library;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() async => _controller.stop();

  @override
  Future<void> stop() async => _controller.stop();

  @override
  Future<void> skipToNext() async => _library?.nextSong(_controller);

  @override
  Future<void> skipToPrevious() async => _library?.previousSong(_controller);

  /// Swiping the app away from recents stops the click.
  @override
  Future<void> onTaskRemoved() => stop();

  // Playing = ready + playing: audio_service then starts the foreground
  // service; stopped = idle releases it.
  void _publish() {
    final playing = _controller.isPlaying;
    final transport = playing ? MediaControl.stop : MediaControl.play;
    final library = _library;
    // Previous/next only inside a setlist (none in Free play).
    final songs =
        library?.activeSetlist != null && library!.visibleSongs.isNotEmpty;
    playbackState.add(
      PlaybackState(
        controls: songs
            ? [MediaControl.skipToPrevious, transport, MediaControl.skipToNext]
            : [transport],
        androidCompactActionIndices: songs ? const [0, 1, 2] : const [0],
        processingState: playing
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: playing,
      ),
    );
    // MediaItem equality only compares ids, so compare the shown text.
    final title = library?.currentSong?.name ?? 'Metra';
    final tempo = '${_controller.bpm} BPM';
    final current = mediaItem.value;
    if (current?.title != title || current?.artist != tempo) {
      mediaItem.add(MediaItem(id: 'metronome', title: title, artist: tempo));
    }
  }
}
