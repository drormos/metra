import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../model/click_sound.dart';
import '../model/metronome_pattern.dart';
import 'click_output.dart';

/// [ClickOutput] backed by the flutter_soloud engine clock.
class SoloudClickOutput implements ClickOutput {
  SoloudClickOutput._(this._sources);

  /// Initializes the engine and loads the click samples. Call once, from
  /// `main()`: `init()` on a running engine unloads every sound.
  static Future<SoloudClickOutput> create() async {
    final soloud = SoLoud.instance;
    await soloud.init();
    // Headroom for fast subdivisions (default is 16).
    soloud.setMaxActiveVoiceCount(32);
    // All sounds up front (a few KB each), so switching never waits.
    return SoloudClickOutput._({
      for (final sound in ClickSound.values)
        sound: (
          accent: await soloud.loadAsset(sound.assetFor(StepLevel.accent)),
          normal: await soloud.loadAsset(sound.assetFor(StepLevel.normal)),
        ),
    });
  }

  static const _defaultIdleTimeout = Duration(milliseconds: 500);

  final Map<ClickSound, ({AudioSource accent, AudioSource normal})> _sources;
  var _sound = ClickSound.classic;

  @override
  Stream<void> get deviceFailures =>
      SoLoud.instance.audioDeviceStartFailures.map((_) {});

  @override
  Future<void> recover() => SoLoud.instance.startAudioDevice();

  @override
  Duration now() => SoLoud.instance.getEngineTime();

  @override
  Future<void> prepare() async {
    // The engine clock only advances while the device runs. With the
    // default idle stop, slow tempos leave gaps with nothing pending and
    // the clock would freeze between clicks.
    SoLoud.instance.setAudioDeviceIdleTimeout(null);
    await SoLoud.instance.startAudioDevice();
  }

  @override
  void release() =>
      SoLoud.instance.setAudioDeviceIdleTimeout(_defaultIdleTimeout);

  @override
  ClickHandle schedule(StepLevel level, Duration at) => _Click(
    SoLoud.instance.playScheduled(
      level == StepLevel.accent
          ? _sources[_sound]!.accent
          : _sources[_sound]!.normal,
      at,
      // Subdivisions sit under the beat so the pulse stays clear.
      volume: level == StepLevel.soft ? 0.4 : 1,
    ),
  );

  @override
  set sound(ClickSound value) => _sound = value;

  @override
  void preview() => SoLoud.instance.play(_sources[_sound]!.accent);

  @override
  void cancel(ClickHandle handle) =>
      unawaited(SoLoud.instance.stop((handle as _Click).handle));
}

// SoundHandle is an extension type, which is not an Object subtype.
class _Click {
  _Click(this.handle);
  final SoundHandle handle;
}
