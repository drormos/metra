import 'dart:async';
import 'dart:typed_data';

import 'package:metra/src/audio/mic_input.dart';

/// A microphone for tests: a permission to set, what the dialog answers,
/// and samples pushed by hand.
class FakeMicInput implements MicInput {
  FakeMicInput({this.state = MicPermission.unknown, this.answer});

  MicPermission state;

  /// What the permission dialog answers (null: keep [state]).
  MicPermission? answer;
  int requests = 0;
  int settingsOpened = 0;
  int rate = 48000;
  bool running = false;
  final _samples = StreamController<Float32List>.broadcast(sync: true);

  void push(Float32List chunk) => _samples.add(chunk);

  @override
  Stream<Float32List> get samples => _samples.stream;

  @override
  Future<MicPermission> permission() async => state;

  @override
  Future<MicPermission> request() async {
    requests++;
    state = answer ?? state;
    return state;
  }

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  Future<int?> start() async {
    running = true;
    return rate;
  }

  @override
  Future<void> stop() async => running = false;
}
