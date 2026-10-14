import 'metronome_controller.dart';

/// Keeps the screen awake while [metronome] plays (ui-spec.md) by calling
/// [setAwake] on every start/stop change, and only then.
void keepAwakeWhilePlaying(
  MetronomeController metronome,
  Future<void> Function(bool awake) setAwake,
) {
  var awake = false;
  metronome.addListener(() {
    if (metronome.isPlaying == awake) return;
    awake = metronome.isPlaying;
    setAwake(awake).catchError((_) {}); // best effort: never block playback
  });
}
