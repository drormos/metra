import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';

void main() {
  late Directory dir;
  late File file;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_store_test');
    file = File('${dir.path}/library.json');
    store = LibraryStore(file);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('missing file loads an empty library', () async {
    final library = await store.load();
    expect(library.songs, isEmpty);
    expect(library.lastBpm, Library.empty.lastBpm);
  });

  test('save then load', () async {
    await store.save(Library.empty.copyWith(lastBpm: 88));
    expect((await LibraryStore(file).load()).lastBpm, 88);
  });

  test('concurrent saves land in order; last one wins', () async {
    await Future.wait([
      for (var bpm = 60; bpm <= 70; bpm++)
        store.save(Library.empty.copyWith(lastBpm: bpm)),
    ]);
    expect((await store.load()).lastBpm, 70);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });

  test('a corrupt file is kept aside, not overwritten', () async {
    file.writeAsStringSync('{not json');
    final library = await store.load();
    expect(library.songs, isEmpty);
    final backups = store.corruptDir.listSync().whereType<File>().toList();
    expect(backups, hasLength(1));
    expect(backups.single.readAsStringSync(), '{not json');
  });

  test('a failed save does not block later saves', () async {
    final sub = Directory('${dir.path}/sub');
    final subStore = LibraryStore(File('${sub.path}/library.json'));
    // Directory missing: this write fails.
    await expectLater(subStore.save(Library.empty), throwsA(anything));
    sub.createSync();
    await subStore.save(Library.empty.copyWith(lastBpm: 77));
    expect((await subStore.load()).lastBpm, 77);
  });

  test('a newer file is left untouched and the load fails', () async {
    final newer = jsonEncode(Library.empty.toJson()..['version'] = 99);
    file.writeAsStringSync(newer);
    await expectLater(store.load(), throwsA(isA<NewerLibraryException>()));
    expect(file.readAsStringSync(), newer);
    expect(dir.listSync(), hasLength(1));
  });

  Library withSong() => Library.empty.copyWith(
    lastBpm: 91,
    songs: [
      const Song(
        id: 'a',
        name: 'A',
        bpm: 100,
        pattern: MetronomePattern.standard(),
      ),
    ],
  );

  test(
    'songs and setlists in library.json, the rest in settings.json',
    () async {
      await store.save(withSong());
      final lib = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final settings = jsonDecode(
        store.settingsFile.readAsStringSync(),
      ) as Map<String, Object?>;
      expect(lib.keys, unorderedEquals(['version', 'songs', 'setlists']));
      expect(settings['lastBpm'], 91);
      expect(settings.containsKey('songs'), isFalse);
      expect(await store.exists(), isTrue);
    },
  );

  test(
    'broken settings keep the songs; a broken library keeps the settings',
    () async {
      await store.save(withSong());
      store.settingsFile.writeAsStringSync('{oops');
      var loaded = await LibraryStore(file).load();
      expect(loaded.songs.single.name, 'A');
      expect(loaded.lastBpm, Library.empty.lastBpm);
      await LibraryStore(file).save(withSong());
      file.writeAsStringSync('[1, 2]');
      loaded = await LibraryStore(file).load();
      expect(loaded.songs, isEmpty);
      expect(loaded.lastBpm, 91);
      expect(store.corruptDir.listSync(), hasLength(2), reason: 'both kept');
    },
  );

  test('keeps only the 3 newest corrupt files; old ones beside the library '
      'move into the folder', () async {
    File('${dir.path}/library.json.corrupt-1').writeAsStringSync('old');
    for (var i = 0; i < 4; i++) {
      file.writeAsStringSync('{broken $i');
      await LibraryStore(file).load();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final kept = store.corruptDir.listSync().whereType<File>().toList();
    expect(kept, hasLength(LibraryStore.keepCorrupt));
    expect(
      kept.map((f) => f.readAsStringSync()),
      containsAll(['{broken 3', '{broken 2', '{broken 1']),
    );
    expect(
      dir.listSync().whereType<File>().where(
        (f) => f.path.contains('.corrupt-'),
      ),
      isEmpty,
    );
  });

  test('a version 1 file keeps its backup until a save succeeds', () async {
    final v1 = (withSong().toJson()..['version'] = 1)
      ..remove('tipsSeen')
      ..remove('lastOnStart');
    file.writeAsStringSync(jsonEncode(v1));
    final loaded = await store.load();
    expect(loaded.songs.single.name, 'A');
    expect(store.backupFile.existsSync(), isTrue);
    // A failing save (the settings path is a folder) keeps the backup.
    Directory(store.settingsFile.path).createSync();
    await expectLater(store.save(loaded), throwsA(anything));
    expect(store.backupFile.existsSync(), isTrue);
    Directory(store.settingsFile.path).deleteSync();
    await store.save(loaded);
    expect(store.backupFile.existsSync(), isFalse);
  });

  test('an unchanged file is not rewritten (a tempo change only touches '
      'settings)', () async {
    await store.save(withSong());
    file.writeAsStringSync('marker');
    await store.save(withSong().copyWith(lastBpm: 140));
    expect(file.readAsStringSync(), 'marker');
    expect(
      (jsonDecode(store.settingsFile.readAsStringSync()) as Map)['lastBpm'],
      140,
    );
  });

  test('a newer settings file is refused, touching nothing', () async {
    await store.save(withSong());
    final newer = jsonEncode(withSong().settingsJson()..['version'] = 99);
    store.settingsFile.writeAsStringSync(newer);
    await expectLater(
      LibraryStore(file).load(),
      throwsA(isA<NewerLibraryException>()),
    );
    expect(store.settingsFile.readAsStringSync(), newer);
  });

  test(
    'settings with values of the wrong kind: the songs stay, the settings '
    'file is kept aside; a lone broken settings file never stops loading',
    () async {
      await store.save(withSong());
      store.settingsFile.writeAsStringSync('{"version": "two", "tipsSeen": 3}');
      var loaded = await LibraryStore(file).load();
      expect(loaded.songs.single.name, 'A');
      file.deleteSync();
      store.settingsFile.writeAsStringSync('{"version": [], "lastBpm": "x"}');
      loaded = await LibraryStore(file).load();
      expect(loaded.songs, isEmpty);
    },
  );
}
