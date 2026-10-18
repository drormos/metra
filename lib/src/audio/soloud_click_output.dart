import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import '../model/click_sound.dart';
import '../model/click_volumes.dart';
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
    soloud.setMaxActiveVoiceCount(maxVoices);
    // All sounds up front (a few KB each), so switching never waits.
    return SoloudClickOutput._({
      for (final sound in ClickSound.values)
        sound: (
          accent: await soloud.loadAsset(sound.assetFor(StepLevel.accent)),
          normal: await soloud.loadAsset(sound.assetFor(StepLevel.normal)),
        ),
    });
  }

  /// Scheduled clicks hold a voice from [schedule] until they finish
  /// ringing, and at the limit SoLoud silently drops the oldest one. The
  /// background lookahead (2 s) at 300 bpm in 16ths needs ~45 (default 16).
  static const maxVoices = 128;

  static const _defaultIdleTimeout = Duration(milliseconds: 500);

  final Map<ClickSound, ({AudioSource accent, AudioSource normal})> _sources;
  var _sound = ClickSound.classic;
  var _volumes = ClickVolumes.defaults;

  // The samples peak at 0.9 (accent) and 0.7 (normal) of full scale. This
  // boost makes every level peak at its volume × 0.9, so the per-level
  // volumes alone set the balance.
  static const _normalBoost = 0.9 / 0.7;

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
      volume: _gain(level),
    ),
  );

  /// Polyrhythm pulses: the same samples ~a fifth up (1.5× speed, by ear).
  static const pulseSpeed = 1.5;

  @override
  ClickHandle schedulePulse(StepLevel level, Duration at) {
    final accent = level == StepLevel.accent;
    final source = accent ? _sources[_sound]!.accent : _sources[_sound]!.normal;
    // Accented pulses at the polyrhythm volume, regular ones softer.
    final gain = _volumes.polyrhythm * (accent ? 1 : 0.75 * _normalBoost);
    return _Click(
      SoLoud.instance.playScheduled(
        source,
        at,
        volume: gain,
        scale: pulseSpeed,
      ),
    );
  }

  double _gain(StepLevel level) =>
      _volumes.forLevel(level) * (level == StepLevel.accent ? 1 : _normalBoost);

  @override
  set sound(ClickSound value) => _sound = value;

  @override
  set volumes(ClickVolumes value) => _volumes = value;

  SoundHandle? _preview;

  /// A new sample cuts off the one still ringing, so taps restart it.
  @override
  void preview() {
    final previous = _preview;
    if (previous != null) unawaited(SoLoud.instance.stop(previous));
    _preview = SoLoud.instance.play(
      _sources[_sound]!.accent,
      volume: _gain(StepLevel.accent),
    );
  }

  @override
  void cancel(ClickHandle handle) =>
      unawaited(SoLoud.instance.stop((handle as _Click).handle));
}

// SoundHandle is an extension type, which is not an Object subtype.
class _Click {
  _Click(this.handle);
  final SoundHandle handle;
}
