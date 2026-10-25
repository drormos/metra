import '../model/library.dart';
import 'library_controller.dart';
import 'metronome_controller.dart';

/// Keeps the screen on (ui-spec.md "Keep the screen on"): always in stage
/// mode, else while Metra is open or only while playing, as set. The flag
/// only holds while Metra is in front, so leaving the app lets the phone
/// lock. Calls [setAwake] only when the answer changes.
void keepScreenAwake(
  MetronomeController metronome,
  LibraryController? library,
  Future<void> Function(bool awake) setAwake,
) {
  bool? awake;
  void sync() {
    final want =
        metronome.isPlaying ||
        library == null ||
        library.stageMode ||
        library.keepScreenOn == KeepScreenOn.whileOpen;
    if (want == awake) return;
    awake = want;
    setAwake(want).catchError((_) {}); // best effort: never block playback
  }

  metronome.addListener(sync);
  library?.addListener(sync);
  sync();
}
