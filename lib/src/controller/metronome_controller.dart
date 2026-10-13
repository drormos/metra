import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../audio/click_output.dart';
import '../audio/click_scheduler.dart';
import '../model/metronome_pattern.dart';

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

  final ClickOutput _output;
  final ClickScheduler _scheduler;
  late final StreamSubscription<void> _failures;

  int _bpm = 120;
  MetronomePattern _pattern = const MetronomePattern.standard();
  bool _playing = false;
  Object? _audioError;
  bool _disposed = false;

  int get bpm => _bpm;
  MetronomePattern get pattern => _pattern;
  bool get isPlaying => _playing;

  /// Last audio device error, or null when audio is healthy.
  Object? get audioError => _audioError;

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

  /// While playing, restarts from the downbeat with [pattern].
  Future<void> setPattern(MetronomePattern pattern) async {
    if (pattern == _pattern) return;
    _pattern = pattern;
    notifyListeners();
    if (_playing) await _start();
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
