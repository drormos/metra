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
    // Overlapping clicks (accent + subdivision + polyrhythm) can sum past
    // full scale: a brickwall look-ahead limiter catches them instead of
    // the hard clip. No drive, so a single click passes untouched; the
    // 1 ms look-ahead delays every click alike (the grid is unchanged).
    final limiter = soloud.filters.limiterFilter..activate();
    limiter.threshold.value = 0;
    limiter.outputCeiling.value = -0.1;
    limiter.attackTime.value = 1;
    limiter.releaseTime.value = 50;
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
  var _sound = ClickSound.woodblock;
  var _volumes = ClickVolumes.defaults;

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
  ClickHandle schedule(StepLevel level, Duration at, {bool raised = false}) =>
      _Click(
        _full(
          raised
              // The accent, two semitones up: heard as "something changed",
              // not mistaken for a polyrhythm pulse (a fifth up).
              ? SoLoud.instance.playScheduled(
                  _sources[_sound]!.accent,
                  at,
                  volume: _gain(StepLevel.accent),
                  scale: partChangeSpeed,
                )
              : SoLoud.instance.playScheduled(
                  level == StepLevel.accent
                      ? _sources[_sound]!.accent
                      : _sources[_sound]!.normal,
                  at,
                  volume: _gain(level),
                ),
        ),
      );

  /// A mono click at full level in both channels: SoLoud's default centre
  /// pan is constant-power (0.707 a side, −3 dB), a fixed loss for a click
  /// that's the only thing playing.
  static SoundHandle _full(SoundHandle handle) {
    SoLoud.instance.setPanAbsolute(handle, 1, 1);
    return handle;
  }

  /// The first beat of a new part: two semitones up (2^(2/12)).
  static const partChangeSpeed = 1.1225;

  /// Polyrhythm pulses: the same samples ~a fifth up (1.5× speed, by ear).
  static const pulseSpeed = 1.5;

  @override
  ClickHandle schedulePulse(StepLevel level, Duration at) {
    final accent = level == StepLevel.accent;
    final source = accent ? _sources[_sound]!.accent : _sources[_sound]!.normal;
    // Accented pulses at the polyrhythm volume, regular ones softer.
    final gain = _volumes.polyrhythm * (accent ? 1 : 0.75);
    return _Click(
      _full(
        SoLoud.instance.playScheduled(
          source,
          at,
          volume: gain,
          scale: pulseSpeed,
        ),
      ),
    );
  }

  /// 100% is the sample as it is.
  double _gain(StepLevel level) => _volumes.forLevel(level);

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
    _preview = _full(
      SoLoud.instance.play(
        _sources[_sound]!.accent,
        volume: _gain(StepLevel.accent),
      ),
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
