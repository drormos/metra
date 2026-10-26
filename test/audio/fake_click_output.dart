import 'dart:async';

import 'package:metra/src/audio/click_output.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/metronome_pattern.dart';

class FakeClick {
  FakeClick(this.id, this.level, this.at, {this.raised = false});
  final int id;
  final StepLevel level;
  final Duration at;
  final bool raised;
  bool cancelled = false;
}

/// [ClickOutput] with a manually advanced engine clock.
class FakeClickOutput implements ClickOutput {
  Duration time = Duration.zero;
  final clicks = <FakeClick>[];
  bool prepared = false;
  int releaseCount = 0;

  /// Set to hold [prepare] until it completes (a slow device start).
  Completer<void>? prepareGate;

  /// Set to make [prepare] / [recover] throw.
  Object? deviceError;
  int recoverCount = 0;
  final failures = StreamController<void>.broadcast();
  ClickSound currentSound = ClickSound.woodblock;
  int previewCount = 0;

  List<FakeClick> get live => clicks.where((c) => !c.cancelled).toList();
  List<Duration> get liveTimes => live.map((c) => c.at).toList();

  @override
  Duration now() => time;

  @override
  Future<void> prepare() async {
    await prepareGate?.future;
    if (deviceError != null) throw deviceError!;
    prepared = true;
  }

  @override
  void release() {
    prepared = false;
    releaseCount++;
  }

  @override
  ClickHandle schedule(StepLevel level, Duration at, {bool raised = false}) {
    final click = FakeClick(clicks.length, level, at, raised: raised);
    clicks.add(click);
    return click;
  }

  /// Polyrhythm pulses, apart from [clicks].
  final pulses = <FakeClick>[];
  List<FakeClick> get livePulses => pulses.where((c) => !c.cancelled).toList();

  @override
  ClickHandle schedulePulse(StepLevel level, Duration at) {
    final pulse = FakeClick(pulses.length, level, at);
    pulses.add(pulse);
    return pulse;
  }

  @override
  void cancel(ClickHandle handle) => (handle as FakeClick).cancelled = true;

  @override
  set sound(ClickSound value) => currentSound = value;

  @override
  set volumes(ClickVolumes value) => currentVolumes = value;
  ClickVolumes currentVolumes = ClickVolumes.defaults;

  @override
  void preview() => previewCount++;

  @override
  Stream<void> get deviceFailures => failures.stream;

  @override
  Future<void> recover() async {
    recoverCount++;
    if (deviceError != null) throw deviceError!;
  }
}
