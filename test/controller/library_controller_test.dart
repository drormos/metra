import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';

import '../audio/fake_click_output.dart';

void main() {
  late Directory dir;
  late LibraryStore store;
  late LibraryController library;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('metra_library_test');
    store = LibraryStore(File('${dir.path}/library.json'));
    library = await LibraryController.load(store);
  });

  tearDown(() async {
    await library.flush(); // don't delete the folder under a pending save
    dir.deleteSync(recursive: true);
  });

  /// What a fresh app launch would see on disk.
  Future<LibraryController> reload() async {
    await library.flush();
    return LibraryController.load(LibraryStore(store.file));
  }

  final waltz = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

  test('songs: add, update, delete persist', () async {
    final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
    final b = library.addSong(
      name: 'B',
      bpm: 140,
      pattern: const MetronomePattern.standard(),
    );
    expect(a.id, isNot(b.id));
    library.updateSong(a.copyWith(bpm: 104));

    var loaded = await reload();
    expect(loaded.songs.map((s) => '${s.name}:${s.bpm}'), ['A:104', 'B:140']);
    expect(loaded.songById(a.id)?.pattern, waltz);

    library.deleteSong(a.id);
    loaded = await reload();
    expect(loaded.songs.map((s) => s.name), ['B']);
  });

  test('setlists: add, reorder, delete persist', () async {
    final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
    final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
    final gig = library.addSetlist('Gig');
    library.updateSetlist(gig.copyWith(songIds: [b.id, a.id]));

    var loaded = await reload();
    expect(loaded.setlists.single.name, 'Gig');
    expect(loaded.setlists.single.songIds, [b.id, a.id]);

    library.deleteSetlist(gig.id);
    loaded = await reload();
    expect(loaded.setlists, isEmpty);
    expect(loaded.songs, hasLength(2), reason: 'songs outlive setlists');
  });

  test('deleting a song removes it from setlists', () async {
    final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
    final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
    final gig = library.addSetlist('Gig');
    library.updateSetlist(gig.copyWith(songIds: [a.id, b.id, a.id]));
    library.deleteSong(a.id);
    expect(library.setlists.single.songIds, [b.id]);
  });

  test('changes notify listeners', () {
    var count = 0;
    library.addListener(() => count++);
    library.addSong(name: 'A', bpm: 100, pattern: waltz);
    library.addSetlist('Gig');
    expect(count, 2);
  });

  group('attach', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('restores and saves the last session', () async {
      library.attach(metronome);
      metronome.setBpm(87);
      metronome.setPattern(waltz);
      metronome.setVisualOffset(const Duration(milliseconds: 30));

      final loaded = await reload();
      final next = MetronomeController(FakeClickOutput());
      addTearDown(next.dispose);
      loaded.attach(next);
      expect(next.bpm, 87);
      expect(next.pattern, waltz);
      expect(next.visualOffset, const Duration(milliseconds: 30));
    });

    test('a fresh install keeps the defaults', () {
      library.attach(metronome);
      expect(metronome.bpm, 120);
      expect(metronome.visualOffset, Duration.zero);
    });
  });
}
