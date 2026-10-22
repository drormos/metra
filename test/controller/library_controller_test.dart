import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
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

    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library.deleteSong(a.id, metronome);
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
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library.deleteSong(a.id, metronome);
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
      const quiet = ClickVolumes(accent: 0.7, beat: 0.6, subdivision: 0.1);
      metronome.setVolumes(quiet);

      final loaded = await reload();
      final next = MetronomeController(FakeClickOutput());
      addTearDown(next.dispose);
      loaded.attach(next);
      expect(next.bpm, 87);
      expect(next.pattern, waltz);
      expect(next.visualOffset, const Duration(milliseconds: 30));
      expect(next.clickSound, ClickSound.cowbell);
      expect(next.volumes, quiet);
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
      library.setActiveSetlist(gig.id);
      expect(library.visibleSongs.map((s) => s.name), ['B', 'A']);
      library.setActiveSetlist(null);
      expect(library.activeSetlist, isNull);
    });

    test('a deleted selected setlist falls back to all songs', () {
      final gig = library.addSetlist('Gig');
      library.setActiveSetlist(gig.id);
      library.deleteSetlist(gig.id);
      expect(library.activeSetlist, isNull);
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
      library.setActiveSetlist(gig.id);
      metronome.setBpm(133);
      final song = library.saveCurrentAsSong('New', metronome);
      expect(song.bpm, 133);
      expect(library.activeSetlist!.songIds, [song.id]);
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

    test('reorder and remove setlist entries; saved at once', () async {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
      final c = library.addSong(name: 'C', bpm: 120, pattern: waltz);
      final gig = library.addSetlist('Gig');
      for (final s in [a, b, c]) {
        library.addToSetlist(gig.id, s.id);
      }
      library.reorderSetlist(gig.id, 0, 2); // A to the end
      expect(library.setlists.single.songIds, [b.id, c.id, a.id]);
      expect((await reload()).setlists.single.songIds, [b.id, c.id, a.id]);
      library.reorderSetlist(gig.id, 2, 0); // A back to the front
      expect(library.setlists.single.songIds, [a.id, b.id, c.id]);
      library.removeFromSetlist(gig.id, 1);
      expect(library.setlists.single.songIds, [a.id, c.id]);
      expect(library.songs, hasLength(3), reason: 'song itself stays');
    });
  });

  test('reordering the loaded set keeps the current song current', () {
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
    final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
    final gig = library.addSetlist('Gig');
    for (final s in [a, b, a]) {
      library.addToSetlist(gig.id, s.id);
    }
    library.setActiveSetlist(gig.id);
    library.playSong(a, metronome, index: 2); // the second A
    library.reorderSetlist(gig.id, 1, 0); // B to the front: B, A, A
    expect(library.currentIndex, 2);
    library.reorderSetlist(gig.id, 2, 0); // the current A to the front
    expect(library.currentIndex, 0);
    expect(library.hasNext, isTrue);
    expect(library.hasPrevious, isFalse);
  });

  group('next / previous', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('steps through the setlist and stops at the ends', () {
      final gig = library.addSetlist('Gig');
      for (final (name, bpm) in [('A', 100), ('B', 110), ('C', 120)]) {
        final song = library.addSong(name: name, bpm: bpm, pattern: waltz);
        library.addToSetlist(gig.id, song.id);
      }
      library.setActiveSetlist(gig.id);
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
      library.setActiveSetlist(gig.id);
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

  group('modes', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('first launch is Free play: no stepping', () {
      library.addSong(name: 'A', bpm: 100, pattern: waltz);
      library.addSong(name: 'B', bpm: 110, pattern: waltz);
      expect(library.activeSetlist, isNull);
      expect(library.hasNext, isFalse);
      library.nextSong(metronome);
      expect(library.currentSong, isNull);
    });

    test('a library song in Free play shows as current, mode unchanged', () {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      library.playSong(a, metronome);
      expect(library.currentSong?.name, 'A');
      expect(library.activeSetlist, isNull);
    });

    test(
      'switching to Free play detaches the song; the click carries on',
      () async {
        final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
        final gig = library.addSetlist('Gig');
        library
          ..addToSetlist(gig.id, a.id)
          ..setActiveSetlist(gig.id)
          ..nextSong(metronome);
        await metronome.play();
        metronome.nudge(5); // an unsaved change
        library.setActiveSetlist(null);
        expect(metronome.isPlaying, isTrue);
        expect(metronome.bpm, 105, reason: 'unsaved change kept');
        expect(metronome.pattern, waltz);
        expect(library.activeSetlist, isNull);
        expect(library.currentSong, isNull);
        expect(library.singleSong, isFalse);
        expect(library.songChanged(metronome), isFalse);
        expect(library.songById(a.id)!.bpm, 100, reason: 'song untouched');
      },
    );

    test(
      'a library song outside a set is Single song; Go free detaches',
      () async {
        final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
        library.playSong(a, metronome);
        expect(library.singleSong, isTrue);
        metronome.cycleBeat(1);
        final changed = metronome.pattern;
        library.detachSong();
        expect(library.singleSong, isFalse);
        expect(library.currentSong, isNull);
        expect(metronome.pattern, changed);
        expect(library.songById(a.id)!.pattern, waltz);
      },
    );

    test('reopens in Single song', () async {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      library.playSong(a, metronome);
      final reopened = await reload();
      expect(reopened.singleSong, isTrue);
      expect(reopened.currentSong?.id, a.id);
    });

    test('a library song always enters Single song, unloading the set', () {
      final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      final gig = library.addSetlist('Gig');
      library
        ..addToSetlist(gig.id, a.id)
        ..setActiveSetlist(gig.id)
        ..playSingleSong(a, metronome);
      expect(library.activeSetlist, isNull);
      expect(library.singleSong, isTrue);
      expect(metronome.bpm, 100);
    });

    test(
      'a current song removed from the set: no current song, next = 1st',
      () {
        final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
        final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
        final gig = library.addSetlist('Gig');
        library
          ..addToSetlist(gig.id, a.id)
          ..addToSetlist(gig.id, b.id)
          ..setActiveSetlist(gig.id)
          ..nextSong(metronome)
          ..nextSong(metronome); // B
        library.removeFromSetlist(gig.id, 1);
        expect(library.currentSong, isNull);
        expect(library.currentIndex, -1);
        expect(library.songChanged(metronome), isFalse);
        library.nextSong(metronome);
        expect(library.currentSong?.name, 'A');
      },
    );

    test('reopens in the same setlist at the same song', () async {
      final gig = library.addSetlist('Gig');
      for (final name in ['A', 'B', 'C']) {
        final song = library.addSong(name: name, bpm: 100, pattern: waltz);
        library.addToSetlist(gig.id, song.id);
      }
      library
        ..setActiveSetlist(gig.id)
        ..nextSong(metronome)
        ..nextSong(metronome);
      final loaded = await reload();
      expect(loaded.activeSetlist?.name, 'Gig');
      expect(loaded.currentSong?.name, 'B');
      expect(loaded.currentIndex, 1);
    });

    test('reopens in Free play when it was left there', () async {
      final gig = library.addSetlist('Gig');
      library
        ..setActiveSetlist(gig.id)
        ..setActiveSetlist(null);
      expect((await reload()).activeSetlist, isNull);
    });
  });

  group('changes to a loaded song', () {
    late MetronomeController metronome;
    late Song song;

    setUp(() {
      metronome = MetronomeController(FakeClickOutput());
      library.attach(metronome);
      song = library.addSong(name: 'A', bpm: 100, pattern: waltz);
      library.playSong(song, metronome);
    });
    tearDown(() => metronome.dispose());

    test('nothing loaded, or just loaded: no changes', () {
      expect(library.songChanged(metronome), isFalse);
      library.deleteSong(song.id, metronome);
      metronome.nudge(1);
      expect(library.songChanged(metronome), isFalse, reason: 'no song');
    });

    test('a main-screen change shows; the song is not touched', () {
      metronome.cycleBeat(1);
      expect(library.songChanged(metronome), isTrue);
      expect(library.songById(song.id)!.pattern, waltz);
    });

    test('Save to song stores the changes', () {
      metronome
        ..nudge(5)
        ..setSubdivision(2);
      library.saveToSong(metronome);
      expect(library.songChanged(metronome), isFalse);
      final saved = library.songById(song.id)!;
      expect(saved.bpm, 105);
      expect(saved.pattern.stepsPerBeat, 2);
    });

    test('Revert restores the stored values', () {
      metronome
        ..nudge(5)
        ..setMeter(4, 4);
      library.revertSong(metronome);
      expect(library.songChanged(metronome), isFalse);
      expect(metronome.bpm, 100);
      expect(metronome.pattern, waltz);
    });

    test('loading another song discards them', () {
      final other = library.addSong(name: 'B', bpm: 80, pattern: waltz);
      metronome.nudge(5);
      library.playSong(other, metronome);
      expect(library.songChanged(metronome), isFalse);
      expect(library.songById(song.id)!.bpm, 100);
    });

    test('they survive closing the app', () async {
      metronome.nudge(5);
      final reopened = await reload();
      final fresh = MetronomeController(FakeClickOutput());
      addTearDown(fresh.dispose);
      reopened.attach(fresh);
      expect(fresh.bpm, 105);
      expect(reopened.songChanged(fresh), isTrue);
    });
  });

  group('save as new song', () {
    late MetronomeController metronome;
    late Song original;
    late Setlist gig;

    setUp(() {
      metronome = MetronomeController(FakeClickOutput());
      original = library.addSong(name: 'Dead Weight', bpm: 100, pattern: waltz);
      final other = library.addSong(name: 'Other', bpm: 90, pattern: waltz);
      gig = library.saveSetlist(
        name: 'Gig',
        songIds: [other.id, original.id, other.id],
      );
      library
        ..setActiveSetlist(gig.id)
        ..playSong(original, metronome, index: 1);
      metronome.nudge(5); // the unsaved change being saved
    });
    tearDown(() => metronome.dispose());

    List<String> names() => [
      for (final id in library.setlists.single.songIds)
        library.songById(id)!.name,
    ];

    test('copy names count on from 2', () {
      expect(library.copyName(original), 'Dead Weight 2');
      final copy = library.addSong(
        name: 'Dead Weight 2',
        bpm: 1,
        pattern: waltz,
      );
      expect(library.copyName(original), 'Dead Weight 3');
      expect(library.copyName(copy), 'Dead Weight 3', reason: 'no "2 2"');
    });

    void expectLoaded(Song song) {
      expect(library.currentSong?.id, song.id);
      expect(
        library.songChanged(metronome),
        isFalse,
        reason: 'nothing unsaved',
      );
      expect(metronome.bpm, 105, reason: 'the click carries on');
      expect(library.songById(original.id)!.bpm, 100, reason: 'untouched');
    }

    test('replace: same position in the set', () {
      final song = library.saveAsNewSong('DW 2', metronome);
      expect(names(), ['Other', 'DW 2', 'Other']);
      expect(library.currentIndex, 1);
      expect(song.bpm, 105);
      expectLoaded(song);
    });

    test('add after: both stay', () {
      final song = library.saveAsNewSong(
        'DW 2',
        metronome,
        placement: SongPlacement.addAfter,
      );
      expect(names(), ['Other', 'Dead Weight', 'DW 2', 'Other']);
      expect(library.currentIndex, 2);
      expectLoaded(song);
    });

    test("don't add: leaves the set for Single song", () {
      final song = library.saveAsNewSong(
        'DW 2',
        metronome,
        placement: SongPlacement.none,
      );
      expect(names(), ['Other', 'Dead Weight', 'Other']);
      expect(library.activeSetlist, isNull);
      expect(library.singleSong, isTrue);
      expectLoaded(song);
    });

    test('from Free play: Single song with the new song', () {
      library.detachSong();
      final song = library.saveAsNewSong('Song 1', metronome);
      expect(library.singleSong, isTrue);
      expect(library.currentSong?.id, song.id);
      expect(song.bpm, 105);
    });
  });

  group('setlist editing', () {
    test('saveSetlist creates, then updates in place', () async {
      final a = library.addSong(name: 'a', bpm: 100, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 110, pattern: waltz);
      final created = library.saveSetlist(
        name: 'Gig',
        songIds: [b.id, a.id, b.id],
      );
      expect(library.setlists.single.songIds, [b.id, a.id, b.id]);
      library.saveSetlist(id: created.id, name: 'Gig 2', songIds: [a.id]);
      final loaded = await reload();
      expect(loaded.setlists.single.name, 'Gig 2');
      expect(loaded.setlists.single.songIds, [a.id]);
    });

    test('songsAZ ignores case; setlistsUsing finds every set', () {
      final c = library.addSong(name: 'charlie', bpm: 1 * 100, pattern: waltz);
      final a = library.addSong(name: 'Alpha', bpm: 100, pattern: waltz);
      library.addSong(name: 'bravo', bpm: 100, pattern: waltz);
      expect(library.songsAZ.map((s) => s.name), ['Alpha', 'bravo', 'charlie']);
      library.saveSetlist(name: 'One', songIds: [a.id]);
      library.saveSetlist(name: 'Two', songIds: [c.id, a.id]);
      expect(library.setlistsUsing(a.id).map((l) => l.name), ['One', 'Two']);
      expect(library.setlistsUsing(c.id).map((l) => l.name), ['Two']);
    });
  });

  test('songs record when they were edited', () async {
    final a = library.addSong(name: 'A', bpm: 100, pattern: waltz);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final b = library.addSong(name: 'B', bpm: 100, pattern: waltz);
    expect(a.editedAt, isNotNull);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    library.updateSong(library.songById(a.id)!.copyWith(bpm: 101));
    expect(library.songById(a.id)!.editedAt!.isAfter(b.editedAt!), isTrue);
    expect(
      (await reload()).songById(b.id)!.editedAt,
      b.editedAt!.copyWith(microsecond: 0),
    );
  });

  test('a failed save is reported until a save works again', () async {
    await library.flush();
    final blocker = Directory(store.file.path);
    if (store.file.existsSync()) store.file.deleteSync();
    blocker.createSync(); // the rename onto it fails
    var notified = 0;
    library.addListener(() => notified++);
    library.setVibrate(false);
    await library.flush();
    expect(library.saveFailed, isTrue);
    blocker.deleteSync();
    library.setVibrate(true);
    await library.flush();
    expect(library.saveFailed, isFalse);
    expect(notified, 4); // two changes, failed, recovered
  });

  test('Single song steps through the library A–Z; Free play does not', () {
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    final b = library.addSong(name: 'b', bpm: 100, pattern: waltz);
    library
      ..addSong(name: 'A', bpm: 90, pattern: waltz)
      ..addSong(name: 'C', bpm: 120, pattern: waltz);
    expect(library.hasNext, isFalse, reason: 'Free play');
    library.playSingleSong(b, metronome);
    expect([library.songBefore?.name, library.songAfter?.name], ['A', 'C']);
    library.nextSong(metronome);
    expect(library.currentSong?.name, 'C');
    expect(library.singleSong, isTrue);
    expect(library.hasNext, isFalse, reason: 'stops at the end');
    library
      ..previousSong(metronome)
      ..previousSong(metronome)
      ..previousSong(metronome);
    expect(library.currentSong?.name, 'A');
    expect(metronome.bpm, 90);
  });

  group('mode tabs', () {
    late MetronomeController metronome;

    setUp(() => metronome = MetronomeController(FakeClickOutput()));
    tearDown(() => metronome.dispose());

    test('Setlists: the set used this session, at the same song', () {
      final a = library.addSong(name: 'A', bpm: 90, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 100, pattern: waltz);
      final set = library.saveSetlist(name: 'Gig', songIds: [a.id, b.id]);
      library
        ..loadSetlist(set.id, metronome)
        ..nextSong(metronome) // B
        ..detachSong();
      metronome.setBpm(140);
      library.openSetlistsTab(metronome);
      expect(library.activeSetlist?.id, set.id);
      expect(library.currentSong?.name, 'B');
      expect(metronome.bpm, 100);
      expect(library.tab, ModeTab.setlists);
    });

    test('Setlists: otherwise the most recently used set at song 1', () {
      final a = library.addSong(name: 'A', bpm: 90, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 100, pattern: waltz);
      library.saveSetlist(name: 'Old', songIds: [b.id]);
      final recent = library.saveSetlist(name: 'Recent', songIds: [a.id, b.id]);
      library.updateSetlist(recent.copyWith(playedAt: DateTime.now()));
      library.openSetlistsTab(metronome);
      expect(library.activeSetlist?.name, 'Recent');
      expect(library.currentSong?.name, 'A');
    });

    test('Songs: the song used this session, else the latest played', () {
      final a = library.addSong(name: 'A', bpm: 90, pattern: waltz);
      final b = library.addSong(name: 'B', bpm: 100, pattern: waltz);
      final set = library.saveSetlist(name: 'Gig', songIds: [b.id]);
      library.openSongsTab(metronome);
      expect(library.currentSong?.name, 'A', reason: 'none played: first A–Z');
      library
        ..playSingleSong(b, metronome)
        ..playSingleSong(a, metronome)
        ..loadSetlist(set.id, metronome) // plays B, in the set
        ..openSongsTab(metronome);
      expect(library.currentSong?.name, 'A', reason: "this session's song");
      expect(library.singleSong, isTrue);
    });

    test(
      'a fresh launch has no session; the latest played song counts',
      () async {
        final a = library.addSong(name: 'A', bpm: 90, pattern: waltz);
        final b = library.addSong(name: 'B', bpm: 100, pattern: waltz);
        final set = library.saveSetlist(name: 'Gig', songIds: [a.id, b.id]);
        library
          ..playSingleSong(a, metronome)
          ..loadSetlist(set.id, metronome); // A again
        // Saved to the millisecond: keep the two loads apart.
        await Future<void>.delayed(const Duration(milliseconds: 2));
        library.nextSong(metronome); // B, played last
        final next = await reload();
        next
          ..attach(metronome)
          ..detachSong() // as main does
          ..openSongsTab(metronome);
        expect(next.currentSong?.name, 'B', reason: 'latest played, saved');
        next.openSetlistsTab(metronome);
        expect(next.currentSong?.name, 'A', reason: 'no session set: song 1');
        await next.flush();
      },
    );

    test('empty tabs: nothing to load, the tab shows; the click is kept', () {
      metronome.setBpm(77);
      library.openSongsTab(metronome);
      expect(library.tab, ModeTab.songs);
      library.openSetlistsTab(metronome);
      expect(library.tab, ModeTab.setlists);
      library.detachSong();
      expect(library.tab, ModeTab.freePlay);
      expect(metronome.bpm, 77);
    });
  });

  test('a polyrhythm change is an unsaved change to the loaded song', () {
    final metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    final song = library.addSong(name: 'S', bpm: 100, pattern: waltz);
    library.playSingleSong(song, metronome);
    metronome.setPolyrhythm(2);
    expect(library.songChanged(metronome), isTrue);
    library.revertSong(metronome);
    expect(metronome.pattern.polyrhythm, 0);
    expect(library.songChanged(metronome), isFalse);
  });

  group('set panel edits', () {
    late MetronomeController metronome;
    late Setlist gig;

    setUp(() {
      metronome = MetronomeController(FakeClickOutput());
      final ids = [
        for (final (i, n) in ['A', 'B', 'C', 'D'].indexed)
          library.addSong(name: n, bpm: 100 + i, pattern: waltz).id,
      ];
      gig = library.saveSetlist(name: 'Gig', songIds: ids);
      library
        ..loadSetlist(gig.id, metronome)
        ..nextSong(metronome)
        ..nextSong(metronome); // C, 3 of 4
    });
    tearDown(() => metronome.dispose());

    test('removing before the current song shifts the position', () {
      final b = library.visibleSongs[1].id;
      library.removeSongAt(gig.id, 1, metronome);
      expect(library.currentSong?.name, 'C');
      expect(library.currentIndex, 1);
      library.insertSongAt(gig.id, 1, b, metronome);
      expect(library.currentIndex, 2, reason: 'undo restores it');
      expect(library.visibleSongs.map((s) => s.name), ['A', 'B', 'C', 'D']);
    });

    test('removing the current song: the one now in its place loads; '
        'Undo makes it current again', () {
      metronome.nudge(5); // an unsaved change, discarded
      final c = library.currentSong!.id;
      library.removeSongAt(gig.id, 2, metronome);
      expect(library.currentSong?.name, 'D', reason: '3/4 → D as 3/3');
      expect(library.currentIndex, 2);
      expect(metronome.bpm, 103, reason: "D's tempo");
      library.insertSongAt(gig.id, 2, c, metronome, wasCurrent: true);
      expect(library.currentSong?.name, 'C');
      expect(library.currentIndex, 2);
      expect(library.visibleSongs.map((s) => s.name), ['A', 'B', 'C', 'D']);
    });

    test('the last song removed: the new last loads; an empty set stays '
        'loaded with no song and the click as it is', () {
      library.nextSong(metronome); // D, 4/4
      library.removeSongAt(gig.id, 3, metronome);
      expect(library.currentSong?.name, 'C', reason: 'the new last');
      for (var i = 0; i < 3; i++) {
        library.removeSongAt(gig.id, library.currentIndex, metronome);
      }
      expect(library.activeSetlist?.id, gig.id, reason: 'still setlist mode');
      expect(library.visibleSongs, isEmpty);
      expect(library.currentSong, isNull);
      expect(library.tab, ModeTab.setlists);
      expect(metronome.bpm, 100, reason: 'the click keeps A\'s tempo');
    });

    test('while playing the replacement restarts on beat 1; stopped it just '
        'loads', () async {
      await metronome.play();
      library.removeSongAt(gig.id, 2, metronome);
      expect(metronome.isPlaying, isTrue);
      expect(metronome.bpm, 103);
      metronome.stop();
      library.removeSongAt(gig.id, 2, metronome); // D, the last
      expect(metronome.isPlaying, isFalse);
      expect(library.currentSong?.name, 'B');
    });

    test('rename: an empty name keeps the old one', () {
      library.renameSetlist(gig.id, '  ');
      expect(library.activeSetlist?.name, 'Gig');
      library.renameSetlist(gig.id, ' Tour ');
      expect(library.activeSetlist?.name, 'Tour');
    });

    test('deleting another set: Undo restores it in place; the Setlists '
        'tab falls back from a deleted session set', () {
      final other = library.saveSetlist(name: 'Other', songIds: const []);
      final deleted = library.deleteSetlistAt(other.id, metronome)!;
      expect(deleted.index, 1);
      expect(library.activeSetlist?.id, gig.id, reason: 'unchanged');
      library.restoreSetlist(deleted, metronome);
      expect(library.setlists.map((l) => l.id), [gig.id, other.id]);
      library
        ..loadSetlist(other.id, metronome)
        ..detachSong()
        ..deleteSetlistAt(other.id, metronome)
        ..openSetlistsTab(metronome);
      expect(library.activeSetlist?.id, gig.id);
    });

    test('deleting the loaded set: the most recently used other set loads '
        'at song 1; Undo brings it back at the same song', () {
      final tour = library.saveSetlist(
        name: 'Tour',
        songIds: [library.songs[3].id, library.songs[0].id],
      );
      final quiet = library.saveSetlist(name: 'Quiet', songIds: const []);
      library
        ..loadSetlist(tour.id, metronome)
        ..loadSetlist(gig.id, metronome)
        ..nextSong(metronome); // Gig at B; Tour used most recently before
      final deleted = library.deleteSetlistAt(gig.id, metronome)!;
      expect(library.activeSetlist?.id, tour.id);
      expect(library.currentSong?.name, 'D', reason: 'song 1');
      library.restoreSetlist(deleted, metronome);
      expect(library.activeSetlist?.id, gig.id);
      expect(library.currentSong?.name, 'B');
      // The last set goes: setlist mode with no set, click unchanged.
      library
        ..deleteSetlistAt(quiet.id, metronome)
        ..deleteSetlistAt(tour.id, metronome)
        ..deleteSetlistAt(gig.id, metronome);
      expect(library.setlists, isEmpty);
      expect(library.tab, ModeTab.setlists);
      expect(metronome.bpm, 101, reason: "B's tempo stays");
    });

    test('deleting the loaded song in a set: it leaves the set and the next '
        'takes over; Undo restores it everywhere, current', () {
      final deleted = library.deleteSongForUndo(
        library.currentSong!.id,
        metronome,
      )!;
      expect(library.currentSong?.name, 'D');
      expect(library.visibleSongs.map((s) => s.name), ['A', 'B', 'D']);
      library.restoreSong(deleted, metronome);
      expect(library.currentSong?.name, 'C');
      expect(library.currentIndex, 2);
    });

    test('deleting the loaded single song: the next A–Z, else the previous; '
        'an empty library stays in Single song', () {
      final songs = library.songsAZ; // A B C D
      library.playSingleSong(songs[1], metronome);
      final deleted = library.deleteSongForUndo(songs[1].id, metronome)!;
      expect(library.currentSong?.name, 'C', reason: 'next A–Z');
      expect(library.singleSong, isTrue);
      library.restoreSong(deleted, metronome);
      expect(library.currentSong?.name, 'B', reason: 'Undo: current again');
      library.playSingleSong(songs[3], metronome);
      library.deleteSongForUndo(songs[3].id, metronome);
      expect(library.currentSong?.name, 'C', reason: 'last: the previous');
      library.deleteSongs({for (final s in library.songs) s.id}, metronome);
      expect(library.songs, isEmpty);
      expect(library.tab, ModeTab.songs);
      expect(metronome.bpm, 102, reason: "C's tempo stays");
    });

    test('the swipe hint flag is saved', () async {
      expect(library.swipeHintSeen, isFalse);
      library.markSwipeHintSeen();
      expect((await reload()).swipeHintSeen, isTrue);
    });

    test('one-time tips are saved', () async {
      expect(library.tipSeen('edit-first-load'), isFalse);
      library.markTipSeen('edit-first-load');
      final loaded = await reload();
      expect(loaded.tipSeen('edit-first-load'), isTrue);
      expect(loaded.tipSeen('edit-first-change'), isFalse);
    });
  });

  group('example content (fresh install)', () {
    test('a fresh install is noticed; a saved library is not', () async {
      expect(library.freshInstall, isTrue);
      library.addSong(name: 'A', bpm: 100, pattern: waltz);
      expect((await reload()).freshInstall, isFalse);
    });

    test('4 example songs and "Try me" with all four, in order', () async {
      library.addExamples();
      expect(library.songs.map((s) => (s.name, s.bpm)), [
        ('Example · Rock', 120),
        ('Example · Waltz', 90),
        ('Example · Shuffle', 100),
        ('Example · Odd', 140),
      ]);
      final [rock, waltz3, shuffle, odd] = library.songs;
      expect(rock.pattern.timeSignature, '4/4');
      expect(rock.pattern.beatLevels.first, StepLevel.accent);
      expect(waltz3.pattern.timeSignature, '3/4');
      expect(shuffle.pattern.stepsPerBeat, 3);
      expect(odd.pattern.timeSignature, '7/8');
      expect(
        [
          for (final (i, l) in odd.pattern.beatLevels.indexed)
            if (l == StepLevel.accent) i + 1,
        ],
        [1, 3, 5],
      );
      expect(library.setlists.single.name, 'Try me');
      expect(library.setlists.single.songIds, [
        for (final s in library.songs) s.id,
      ]);
      expect(library.activeSetlist, isNull, reason: 'still Free play');
    });

    test('never re-created after deletion (stored flag)', () async {
      final metronome = MetronomeController(FakeClickOutput());
      addTearDown(metronome.dispose);
      library.addExamples();
      library.deleteSongs({for (final s in library.songs) s.id}, metronome);
      library.deleteSetlist(library.setlists.single.id);
      final loaded = await reload();
      loaded.addExamples();
      expect(loaded.songs, isEmpty);
      expect(loaded.setlists, isEmpty);
    });

    test('never added to a library that already has songs', () {
      library.addSong(name: 'Mine', bpm: 100, pattern: waltz);
      library.addExamples();
      expect(library.songs.map((s) => s.name), ['Mine']);
      expect(library.setlists, isEmpty);
    });
  });
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
