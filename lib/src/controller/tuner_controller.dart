import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/mic_input.dart';
import '../audio/pitch_detector.dart';
import '../model/tuner_note.dart';

/// The tuner page's state (ui-spec.md "Tuner"): the microphone permission,
/// listening only between [open] and [close] (and not while the app is in
/// the background), and the note heard, held through short gaps and gone
/// after [silenceHold] without one. Time is counted in samples heard, so
/// it follows the microphone exactly.
class TunerController extends ChangeNotifier {
  TunerController(this._mic, {required this.referenceA4, this.announce});

  /// True while the tuner page is open: the screen stays on.
  static final isOpen = ValueNotifier(false);

  static const silenceHold = Duration(seconds: 1);

  /// TalkBack's line ("A, 12 cents sharp") once it has held for [settle],
  /// at most once per [announceGap].
  static const settle = Duration(milliseconds: 500);
  static const announceGap = Duration(seconds: 1);

  /// Detections a reading is the median of (~100 ms at 48 kHz).
  static const _median = 5;

  final MicInput _mic;

  /// The Reference A4 in Hz, read at every detection.
  final int Function() referenceA4;
  final void Function(String message)? announce;

  MicPermission? _permission;
  bool _open = false;
  bool _foreground = true;
  bool _listening = false;
  StreamSubscription<Float32List>? _subscription;
  PitchDetector? _detector;
  Float32List _buffer = Float32List(0);
  int _filled = 0;
  int _rate = 48000;
  int _samplesHeard = 0;
  int _sinceDetect = 0;
  final _recent = <double>[];
  Duration? _heardAt;
  TunerNote? _note;
  String? _candidate;
  Duration _candidateSince = Duration.zero;
  String? _said;
  Duration? _saidAt;

  /// Null until checked.
  MicPermission? get permission => _permission;

  /// The note heard, or null: silence ("–", "Play a string").
  TunerNote? get note => _note;

  bool get listening => _listening;

  /// The page opened: asks for the microphone the first time, then
  /// listens if allowed.
  Future<void> open() async {
    _open = true;
    isOpen.value = true;
    _permission = await _mic.permission();
    notifyListeners();
    if (_permission == MicPermission.unknown && _open) {
      _permission = await _mic.request();
      notifyListeners();
    }
    await _sync();
  }

  /// "Allow microphone": asks again, or opens the app's settings when
  /// Android won't ask (the answer is read again on [resumed]).
  Future<void> allow() async {
    if (_permission == MicPermission.blocked) {
      await _mic.openSettings();
      return;
    }
    _permission = await _mic.request();
    notifyListeners();
    await _sync();
  }

  /// The app went to the background: the microphone stops at once.
  Future<void> paused() async {
    _foreground = false;
    await _sync();
  }

  /// Back in front, maybe from the app's settings with the permission now
  /// allowed.
  Future<void> resumed() async {
    _foreground = true;
    if (_open && _permission != MicPermission.granted) {
      _permission = await _mic.permission();
      notifyListeners();
    }
    await _sync();
  }

  /// The page closed.
  Future<void> close() async {
    _open = false;
    isOpen.value = false;
    await _sync();
  }

  Future<void> _sync() async {
    final want = _open && _foreground && _permission == MicPermission.granted;
    if (want == _listening) return;
    _listening = want;
    if (want) {
      final rate = await _mic.start();
      if (rate == null || !_listening) return;
      _rate = rate;
      _detector = PitchDetector(rate);
      _buffer = Float32List(_detector!.frameSize);
      _filled = 0;
      _sinceDetect = 0;
      _subscription = _mic.samples.listen(_take);
    } else {
      await _subscription?.cancel();
      _subscription = null;
      await _mic.stop();
      _recent.clear();
      _heardAt = null;
      _note = null;
      notifyListeners();
    }
  }

  /// Keeps the last frame of samples; detects every quarter frame.
  void _take(Float32List chunk) {
    final detector = _detector;
    if (detector == null) return;
    final size = _buffer.length;
    if (chunk.length >= size) {
      _buffer.setRange(0, size, chunk, chunk.length - size);
      _filled = size;
    } else {
      final keep = size - chunk.length;
      _buffer.setRange(0, keep, _buffer, chunk.length);
      _buffer.setRange(keep, size, chunk);
      _filled = (_filled + chunk.length).clamp(0, size);
    }
    _sinceDetect += chunk.length;
    _samplesHeard += chunk.length;
    if (_filled < size || _sinceDetect < size ~/ 4) return;
    _sinceDetect = 0;
    _heard(detector.detect(_buffer));
  }

  void _heard(double? hz) {
    final now = Duration(microseconds: _samplesHeard * 1000000 ~/ _rate);
    final before = _note;
    if (hz != null) {
      _recent.add(hz);
      if (_recent.length > _median) _recent.removeAt(0);
      final sorted = [..._recent]..sort();
      _note = TunerNote.fromHz(
        sorted[sorted.length ~/ 2],
        a4: referenceA4().toDouble(),
      );
      _heardAt = now;
    } else if (_heardAt != null && now - _heardAt! >= silenceHold) {
      _recent.clear();
      _heardAt = null;
      _note = null;
    }
    if (_note != before) notifyListeners();
    _maybeAnnounce(now);
  }

  void _maybeAnnounce(Duration now) {
    final line = _note?.spoken;
    if (line != _candidate) {
      _candidate = line;
      _candidateSince = now;
      return;
    }
    if (line == null || line == _said || now - _candidateSince < settle) {
      return;
    }
    if (_saidAt != null && now - _saidAt! < announceGap) return;
    _said = line;
    _saidAt = now;
    announce?.call(line);
  }

  @override
  void dispose() {
    _open = false;
    isOpen.value = false;
    if (_listening) {
      _listening = false;
      _subscription?.cancel();
      _mic.stop();
    }
    super.dispose();
  }
}
