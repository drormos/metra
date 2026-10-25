import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/keep_awake.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';

import '../audio/fake_click_output.dart';

void main() {
  late Directory dir;
  late LibraryController library;
  late MetronomeController metronome;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('metra_awake_test');
    library = await LibraryController.load(
      LibraryStore(File('${dir.path}/library.json')),
    );
    metronome = MetronomeController(FakeClickOutput());
  });

  tearDown(() async {
    metronome.dispose();
    await library.flush();
    dir.deleteSync(recursive: true);
  });

  test('while Metra is open (default): awake, playing or not', () async {
    final calls = <bool>[];
    keepScreenAwake(metronome, library, (awake) async => calls.add(awake));
    await metronome.play();
    metronome.stop();
    expect(calls, [true]);
  });

  test('only while playing: toggled once per start / stop', () async {
    library.setKeepScreenOn(KeepScreenOn.whilePlaying);
    final calls = <bool>[];
    keepScreenAwake(metronome, library, (awake) async => calls.add(awake));
    metronome.setBpm(100); // not a start/stop change
    await metronome.play();
    metronome.setBpm(110);
    metronome.stop();
    expect(calls, [false, true, false]);
  });

  test('stage mode keeps it on whatever the setting', () async {
    library.setKeepScreenOn(KeepScreenOn.whilePlaying);
    final song = library.addSong(
      name: 'A',
      bpm: 100,
      pattern: const MetronomePattern.standard(),
    );
    final set = library.saveSetlist(name: 'Set', songIds: [song.id]);
    library.loadSetlist(set.id, metronome);
    final calls = <bool>[];
    keepScreenAwake(metronome, library, (awake) async => calls.add(awake));
    library.enterStageMode(metronome);
    library.exitStageMode();
    expect(calls, [false, true, false]);
  });

  test('a failing platform call does not throw', () async {
    keepScreenAwake(metronome, library, (_) => Future.error('unsupported'));
    library.setKeepScreenOn(KeepScreenOn.whilePlaying);
    await metronome.play();
    metronome.stop();
  });
}
