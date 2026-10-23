import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/storage/library_store.dart';

/// Damaged saved files (keys removed, values of the wrong type or out of
/// range, truncated text) never stop the app: loading either repairs them
/// or sets the file aside and starts from what's left. Only a file from a
/// newer version is refused, untouched.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('metra_load_fuzz'));
  tearDown(() => dir.deleteSync(recursive: true));

  final fixtures = [
    for (final f in Directory('test/fixtures').listSync(recursive: true))
      if (f is File && f.path.endsWith('.json')) f,
  ];

  Object? junk(Random r) => switch (r.nextInt(8)) {
    0 => null,
    1 => r.nextInt(100000) - 50000,
    2 => 'x' * r.nextInt(5),
    3 => r.nextBool(),
    4 => <Object?>[],
    5 => <String, Object?>{},
    6 => r.nextDouble() * 1e6,
    _ => [1, 'a', null],
  };

  /// Changes one random place in [json]: drops a key, swaps a value for
  /// junk, or empties a list.
  void mutate(Object? json, Random r) {
    if (json is Map<String, Object?> && json.isNotEmpty) {
      final key = json.keys.elementAt(r.nextInt(json.length));
      switch (r.nextInt(3)) {
        case 0:
          json.remove(key);
        case 1:
          json[key] = junk(r);
        case _:
          mutate(json[key], r);
      }
    } else if (json is List && json.isNotEmpty) {
      final i = r.nextInt(json.length);
      if (r.nextBool()) {
        json[i] = junk(r);
      } else {
        mutate(json[i], r);
      }
    }
  }

  // More: `--dart-define=LOAD_FUZZ=4000`.
  const files = int.fromEnvironment('LOAD_FUZZ', defaultValue: 400);
  for (var seed = 0; seed < files; seed++) {
    test('damaged file $seed loads', () async {
      final r = Random(seed);
      final source = fixtures[r.nextInt(fixtures.length)];
      final json = jsonDecode(source.readAsStringSync());
      for (var i = 1 + r.nextInt(6); i > 0; i--) {
        mutate(json, r);
      }
      var text = jsonEncode(json);
      if (r.nextInt(10) == 0) text = text.substring(0, r.nextInt(text.length));
      // A settings file lands beside a version 2 library (settings.json),
      // everything else as library.json.
      final name = source.path.endsWith('settings.json')
          ? 'settings.json'
          : 'library.json';
      File('${dir.path}/$name').writeAsStringSync(text);
      final store = LibraryStore(File('${dir.path}/library.json'));

      Library? loaded;
      try {
        loaded = await store.load();
      } on NewerLibraryException {
        return; // a version number mutated upward: refused, untouched
      }
      // Whatever loaded is consistent and saves.
      final ids = loaded.songs.map((s) => s.id).toSet();
      expect(ids.length, loaded.songs.length, reason: 'unique song ids');
      for (final set in loaded.setlists) {
        expect(ids.containsAll(set.songIds), isTrue, reason: 'no dangling');
      }
      for (final song in loaded.songs) {
        expect(song.bpm, inInclusiveRange(30, 300));
      }
      await store.save(loaded);
      final again = await LibraryStore(store.file).load();
      expect(again.toJson(), loaded.toJson());
    });
  }
}
