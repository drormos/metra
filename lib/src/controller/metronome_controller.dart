import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../audio/click_output.dart';
import '../audio/click_scheduler.dart';
import '../model/click_sound.dart';
import '../model/metronome_pattern.dart';
import '../timing/engine_clock_smoother.dart';
import '../timing/tap_tempo.dart';

/// App-facing metronome state: tempo, pattern, transport and audio errors.
/// Widgets read and drive this; they hold no metronome state themselves.
class MetronomeController extends ChangeNotifier {
  MetronomeController(this._output) : _scheduler = ClickScheduler(_output) {
    _scheduler.lookahead = foregroundLookahead;
    _failures = _output.deviceFailures.listen((_) => _recover());
  }

  static const minBpm = 30;
  static const maxBpm = 300;

  /// Lookahead while the app is visible: short, so tempo changes are heard
  /// within ~one step.
  static const foregroundLookahead = Duration(milliseconds: 150);

  /// Lookahead while hidden/inactive: long enough to ride out throttled
  /// timers (macOS App Nap) without gaps.
  static const backgroundLookahead = Duration(seconds: 2);

  /// How far the beat flash trails the engine clock. Measured by eye on
  /// macOS: 0 ms on built-in speakers, 20 ms on a USB-dongle wireless
  /// headset. Default to the speakers; higher-latency outputs adjust it.
  static const defaultVisualOffset = Duration.zero;
  static const minVisualOffset = Duration(milliseconds: -200);
  // Covers Bluetooth output (~150-250 ms).
  static const maxVisualOffset = Duration(milliseconds: 500);

  final ClickOutput _output;
  final ClickScheduler _scheduler;
  late final StreamSubscription<void> _failures;

  int _bpm = 120;
  MetronomePattern _pattern = const MetronomePattern.standard();
  bool _playing = false;
  Object? _audioError;
  bool _disposed = false;
  Duration _visualOffset = defaultVisualOffset;
  ClickSound _clickSound = ClickSound.classic;
  EngineClockSmoother _smoother = EngineClockSmoother();
  final _tapClock = Stopwatch()..start();
  final _tapTempo = TapTempo(minBpm: minBpm, maxBpm: maxBpm);

  int get bpm => _bpm;
  MetronomePattern get pattern => _pattern;
  bool get isPlaying => _playing;

  /// Last audio device error, or null when audio is healthy.
  Object? get audioError => _audioError;

  Duration get visualOffset => _visualOffset;

  ClickSound get clickSound => _clickSound;

  /// Applies to clicks scheduled from now on (within ~one lookahead). While
  /// stopped, plays a sample so the choice is heard.
  void setClickSound(ClickSound sound, {bool preview = true}) {
    if (sound == _clickSound) return;
    _clickSound = sound;
    _output.sound = sound;
    if (preview && !_playing) _output.preview();
    notifyListeners();
  }

  void setVisualOffset(Duration offset) {
    final clamped = offset < minVisualOffset
        ? minVisualOffset
        : offset > maxVisualOffset
        ? maxVisualOffset
        : offset;
    if (clamped == _visualOffset) return;
    _visualOffset = clamped;
    notifyListeners();
  }

  /// The step the beat indicator should show at [frameTime] (a monotonic
  /// local time, e.g. a Ticker's elapsed time), or null.
  ScheduledStep? visualStepAt(Duration frameTime) {
    if (!_playing) return null;
    final engineTime = _smoother.estimate(_output.now(), frameTime);
    return _scheduler.stepAt(engineTime - _visualOffset);
  }

  /// Call when the frame-time source restarts (e.g. a new Ticker).
  void resetVisualClock() => _smoother = EngineClockSmoother();

  /// Set the tempo (clamped to [minBpm]..[maxBpm]). While playing, the new
  /// tempo starts at the next step that is not yet committed to the engine.
  void setBpm(int bpm) {
    final clamped = bpm.clamp(minBpm, maxBpm);
    if (clamped == _bpm) return;
    _bpm = clamped;
    _scheduler.setTempo(clamped.toDouble());
    notifyListeners();
  }

