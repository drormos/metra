import 'package:audio_service/audio_service.dart';

import '../controller/metronome_controller.dart';

/// Bridges [MetronomeController] to audio_service: while playing, Android
/// keeps the app alive as a media foreground service (screen off or app in
/// background) and shows Play/Stop in the notification and lock screen.
class MetronomeAudioHandler extends BaseAudioHandler {
  MetronomeAudioHandler(this._controller) {
    _controller.addListener(_publish);
    _publish();
  }

  final MetronomeController _controller;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() async => _controller.stop();

  @override
  Future<void> stop() async => _controller.stop();

  /// Swiping the app away from recents stops the click.
  @override
  Future<void> onTaskRemoved() => stop();

  // Playing = ready + playing: audio_service then starts the foreground
  // service; stopped = idle releases it.
  void _publish() {
    final playing = _controller.isPlaying;
    playbackState.add(
      PlaybackState(
        controls: [playing ? MediaControl.stop : MediaControl.play],
        androidCompactActionIndices: const [0],
        processingState: playing
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: playing,
      ),
    );
    // MediaItem equality only compares ids, so compare the shown text.
    final tempo = '${_controller.bpm} BPM';
    if (mediaItem.value?.artist != tempo) {
      mediaItem.add(MediaItem(id: 'metronome', title: 'Metra', artist: tempo));
    }
  }
}
