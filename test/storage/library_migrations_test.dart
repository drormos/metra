import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/library_migrations.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/storage/library_store.dart';

/// Golden files: one library in every format that shipped (test/fixtures/,
/// rebuilt from each release's toJson), loaded through the store, checked,
/// re-saved as the latest version, and loaded again unchanged.
void main() {
  late Directory dir;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_migrations');
    store = LibraryStore(File('${dir.path}/library.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
  Map<String, Object?> decode(File f) =>
      jsonDecode(f.readAsStringSync()) as Map<String, Object?>;

  /// Loads [name] as the app would, re-saves it, and checks the result is
  /// version 2 in two files that load to the same library.
  Future<Library> loadAndResave(String name) async {
    store.file.writeAsStringSync(fixture(name));
    final first = await store.load();
    expect(store.backupFile.existsSync(), isTrue, reason: 'v1 kept aside');
    expect(
      store.backupFile.readAsStringSync(),
      fixture(name),
      reason: 'the original, byte for byte',
    );
    await store.save(first);
    expect(store.backupFile.existsSync(), isFalse, reason: 'saved: dropped');
    expect(decode(store.file)['version'], 2);
    expect(decode(store.settingsFile)['version'], 2);
    expect(
      decode(store.file).keys,
      unorderedEquals(['version', 'songs', 'setlists']),
    );
    expect(decode(store.settingsFile).containsKey('songs'), isFalse);
    final again = await LibraryStore(store.file).load();
    expect(again.toJson(), first.toJson(), reason: 'lossless');
    return first;
  }

  void expectCommon(Library l) {
    expect(l.songs.map((s) => s.name), ['Dead Weight', 'Slow Blues']);
    expect(l.songs.map((s) => s.bpm), [128, 64]);
    expect(l.songs[1].pattern.timeSignature, '12/8');
    expect(l.songs[0].pattern.stepsPerBeat, 2);
    expect(l.setlists.single.name, 'Friday set');
    expect(l.setlists.single.songIds, ['s1', 's2']);
    expect(l.setlists.single.playedAt, isNotNull);
    expect(l.activeSetlistId, 'set1');
    expect(l.currentSongId, 's2');
    expect(l.currentPosition, 1);
    expect(l.lastBpm, 96);
    expect(l.lastPattern.timeSignature, '3/4');
    expect(l.visualOffset, const Duration(milliseconds: 20));
    expect(l.themeMode, ThemeMode.dark);
    expect(l.vibrate, isFalse);
    expect(l.songs[0].editedAt, isNotNull);
  }

  test('1.0.0 (build 2): Classic → Woodblock, no polyrhythm, played-at and '
      'polyrhythm volume filled in', () async {
    final l = await loadAndResave('library_v1_build2.json');
    expectCommon(l);
    expect(l.clickSound, ClickSound.woodblock);
    expect(l.volumes.accent, 0.9);
    expect(l.volumes.polyrhythm, 0.7, reason: 'default');
    expect(l.songs[0].pattern.polyrhythm, 0);
    expect(l.songs[0].playedAt, isNull);
    expect(l.tipsSeen, isEmpty);
    expect(l.songs[0].onStart, OnStart.off);
    expect(l.lastOnStart, OnStart.off);
  });

  test('1.1.0 (build 13): polyrhythm and played-at kept', () async {
    final l = await loadAndResave('library_v1_build13.json');
    expectCommon(l);
    expect(l.clickSound, ClickSound.cowbell);
    expect(l.volumes.polyrhythm, 0.6);
    expect(l.songs[0].pattern.polyrhythm, 3);
    expect(l.songs[0].pattern.polyStates, [
      StepLevel.accent,
      StepLevel.normal,
      StepLevel.silent,
    ]);
    expect(l.songs[0].playedAt, isNotNull);
  });

  test('1.2.0 / 1.3.0 (builds 20, 26): the hint flags join tipsSeen', () async {
    expect((await loadAndResave('library_v1_build20.json')).tipsSeen, {
      swipeHintTip,
    });
    dir.listSync().forEach((e) => e.deleteSync(recursive: true));
    expect((await loadAndResave('library_v1_build26.json')).tipsSeen, {
      swipeHintTip,
      setsHintTip,
    });
  });

  test('builds 37–38: count-ins become "When I press Start"', () async {
    final l = await loadAndResave('library_v1_build37.json');
    expectCommon(l);
    expect(l.tipsSeen, {'edit-first-load', swipeHintTip, setsHintTip});
    expect(l.songs[0].onStart, const OnStart(countInOn: true, countInBars: 2));
    expect(l.songs[1].onStart, OnStart.off);
    expect(l.lastOnStart, const OnStart(countInOn: true));
  });

  const migrated = OnStart(
    countInOn: true,
    countInBars: 2,
    speedUp: true,
    upTo: 160,
    stopOn: true,
    stopBy: StopBy.bars,
  );

  test('build 39: until / stopAfter / countIn become today\'s keys', () async {
    final l = await loadAndResave('library_v1_build39.json');
    expectCommon(l);
    expect(l.songs[0].onStart, migrated);
    expect(
      l.songs[1].onStart,
      const OnStart(speedUp: true),
      reason: 'off parts off, values kept',
    );
    expect(
      l.lastOnStart,
      const OnStart(countInOn: true, speedUp: true, stopOn: true),
    );
  });

  test('builds 40–47 and version 2 load the same library; v2 output is the '
      'golden pair exactly', () async {
    final v1 = await loadAndResave('library_v1_build47.json');
    expect(v1.songs[0].onStart, migrated);
    expect(
      store.file.readAsStringSync(),
      jsonEncode(decode(File('test/fixtures/v2/library.json'))),
    );
    expect(
      store.settingsFile.readAsStringSync(),
      jsonEncode(decode(File('test/fixtures/v2/settings.json'))),
    );
    final fresh = Directory('${dir.path}/v2')..createSync();
    File('test/fixtures/v2/library.json')
        .copySync('${fresh.path}/library.json');
    File('test/fixtures/v2/settings.json')
        .copySync('${fresh.path}/settings.json');
    final v2Store = LibraryStore(File('${fresh.path}/library.json'));
    final v2 = await v2Store.load();
    expect(v2.toJson(), v1.toJson());
    expect(
      v2Store.backupFile.existsSync(),
      isFalse,
      reason: 'no backup for v2',
    );
  });

  test('every step runs in order up to the latest; unknown versions throw', () {
    expect(migrate({'version': 1, 'songs': [], 'setlists': []})['version'], 2);
    expect(() => migrate({'version': 0}), throwsFormatException);
    expect(latestVersion, Library.version);
  });

  group('repair on load (never throws)', () {
    Map<String, Object?> pattern(int beats, int steps, int unit) => {
      'beatsPerBar': beats,
      'stepsPerBeat': steps,
      'beatUnit': unit,
      'steps': [for (var i = 0; i < beats * steps; i++) 'normal'],
      'polyrhythm': 0,
      'polyStates': [],
    };
    Map<String, Object?> song(String id, {int bpm = 100, Object? pattern}) => {
      'id': id,
      'name': id,
      'bpm': bpm,
      'pattern': pattern ?? const MetronomePattern.standard().toJson(),
      'onStart': OnStart.off.toJson(),
      'editedAt': null,
      'playedAt': null,
    };

    test('duplicates, dangling set entries, out-of-range values and a '
        'session pointing at nothing', () {
      final l = Library.fromJson({
        'version': 2,
        'songs': [
          song('a', bpm: 500),
          song('a', bpm: 90), // duplicate id: the first one stays
          song('b', bpm: 5, pattern: pattern(20, 6, 3)),
          song('c', pattern: {'beatsPerBar': 0}), // broken pattern
        ],
        'setlists': [
          {
            'id': 's',
            'name': 'S',
            'songIds': ['a', 'gone', 'b', 'a'],
            'playedAt': null,
          },
          {'id': 's', 'name': 'Dup', 'songIds': [], 'playedAt': null},
        ],
        'lastBpm': 1000,
        'visualOffsetMs': 9000,
        'volumes': {
          'accent': 1.7,
          'beat': -1,
          'subdivision': 0.5,
          'polyrhythm': 0.5,
        },
        'activeSetlistId': 'nope',
        'currentSongId': 'gone',
        'currentPosition': 7,
      });
      expect(l.songs.map((s) => s.id), ['a', 'b', 'c']);
      expect(l.songs[0].bpm, 300);
      expect(l.songs[1].bpm, 30);
      expect(l.songs[1].pattern.beatsPerBar, Library.maxBeats);
      expect(l.songs[1].pattern.stepsPerBeat, 4);
      expect(l.songs[1].pattern.beatUnit, 4);
      expect(
        l.songs[2].pattern,
        const MetronomePattern.standard(),
        reason: 'kept',
      );
      expect(l.setlists.single.name, 'S');
      expect(l.setlists.single.songIds, [
        'a',
        'b',
        'a',
      ], reason: 'repeats stay');
      expect(l.lastBpm, 300);
      expect(l.visualOffset, const Duration(milliseconds: 500));
      expect(l.volumes.accent, 1);
      expect(l.volumes.beat, 0);
      expect(l.activeSetlistId, isNull);
      expect(l.currentSongId, isNull);
      expect(l.currentPosition, -1);
    });

    test('a position that doesn\'t point at the current song is re-found', () {
      final l = Library.fromJson({
        'version': 2,
        'songs': [song('a'), song('b')],
        'setlists': [
          {
            'id': 's',
            'name': 'S',
            'songIds': ['a', 'b'],
            'playedAt': null,
          },
        ],
        'activeSetlistId': 's',
        'currentSongId': 'b',
        'currentPosition': 0,
      });
      expect(l.currentPosition, 1);
    });
  });
}
