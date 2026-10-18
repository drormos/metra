import '../model/click_sound.dart';
import '../model/click_volumes.dart';
import '../model/metronome_pattern.dart';

/// Opaque handle to one scheduled click.
typedef ClickHandle = Object;

/// The audio engine as seen by the scheduler: an engine clock plus
/// sample-accurate click scheduling. Keeping SoLoud behind this interface
/// lets the scheduler and controller run in unit tests with a fake clock.
abstract interface class ClickOutput {
  /// Current engine time (the clock [schedule] times refer to).
  Duration now();

  /// Get the output ready for continuous playback (device running, no idle
  /// stop between clicks). Await before reading [now] to anchor a session.
  Future<void> prepare();

  /// Undo [prepare] once playback stops.
  void release();

  /// Play a click of [level] at engine time [at]. [level] is never
  /// [StepLevel.silent].
  ClickHandle schedule(StepLevel level, Duration at);

  /// Play a polyrhythm pulse of [level] (accent or normal) at engine time
  /// [at]: the current click sound, higher, so it's a separate voice.
  ClickHandle schedulePulse(StepLevel level, Duration at);

  /// Cancel a click that has not started yet.
  void cancel(ClickHandle handle);

  /// Sound for clicks scheduled from now on.
  set sound(ClickSound value);

  /// Per-level volumes for clicks scheduled from now on.
  set volumes(ClickVolumes value);

  /// Play one accent click right away (feedback when picking a sound),
  /// cutting off a previous one still ringing.
  void preview();

  /// Fires when the output device failed to start on its own.
  Stream<void> get deviceFailures;

  /// Try to start the output device again after a [deviceFailures] event.
  Future<void> recover();
}
