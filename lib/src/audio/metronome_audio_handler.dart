import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';

/// Bridges [MetronomeController] to audio_service: while playing, Android
/// keeps the app alive as a media foreground service (screen off or app in
/// background) and shows the media card in the notification and lock
/// screen (ui-spec.md "Media controls"): title, subtitle and a cover that
/// follow the main screen, and one ▶ / ❚❚ toggle that starts and stops.
/// Setlist mode adds previous/next; Free play and Single song add the
/// main screen's −5 −1 +1 +5 tempo steps. No duration, so no seek bar.
class MetronomeAudioHandler extends BaseAudioHandler {
  MetronomeAudioHandler(this._controller, {this._library, this._cover}) {
    Listenable.merge([_controller, ?_library]).addListener(_publish);
    _publish();
  }

  final MetronomeController _controller;
  final LibraryController? _library;

  /// The cover image for a tempo, as a file URI; null: no artwork.
  final Future<Uri> Function(int bpm)? _cover;
  int? _coverBpm;
  Uri? _coverUri;

  // Stopped from outside the app (the card, headset, watch, the tile): the
  // card stays, stopped with Start, until swiped away. Stopping inside the
  // app removes it (ui-spec.md "Media controls", "When it's shown").
  bool _keepCard = false;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => stop();

  /// A stop from outside the app.
  @override
  Future<void> stop() async {
    _keepCard = _controller.isPlaying || _keepCard;
    _controller.stop();
    _publish();
  }

  /// A tempo step from the card (Free play and Single song). In Single
  /// song it's an unsaved change, as on the main screen.
  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name == stepAction) _controller.nudge(extras!['delta'] as int);
  }

  static const stepAction = 'step';

  static MediaControl _step(int delta, String icon, String label) =>
      MediaControl.custom(
        androidIcon: 'drawable/ic_step_$icon',
        label: label,
        name: stepAction,
        extras: {'delta': delta},
      );

  // Android 13+ puts the first two custom actions in the previous / next
  // slots, so −1 and +1 come first: the compact card shows −1 ▶ +1.
  static final _steps = [
    _step(-1, 'minus1', 'Tempo −1'),
    _step(1, 'plus1', 'Tempo +1'),
    _step(-5, 'minus5', 'Tempo −5'),
    _step(5, 'plus5', 'Tempo +5'),
  ];

  /// The stopped card was swiped away.
  @override
  Future<void> onNotificationDeleted() async {
    _keepCard = false;
    _controller.stop();
    _publish();
  }

  @override
  Future<void> skipToNext() async => _library?.nextSong(_controller);

  @override
  Future<void> skipToPrevious() async => _library?.previousSong(_controller);

  /// Swiping the app away from recents stops the click and removes the
  /// card.
  @override
  Future<void> onTaskRemoved() => onNotificationDeleted();

  // Playing = ready + playing: audio_service then starts the foreground
  // service. Stopped and ready keeps the card (no longer foreground);
  // idle removes it and releases the service.
  void _publish() {
    final playing = _controller.isPlaying;
    if (playing) _keepCard = false;
    // One toggle: ❚❚ while playing (a pause request stops), ▶ when not.
    final toggle = playing ? MediaControl.pause : MediaControl.play;
    final library = _library;
    final set = library?.activeSetlist;
    playbackState.add(
      PlaybackState(
        controls: set != null
            ? [MediaControl.skipToPrevious, toggle, MediaControl.skipToNext]
            : [_steps[0], toggle, _steps[1], _steps[2], _steps[3]],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: playing || _keepCard
            ? AudioProcessingState.ready
            : AudioProcessingState.idle,
        playing: playing,
      ),
    );
    final bpm = _controller.bpm;
    final title = library?.currentSong?.name ?? 'Free play';
    var subtitle = '$bpm bpm · ${_controller.pattern.timeSignature}';
    if (set != null) {
      final index = library!.currentIndex;
      final position = index < 0 ? '' : ' ${index + 1}/${set.songIds.length}';
      subtitle += ' · ${set.name}$position';
    }
    _requestCover(bpm);
    final current = mediaItem.value;
    // MediaItem equality only compares ids, so compare what's shown.
    if (current?.title != title ||
        current?.artist != subtitle ||
        current?.artUri != _coverUri) {
      mediaItem.add(
        MediaItem(
          id: 'metronome',
          title: title,
          artist: subtitle,
          artUri: _coverUri,
          // No duration: a metronome has none, so no empty seek bar.
        ),
      );
    }
  }

  /// Renders the cover for a new tempo, then shows it if the tempo hasn't
  /// moved on meanwhile.
  void _requestCover(int bpm) {
    final cover = _cover;
    if (cover == null || bpm == _coverBpm) return;
    _coverBpm = bpm;
    cover(bpm).then((uri) {
      if (_coverBpm != bpm) return;
      _coverUri = uri;
      _publish();
    }, onError: (Object e) => debugPrint('Media cover failed: $e'));
  }
}