  void nudge(int delta) => setBpm(_bpm + delta);

  /// Tap tempo: from the second tap on, sets the tempo from recent taps.
  void tap() {
    final bpm = _tapTempo.tap(_tapClock.elapsed);
    if (bpm != null) setBpm(bpm);
  }

  /// While playing, the new pattern starts at the next bar line.
  void setPattern(MetronomePattern pattern) =>
      switchTo(bpm: _bpm, pattern: pattern);

  /// Beat dot tap: normal → accent → silent. Heard from the next click.
  void cycleBeat(int beat) {
    _pattern = _pattern.cycleBeat(beat);
    _scheduler.replaceLevels(_pattern);
    notifyListeners();
  }

  /// Clicks per beat; while playing, from the next beat, bar kept.
  void setSubdivision(int stepsPerBeat) {
    if (stepsPerBeat == _pattern.stepsPerBeat) return;
    _switchAtNextBeat(
      _pattern.withSubdivision(stepsPerBeat),
      restartBar: false,
    );
  }

  /// Time signature (resets custom accents); while playing, the next beat
  /// starts a bar in the new meter.
  void setMeter(int beatsPerBar, int beatUnit) {
    if (beatsPerBar == _pattern.beatsPerBar && beatUnit == _pattern.beatUnit) {
      return;
    }
    _switchAtNextBeat(
      MetronomePattern.simple(
        beatsPerBar: beatsPerBar,
        stepsPerBeat: _pattern.stepsPerBeat,
        beatUnit: beatUnit,
      ),
      restartBar: true,
    );
  }

  void _switchAtNextBeat(MetronomePattern pattern, {required bool restartBar}) {
    _pattern = pattern;
    _scheduler.switchAtNextBeat(
      bpm: _bpm.toDouble(),
      pattern: pattern,
      restartBar: restartBar,
    );
    notifyListeners();
  }

  /// Load a song's tempo and pattern. While playing, the current bar
  /// finishes first, then both change on the next bar line.
  void switchTo({required int bpm, required MetronomePattern pattern}) {
    final clamped = bpm.clamp(minBpm, maxBpm);
    if (clamped == _bpm && pattern == _pattern) return;
    _bpm = clamped;
    _pattern = pattern;
    _scheduler.switchAtNextBar(bpm: clamped.toDouble(), pattern: pattern);
    notifyListeners();
  }

  Future<void> play() async {
    if (_playing) return;
    _playing = true;
    notifyListeners();
    await _start();
  }

  void stop() {
    if (!_playing) return;
    _scheduler.stop();
    _playing = false;
    notifyListeners();
  }

  Future<void> toggle() async => _playing ? stop() : await play();

  /// Wire to `AppLifecycleListener.onStateChange`.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _scheduler.lookahead = state == AppLifecycleState.resumed
        ? foregroundLookahead
        : backgroundLookahead;
    // Top up now, before the OS starts throttling our timer.
    _scheduler.refill();
  }

  @visibleForTesting
  Duration get lookaheadForTesting => _scheduler.lookahead;

  Future<void> _start() async {
    try {
      await _scheduler.start(bpm: _bpm.toDouble(), pattern: _pattern);
      _setAudioError(null);
    } catch (e) {
      _scheduler.stop();
      _playing = false;
      _setAudioError(e, force: true);
    }
  }

  Future<void> _recover() async {
    try {
      await _output.recover();
      _setAudioError(null);
    } catch (e) {
      _setAudioError(e);
    }
  }

  void _setAudioError(Object? error, {bool force = false}) {
    if (_disposed || (!force && error == _audioError)) return;
    _audioError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _failures.cancel();
    _scheduler.stop();
    super.dispose();
  }
}
