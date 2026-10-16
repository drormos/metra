import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
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
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.corrupt-'))
        .toList();
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
}
