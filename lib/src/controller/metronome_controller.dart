import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../audio/click_output.dart';
import '../audio/click_scheduler.dart';
import '../model/click_sound.dart';
import '../model/click_volumes.dart';
import '../model/metronome_pattern.dart';
import '../model/on_start.dart';
import '../model/song_part.dart';
import '../model/song_plan.dart';
import '../timing/engine_clock_smoother.dart';
import '../timing/tap_tempo.dart';

/// App-facing metronome state: tempo, pattern, transport and audio errors.
/// Widgets read and drive this; they hold no metronome state themselves.
class MetronomeController extends ChangeNotifier {
  MetronomeController(this._output) : _scheduler = ClickScheduler(_output) {
    _scheduler
      ..lookahead = foregroundLookahead
      ..onRunTempo = _runTempo
      ..onRunPattern = _runPattern
      ..onRunEnd = _runEnded;
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
  OnStart _onStart = OnStart.off;
  // The tempo when this run started (Stop returns there with speed up);
  // null when not playing a run.
  int? _runFrom;
  Object? _audioError;
  bool _disposed = false;
  Duration _visualOffset = defaultVisualOffset;
  ClickSound _clickSound = ClickSound.woodblock;
  ClickVolumes _volumes = ClickVolumes.defaults;
  EngineClockSmoother _smoother = EngineClockSmoother();
  final _tapClock = Stopwatch()..start();
  final _tapTempo = TapTempo(minBpm: minBpm, maxBpm: maxBpm);
  // What the main screen was doing before a song editor preview took over.
  ({int bpm, MetronomePattern pattern, bool playing, List<SongPart>? parts})?
  _beforePreview;
  // A song of 2+ parts (null: one part, or Free play), what happens at its
  // end, the part Start begins with, and the plan while it plays.
  List<SongPart>? _parts;
  SongEnd _end = SongEnd.stop;
  int _startPart = 0;
  SongPlan? _plan;

  /// The loaded song's parts while it has 2 or more, with the changes made
  /// here (unsaved until saved to the song); null otherwise.
  List<SongPart>? get parts => _parts;

  /// "When the song ends" of the loaded song with parts.
  SongEnd get songEnd => _end;

  /// A song with parts ended by itself (not Stop after, not by hand).
  VoidCallback? onSongEnd;

  bool _offsetTestStarted = false;

  int get bpm => _bpm;
  MetronomePattern get pattern => _pattern;
  bool get isPlaying => _playing;

  /// Count-in, speed up, stop after (ui-spec.md "When I press Start"):
  /// they apply whenever playback starts from stopped and when a song is
  /// loaded while playing. A count-in waits for the next start; speed up
  /// and stop after changes apply to a run in progress from its next beat.
  OnStart get onStart => _onStart;

  int get countIn => _onStart.countIn;

  void setOnStart(OnStart onStart) {
    if (onStart == _onStart) return;
    _onStart = onStart;
    if (_plan case final plan?) {
      plan.onStart = onStart;
      _scheduler.run = plan;
    } else if (_runFrom != null) {
      _scheduler.run = onStart.runs ? onStart : null;
    }
    notifyListeners();
  }

  /// 0 switches the count-in off (keeping its bars).
  void setCountIn(int bars) => setOnStart(
    bars == 0
        ? _onStart.copyWith(countInOn: false)
        : _onStart.copyWith(countInOn: true, countInBars: bars),
  );

  /// The tempo outside a speed-up run: while one plays, where it started
  /// (Stop returns there); otherwise [bpm]. What a song's changes and
  /// saves compare against.
  int get startBpm =>
      _runFrom != null && _onStart.speedUp && _parts == null ? _runFrom! : _bpm;

  /// Whether a run (speed up or stop after) is playing.
  bool get inRun => _playing && _runFrom != null && _onStart.runs;

  /// When the song's beat 1 played in this run (engine time), or null.
  Duration? get runStart => _playing ? _scheduler.runStart : null;

  void _runTempo(double bpm) {
    _bpm = bpm.round();
    notifyListeners();
  }

  void _runPattern(MetronomePattern pattern) {
    _pattern = pattern;
    notifyListeners();
  }

  void _runEnded() {
    final bar = _scheduler.endBar;
    final songEnded = bar != null && _plan?.locate(bar) == null;
    stop();
    if (songEnded) onSongEnd?.call();
  }

  /// With parts: the part playing (stopped: the one Start begins with) and
  /// the bar within it, both from 0; null for a song without parts.
  ({int part, int bar})? get partPosition {
    final parts = _parts;
    if (parts == null) return null;
    final bar = _playing ? _scheduler.stepAt(_output.now())?.bar : null;
    if (bar == null) return (part: _startPart, bar: 0);
    return _plan?.locate(bar) ?? (part: parts.length - 1, bar: 0);
  }

  /// Goes to part [index]: stopped, Start begins there; playing, it starts
  /// on the next bar line.
  void jumpToPart(int index) {
    final parts = _parts;
    if (parts == null || index < 0 || index >= parts.length) return;
    if (_plan case final plan? when _playing) {
      _scheduler.replan((bar) => plan.jump(bar, index));
      return;
    }
    _startPart = index;
    _bpm = parts[index].tempoStart;
    _pattern = parts[index].pattern;
    notifyListeners();
  }

  /// Whether an edit to the current part reaches the click: the next part
  /// may already be handed to the engine (up to a lookahead ahead), and
  /// then the edit only changes the part (heard when it plays again).
  bool get _reachesClick {
    final plan = _plan;
    if (plan == null) return true;
    final bar = _scheduler.openBar;
    final current = partPosition!.part;
    return (bar == null ? current : plan.locate(bar)?.part) == current;
  }

  /// Keeps the current part in step with an edit made here: a tempo
  /// change of [shift] moves both its ends; [pattern] replaces its own.
  void _editPart({int shift = 0, MetronomePattern? pattern}) {
    final parts = _parts;
    if (parts == null) return;
    final i = partPosition!.part;
    final part = parts[i];
    final edited = [...parts]
      ..[i] = part.copyWith(
        tempoStart: (part.tempoStart + shift).clamp(minBpm, maxBpm),
        tempoEnd: (part.tempoEnd + shift).clamp(minBpm, maxBpm),
        pattern: pattern,
      );
    _parts = edited;
    _plan?.parts = edited;
  }

  /// Whether a count-in is playing, or about to start.
  bool get countingIn => _playing && _scheduler.countingIn;

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

  /// The engine time the lights show at [frameTime] (smoothed, minus the
  /// visual offset), or null when stopped. One reading per frame feeds
  /// [stepAt], [pulseAt] and the lights' fades.
  Duration? visualTimeAt(Duration frameTime) => !_playing
      ? null
      : _smoother.estimate(_output.now(), frameTime) - _visualOffset;

  ScheduledStep? stepAt(Duration time) => _scheduler.stepAt(time);

  ScheduledPulse? pulseAt(Duration time) => _scheduler.pulseAt(time);

  /// See [ClickScheduler.stepInterval].
  Duration? stepInterval(ScheduledStep step) => _scheduler.stepInterval(step);

  /// Call when the frame-time source restarts (e.g. a new Ticker).
  void resetVisualClock() => _smoother = EngineClockSmoother();

  /// Set the tempo (clamped to [minBpm]..[maxBpm]). While playing, the new
  /// tempo starts at the next step that is not yet committed to the engine.
  void setBpm(int bpm) {
    final clamped = bpm.clamp(minBpm, maxBpm);
    if (clamped == _bpm) return;
    _editPart(shift: clamped - _bpm);
    _bpm = clamped;
    if (_reachesClick) _scheduler.setTempo(clamped.toDouble());
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
    _editPart(pattern: _pattern);
    if (_reachesClick) _scheduler.replaceLevels(_pattern);
    notifyListeners();
  }

  /// Polyrhythm pulses per bar (0 = off; not the beat count). While
  /// playing, a new number starts at the next beat (with the rest of the
  /// bar's pulses); Off stops at once.
  void setPolyrhythm(int n) {
    if (n == _pattern.polyrhythm) return;
    _applyPolyrhythm(_pattern.withPolyrhythm(n));
  }

  void _applyPolyrhythm(MetronomePattern pattern) {
    _pattern = pattern;
    _editPart(pattern: pattern);
    if (!_reachesClick) {
      // The next part is already on its way: only the part changes.
    } else if (pattern.polyrhythm == 0) {
      _scheduler.replaceLevels(pattern);
    } else {
      // From the next beat, bar kept: the pulses are tied to the bar, so
      // the rest of this bar's pulses play in time; no waiting for beat 1.
      _scheduler.switchAtNextBeat(
        bpm: _bpm.toDouble(),
        pattern: pattern,
        restartBar: false,
      );
    }
    notifyListeners();
  }

  /// Pulse cell tap: normal → accent → silent. Heard from the next pulse.
  void cyclePulse(int k) {
    _pattern = _pattern.cyclePulse(k);
    _editPart(pattern: _pattern);
    if (_reachesClick) _scheduler.replaceLevels(_pattern);
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
  /// the next beat; a polyrhythm as [setPolyrhythm]; a count-in from the
  /// next start. Nothing changed: nothing happens.
  void applyEdit({
    required int bpm,
    required MetronomePattern pattern,
    OnStart? onStart,
  }) {
    if (onStart != null) setOnStart(onStart);
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
      _editPart(pattern: pattern);
      if (_reachesClick) _scheduler.replaceLevels(pattern);
      notifyListeners();
    }
  }

  /// Back to a song's stored [parts] and [end] while it may be playing:
  /// the current part's tempo and pattern apply as [applyEdit] does.
  void applyParts(List<SongPart> parts, SongEnd end, {OnStart? onStart}) {
    final part = parts[partPosition!.part.clamp(0, parts.length - 1)];
    applyEdit(bpm: part.tempoStart, pattern: part.pattern, onStart: onStart);
    // After the edit, which would otherwise shift the restored part.
    _parts = parts;
    _end = end;
    _plan
      ?..parts = parts
      ..end = end;
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
  /// over the click (no count-in: it's a listen, not a take). The first
  /// call remembers the main screen's state for [endPreview]. Edits while
  /// previewing go through [applyEdit].
  Future<void> preview({required int bpm, required MetronomePattern pattern}) {
    _beforePreview ??= (
      bpm: _bpm,
      pattern: _pattern,
      playing: _playing,
      parts: _parts,
    );
    _parts = null;
    _load(bpm, pattern, run: false);
    return play(run: false);
  }

  /// Leaving the song editor: restores what the main screen was doing
  /// (playing restarts it on beat 1). No preview: nothing happens.
  void endPreview() {
    final before = _beforePreview;
    if (before == null) return;
    _beforePreview = null;
    if (!before.playing) stop();
    _parts = before.parts;
    _startPart = 0;
    _load(before.bpm, before.pattern, run: false);
    if (before.playing) play(run: false);
  }

  void _switchAtNextBeat(MetronomePattern pattern, {required bool restartBar}) {
    _pattern = pattern;
    _editPart(pattern: pattern);
    if (_reachesClick) {
      _scheduler.switchAtNextBeat(
        bpm: _bpm.toDouble(),
        pattern: pattern,
        restartBar: restartBar,
      );
    }
    notifyListeners();
  }

  /// Load a song (next/previous, or picked from a list) with its
  /// [onStart] (null keeps the current one). While playing it restarts
  /// immediately on beat 1 at the new tempo, after the song's count-in,
  /// starting its own run; while stopped it only loads.
  /// A song of 2+ [parts] starts at its first part (speed up doesn't
  /// apply: the parts decide the tempo) and ends as [end] says.
  void loadSong({
    required int bpm,
    required MetronomePattern pattern,
    OnStart? onStart,
    List<SongPart>? parts,
    SongEnd end = SongEnd.stop,
  }) {
    if (onStart != null) _onStart = onStart;
    final multi = parts != null && parts.length > 1;
    _parts = multi ? parts : null;
    _end = end;
    _startPart = 0;
    if (multi) {
      bpm = parts.first.tempoStart;
      pattern = parts.first.pattern;
    }
    _load(bpm, pattern, run: true);
  }

  /// What a start (or a song loaded while playing) runs: a song's parts,
  /// else "When I press Start" when it has something to do.
  RunPlan? _runPlan(bool run) {
    _plan = null;
    if (!run) return null;
    if (_parts case final parts?) {
      return _plan = SongPlan(
        parts: parts,
        end: _end,
        onStart: _onStart,
        startPart: _startPart,
      );
    }
    return _onStart.runs ? _onStart : null;
  }

  /// [run]: with the count-in, speed up and stop after.
  void _load(int bpm, MetronomePattern pattern, {required bool run}) {
    _bpm = bpm.clamp(minBpm, maxBpm);
    _pattern = pattern;
    if (_playing) _runFrom = run ? _bpm : null;
    _scheduler.restartNow(
      bpm: _bpm.toDouble(),
      pattern: pattern,
      countInBars: run ? _onStart.countIn : 0,
      run: _playing ? _runPlan(run) : null,
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

  /// Starts on beat 1, with the count-in, speed up and stop after unless
  /// [run] is false.
  Future<void> play({bool run = true}) async {
    if (_playing) return;
    _playing = true;
    _runFrom = run ? _bpm : null;
    notifyListeners();
    await _start(run);
  }

  /// Stop, by hand or at a run's limit: after speed up, the tempo returns
  /// to where it started, so the next Start replays the same exercise.
  void stop() {
    if (!_playing) return;
    _scheduler.stop();
    _playing = false;
    final from = _runFrom;
    _runFrom = null;
    _plan = null;
    if (_parts case final parts?) {
      // Back to where Start begins, ready to play it again.
      _bpm = parts[_startPart].tempoStart;
      _pattern = parts[_startPart].pattern;
    } else if (from != null && _onStart.speedUp) {
      _bpm = from;
    }
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

  Future<void> _start(bool run) async {
    final countInBars = run ? _onStart.countIn : 0;
    final plan = _runPlan(run);
    try {
      final bpm = _bpm, pattern = _pattern;
      await _scheduler.start(
        bpm: bpm.toDouble(),
        pattern: pattern,
        countInBars: countInBars,
        run: plan,
      );
      // Changed while the device was starting, when the scheduler wasn't
      // running to take it: restart with what the screen shows.
      if (_bpm != bpm || _pattern != pattern) {
        _scheduler.restartNow(
          bpm: _bpm.toDouble(),
          pattern: _pattern,
          countInBars: countInBars,
          run: plan,
        );
      }
      _setAudioError(null);
    } catch (e) {
      _scheduler.stop();
      _playing = false;
      _runFrom = null;
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
