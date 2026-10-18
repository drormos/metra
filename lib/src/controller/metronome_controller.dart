import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../audio/click_output.dart';
import '../audio/click_scheduler.dart';
import '../model/click_sound.dart';
import '../model/click_volumes.dart';
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
  ClickVolumes _volumes = ClickVolumes.defaults;
  EngineClockSmoother _smoother = EngineClockSmoother();
  final _tapClock = Stopwatch()..start();
  final _tapTempo = TapTempo(minBpm: minBpm, maxBpm: maxBpm);
  // What the main screen was doing before a song editor preview took over.
  ({int bpm, MetronomePattern pattern, bool playing})? _beforePreview;
  bool _offsetTestStarted = false;

  int get bpm => _bpm;
  MetronomePattern get pattern => _pattern;
  bool get isPlaying => _playing;

  /// Last audio device error, or null when audio is healthy.
  Object? get audioError => _audioError;

  Duration get visualOffset => _visualOffset;

  ClickSound get clickSound => _clickSound;

  ClickVolumes get volumes => _volumes;

  /// Applies to clicks scheduled from now on (within ~one lookahead).
  void setVolumes(ClickVolumes volumes) {
    if (volumes == _volumes) return;
    _volumes = volumes;
    _output.volumes = volumes;
    notifyListeners();
  }

  /// Applies to clicks scheduled from now on (within ~one lookahead). While
  /// stopped, every call with [preview] plays the sample, even for the
  /// sound already chosen (listen again); while playing, the clicks are
  /// the sample.
  void setClickSound(ClickSound sound, {bool preview = true}) {
    if (preview && !_playing) {
      _output.sound = sound;
      _output.preview();
    }
    if (sound == _clickSound) return;
    _clickSound = sound;
    _output.sound = sound;
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
  /// local time shared by every caller, e.g. the frame timestamp), or null.
  ScheduledStep? visualStepAt(Duration frameTime) {
    if (!_playing) return null;
    final engineTime = _smoother.estimate(_output.now(), frameTime);
    return _scheduler.stepAt(engineTime - _visualOffset);
  }

  /// The polyrhythm pulse the lane should light at [frameTime] (same clock
  /// and visual offset as [visualStepAt]), or null.
  ScheduledPulse? visualPulseAt(Duration frameTime) {
    if (!_playing) return null;
    final engineTime = _smoother.estimate(_output.now(), frameTime);
    return _scheduler.pulseAt(engineTime - _visualOffset);
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

  /// Polyrhythm pulses per bar (0 = off; not the beat count). While
  /// playing, a new number starts at the next beat 1; Off stops at once.
  void setPolyrhythm(int n) {
    if (n == _pattern.polyrhythm) return;
    _applyPolyrhythm(_pattern.withPolyrhythm(n));
  }

  void _applyPolyrhythm(MetronomePattern pattern) {
    _pattern = pattern;
    if (pattern.polyrhythm == 0) {
      _scheduler.replaceLevels(pattern);
    } else {
      _scheduler.switchAtNextBar(bpm: _bpm.toDouble(), pattern: pattern);
    }
    notifyListeners();
  }

  /// Pulse cell tap: normal → accent → silent. Heard from the next pulse.
  void cyclePulse(int k) {
    _pattern = _pattern.cyclePulse(k);
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

  /// Time signature, keeping existing beat states (new beats regular);
  /// while playing, the next beat starts a bar in the new meter.
  void setMeter(int beatsPerBar, int beatUnit) {
    if (beatsPerBar == _pattern.beatsPerBar && beatUnit == _pattern.beatUnit) {
      return;
    }
    _switchAtNextBeat(
      _pattern.withBeats(beatsPerBar, beatUnit: beatUnit),
      restartBar: true,
    );
  }

  /// An edited song applied while it may be playing: each change takes
  /// effect as it would on the main screen, without restarting the bar.
  /// Tempo from the next step; accents and cells from the next click;
  /// subdivision from the next beat; a new time signature starts a bar on
  /// the next beat; a polyrhythm as [setPolyrhythm]. Nothing changed:
  /// nothing happens.
  void applyEdit({required int bpm, required MetronomePattern pattern}) {
    setBpm(bpm);
    if (pattern == _pattern) return;
    if (pattern.beatsPerBar != _pattern.beatsPerBar ||
        pattern.beatUnit != _pattern.beatUnit) {
      _switchAtNextBeat(pattern, restartBar: true);
    } else if (pattern.stepsPerBeat != _pattern.stepsPerBeat) {
      _switchAtNextBeat(pattern, restartBar: false);
    } else if (pattern.polyrhythm != _pattern.polyrhythm) {
      _applyPolyrhythm(pattern);
    } else {
      _pattern = pattern;
      _scheduler.replaceLevels(pattern);
      notifyListeners();
    }
  }

  /// Settings' visual offset test: uses the click if it's already
  /// playing, otherwise starts it; [endOffsetTest] stops only a click the
  /// test started.
  Future<void> startOffsetTest() async {
    if (_playing) return;
    _offsetTestStarted = true;
    await play();
  }

  /// Leaving settings: stops the click if the offset test started it.
  void endOffsetTest() {
    if (_offsetTestStarted) stop();
    _offsetTestStarted = false;
  }

  /// Whether a song editor preview has taken over the click (it may have
  /// been stopped since; [endPreview] still restores).
  bool get previewing => _beforePreview != null;

  /// Song editor preview: plays [bpm] and [pattern] from beat 1, taking
  /// over the click. The first call remembers the main screen's state for
  /// [endPreview]. Edits while previewing go through [applyEdit].
  Future<void> preview({required int bpm, required MetronomePattern pattern}) {
    _beforePreview ??= (bpm: _bpm, pattern: _pattern, playing: _playing);
    loadSong(bpm: bpm, pattern: pattern);
    return play();
  }

  /// Leaving the song editor: restores what the main screen was doing
  /// (playing restarts it on beat 1). No preview: nothing happens.
  void endPreview() {
    final before = _beforePreview;
    if (before == null) return;
    _beforePreview = null;
    if (!before.playing) stop();
    loadSong(bpm: before.bpm, pattern: before.pattern);
    if (before.playing) play();
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

  /// Load a song (next/previous, or picked from a list). While playing it
  /// restarts immediately on beat 1 at the new tempo; while stopped it only
  /// loads.
  void loadSong({required int bpm, required MetronomePattern pattern}) {
    _bpm = bpm.clamp(minBpm, maxBpm);
    _pattern = pattern;
    _scheduler.restartNow(bpm: _bpm.toDouble(), pattern: pattern);
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
      final bpm = _bpm, pattern = _pattern;
      await _scheduler.start(bpm: bpm.toDouble(), pattern: pattern);
      // Changed while the device was starting, when the scheduler wasn't
      // running to take it: restart with what the screen shows.
      if (_bpm != bpm || _pattern != pattern) {
        _scheduler.restartNow(bpm: _bpm.toDouble(), pattern: _pattern);
      }
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
