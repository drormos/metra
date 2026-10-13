import 'dart:async';

import 'package:metra/src/audio/click_output.dart';
import 'package:metra/src/model/metronome_pattern.dart';

class FakeClick {
  FakeClick(this.id, this.level, this.at);
  final int id;
  final StepLevel level;
  final Duration at;
  bool cancelled = false;
}

/// [ClickOutput] with a manually advanced engine clock.
class FakeClickOutput implements ClickOutput {
  Duration time = Duration.zero;
  final clicks = <FakeClick>[];
  bool prepared = false;
  int releaseCount = 0;

  /// Set to make [prepare] / [recover] throw.
  Object? deviceError;
  int recoverCount = 0;
  final failures = StreamController<void>.broadcast();

  List<FakeClick> get live => clicks.where((c) => !c.cancelled).toList();
  List<Duration> get liveTimes => live.map((c) => c.at).toList();

  @override
  Duration now() => time;

  @override
  Future<void> prepare() async {
    if (deviceError != null) throw deviceError!;
    prepared = true;
  }

  @override
  void release() {
    prepared = false;
    releaseCount++;
  }

  @override
  ClickHandle schedule(StepLevel level, Duration at) {
    final click = FakeClick(clicks.length, level, at);
    clicks.add(click);
    return click;
  }

  @override
  void cancel(ClickHandle handle) => (handle as FakeClick).cancelled = true;

  @override
  Stream<void> get deviceFailures => failures.stream;

  @override
  Future<void> recover() async {
    recoverCount++;
    if (deviceError != null) throw deviceError!;
  }
}
