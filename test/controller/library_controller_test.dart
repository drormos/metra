import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/library.dart';
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
      metronome.setClickSound(ClickSound.cowbell);

      final loaded = await reload();
      final next = MetronomeController(FakeClickOutput());
      addTearDown(next.dispose);
      loaded.attach(next);
      expect(next.bpm, 87);
      expect(next.pattern, waltz);
      expect(next.visualOffset, const Duration(milliseconds: 30));
      expect(next.clickSound, ClickSound.cowbell);
    });

    test('a fresh install keeps the defaults', () {
      library.attach(metronome);
      expect(metronome.bpm, 120);
      expect(metronome.visualOffset, Duration.zero);
    });
  });

  group('song panel', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('visible songs follow the selected setlist order', () {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
      final gig = library.addSetlist('Gig');
      library.addToSetlist(gig.id, b.id);
      library.addToSetlist(gig.id, a.id);

      expect(library.visibleSongs.map((s) => s.name), ['A', 'B']);
      library.selectSetlist(gig.id);
      expect(library.visibleSongs.map((s) => s.name), ['B', 'A']);
      library.selectSetlist(null);
      expect(library.selectedSetlist, isNull);
    });

    test('a deleted selected setlist falls back to all songs', () {
      final gig = library.addSetlist('Gig');
      library.selectSetlist(gig.id);
      library.deleteSetlist(gig.id);
      expect(library.selectedSetlist, isNull);
    });

    test('playSong loads tempo and pattern and marks it current', () {
      final a = library.addSong(name: 'A', bpm: 95, pattern: waltz);
      library.playSong(a, metronome);
      expect(metronome.bpm, 95);
      expect(metronome.pattern, waltz);
      expect(library.currentSong?.id, a.id);
    });

    test('saveCurrentAsSong adds to the selected setlist', () {
      final gig = library.addSetlist('Gig');
      library.selectSetlist(gig.id);
      metronome.setBpm(133);
      final song = library.saveCurrentAsSong('New', metronome);
      expect(song.bpm, 133);
      expect(library.selectedSetlist!.songIds, [song.id]);
      expect(library.currentSong?.id, song.id);
    });

    test('updateSongFromMetronome overwrites tempo and pattern', () {
      final a = library.addSong(
        name: 'A',
        bpm: 95,
        pattern: const MetronomePattern.standard(),
      );
      metronome.switchTo(bpm: 101, pattern: waltz);
      library.updateSongFromMetronome(a, metronome);
      expect(library.songById(a.id)!.bpm, 101);
      expect(library.songById(a.id)!.pattern, waltz);
    });

    test('reorder and remove setlist entries', () {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
      final c = library.addSong(name: 'C', bpm: 120, pattern: waltz);
      final gig = library.addSetlist('Gig');
      for (final s in [a, b, c]) {
        library.addToSetlist(gig.id, s.id);
      }
      library.reorderSetlist(gig.id, 0, 2); // A to the end
      expect(library.setlists.single.songIds, [b.id, c.id, a.id]);
      library.reorderSetlist(gig.id, 2, 0); // A back to the front
      expect(library.setlists.single.songIds, [a.id, b.id, c.id]);
      library.removeFromSetlist(gig.id, 1);
      expect(library.setlists.single.songIds, [a.id, c.id]);
      expect(library.songs, hasLength(3), reason: 'song itself stays');
    });
  });

  group('next / previous', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('steps through the visible songs and stops at the ends', () {
      for (final (name, bpm) in [('A', 100), ('B', 110), ('C', 120)]) {
        library.addSong(name: name, bpm: bpm, pattern: waltz);
      }
      expect(library.hasPrevious, isFalse);
      library.nextSong(metronome); // nothing current: first song
      expect(library.currentSong?.name, 'A');
      expect(metronome.bpm, 100);
      library
        ..nextSong(metronome)
        ..nextSong(metronome)
        ..nextSong(metronome); // past the end: stays on C
      expect(library.currentSong?.name, 'C');
      expect(library.hasNext, isFalse);
      library.previousSong(metronome);
      expect(library.currentSong?.name, 'B');
      expect(metronome.bpm, 110);
    });

    test('follows setlist order, including a song listed twice', () {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
      final gig = library.addSetlist('Gig');
      for (final id in [a.id, b.id, a.id]) {
        library.addToSetlist(gig.id, id);
      }
      library.selectSetlist(gig.id);
      library
        ..nextSong(metronome)
        ..nextSong(metronome)
        ..nextSong(metronome);
      expect(library.currentIndex, 2, reason: 'the second A, not the first');
      expect(library.hasNext, isFalse);
      library.previousSong(metronome);
      expect(library.currentSong?.name, 'B');
    });

    test('nothing to step through when empty', () {
      expect(library.hasNext, isFalse);
      library.nextSong(metronome);
      expect(library.currentSong, isNull);
    });
  });

  test('theme mode persists', () async {
    expect(library.themeMode, ThemeMode.system);
    library.setThemeMode(ThemeMode.light);
    expect((await reload()).themeMode, ThemeMode.light);
  });

  test(
    'a burst of changes is written as few saves of the latest state',
    () async {
      final metronome = MetronomeController(FakeClickOutput());
      addTearDown(metronome.dispose);
      var saves = 0;
      final counted = await LibraryController.load(
        _CountingStore(store.file, () => saves++),
      );
      counted.attach(metronome);
      for (var bpm = 60; bpm <= 160; bpm++) {
        metronome.setBpm(bpm); // like a tempo drag
      }
      await counted.flush();
      expect(saves, lessThanOrEqualTo(2), reason: '101 changes, coalesced');

      final check = MetronomeController(FakeClickOutput());
      addTearDown(check.dispose);
      (await LibraryController.load(LibraryStore(store.file))).attach(check);
      expect(check.bpm, 160, reason: 'the latest state was saved');
    },
  );
}

class _CountingStore extends LibraryStore {
  _CountingStore(super.file, this.onSave);
  final void Function() onSave;

  @override
  Future<void> save(Library library) {
    onSave();
    return super.save(library);
  }
}
