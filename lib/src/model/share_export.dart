import 'dart:convert';
import 'dart:io' show gzip;

import 'library.dart';
import 'on_start.dart';
import 'share_text.dart';

/// Metra exports (ui-spec.md "Sharing sets and songs"): a readable part,
/// the help line, then one "metra1:" line holding the songs' music
/// (gzip-compressed JSON, base64url). When I press Start is never in it.
///
/// Payload versions (the "v" field; the line prefix stays "metra1:"):
/// - 1 (build 101 on): `{"v": 1, "songs": [song], "set"?: {"name",
///   "order": [song index]}}`, a song being `{"name", "end", "parts":
///   [SongPart.toJson() without "id"]}`. Golden: test/fixtures/export_v1.
/// Newer payloads are read as far as they're understood: unknown fields
/// are ignored and a song that can't be read is skipped and counted.
const exportVersion = 1;

/// The line between the readable part and the data.
const importHelp =
    'To import this into Metra: share this message to Metra, or copy it '
    'and tap Import in Metra.';

/// A set as an export: its song list, the help line, the data.
String exportSetText(Setlist setlist, List<Song> songs) {
  final unique = <String, int>{};
  for (final song in songs) {
    unique.putIfAbsent(song.id, () => unique.length);
  }
  final byId = {for (final s in songs) s.id: s};
  // The song list without its "Shared from Metra" ending.
  final list = setlistShareText(setlist, songs).split('\n');
  return [
    ...list.takeWhile((l) => l.isNotEmpty),
    '',
    importHelp,
    _dataLine({
      'v': exportVersion,
      'set': {
        'name': setlist.name,
        'order': [for (final s in songs) unique[s.id]],
      },
      'songs': [for (final id in unique.keys) _songJson(byId[id]!)],
    }),
  ].join('\n');
}

/// One song as an export: its line, the help line, the data.
String exportSongText(Song song) => [
  songShareLine(song),
  '',
  importHelp,
  _dataLine({
    'v': exportVersion,
    'songs': [_songJson(song)],
  }),
].join('\n');

/// What a song's export holds besides its name: its parts and "At the
/// end", the music that decides whether two songs are the same.
Map<String, Object?> _music(Song song) => {
  'end': song.end.name,
  'parts': [
    for (final part in song.parts)
      {
        for (final MapEntry(:key, :value) in part.toJson().entries)
          if (key != 'id') key: value,
      },
  ],
};

Map<String, Object?> _songJson(Song song) => {
  'name': song.name,
  ..._music(song),
};

/// Equal for two songs with the same music (parts and "At the end"),
/// whatever their names, ids and When I press Start.
String musicKey(Song song) => jsonEncode(_music(song));

String _dataLine(Map<String, Object?> payload) =>
    'metra1:${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(payload)))).replaceAll('=', '')}';

/// A Metra export, read: the set's name and order (null for songs alone),
/// the songs (music only, When I press Start off) and how many couldn't
/// be read.
class SharedImport {
  const SharedImport({
    this.setName,
    this.order = const [],
    required this.songs,
    this.skipped = 0,
  });

  final String? setName;

  /// Indexes into [songs], in the set's order (a song may come twice).
  final List<int> order;
  final List<Song> songs;

  /// Songs that need a newer Metra.
  final int skipped;

  bool get isSet => setName != null;
}

final _data = RegExp(r'metra(\d+):([A-Za-z0-9_-]+)');

/// The export in [text] (the whole message, or any text holding its data
/// line), or null when there's nothing Metra-shaped to add.
SharedImport? parseShared(String text) {
  final match = _data.firstMatch(text);
  if (match == null) return null;
  final Object? payload;
  try {
    var data = match.group(2)!;
    data = data.padRight((data.length + 3) ~/ 4 * 4, '=');
    payload = jsonDecode(utf8.decode(gzip.decode(base64Url.decode(data))));
  } catch (_) {
    return null;
  }
  if (payload is! Map || payload['songs'] is! List) return null;
  final raw = payload['songs'] as List;
  final songs = <Song>[];
  // Raw index → index in [songs] (null: skipped).
  final kept = <int?>[];
  var skipped = 0;
  for (final (i, json) in raw.indexed) {
    final song = _readSong(json, i);
    kept.add(song == null ? null : songs.length);
    if (song == null) {
      skipped++;
    } else {
      songs.add(song);
    }
  }
  final set = payload['set'];
  String? setName;
  var order = <int>[for (var i = 0; i < songs.length; i++) i];
  if (set is Map && set['name'] is String) {
    setName = (set['name'] as String).trim();
    if (setName.isEmpty) setName = 'Shared set';
    if (set['order'] is List) {
      order = [
        for (final i in set['order'] as List)
          if (i is int && i >= 0 && i < kept.length && kept[i] != null)
            kept[i]!,
      ];
    }
  }
  if (songs.isEmpty && skipped == 0) return null;
  return SharedImport(
    setName: setName,
    order: order,
    songs: songs,
    skipped: skipped,
  );
}

/// A song from its export, its values put in range, or null when it
/// can't be read (a newer shape, or damaged).
Song? _readSong(Object? json, int index) {
  try {
    json as Map;
    final name = (json['name'] as String).trim();
    final parts = [
      for (final (i, part) in (json['parts'] as List).indexed)
        SongPart.fromJson({
          ...(part as Map).cast<String, Object?>(),
          'id': 'part-${i + 1}',
        }),
    ];
    if (name.isEmpty || parts.isEmpty) return null;
    return Song.withParts(
      id: 'shared-$index',
      name: name,
      parts: Library.fixParts(parts),
      end: SongEnd.values.asNameMap()[json['end']] ?? SongEnd.loopLastPart,
      onStart: OnStart.off,
    );
  } catch (_) {
    return null;
  }
}

/// What adding [shared] to [library] does (the check dialog says it,
/// then it's applied): each shared song becomes an existing song with
/// the same name (or an earlier "(shared)" copy) and the same music, or
/// a new one, renamed "Name (shared)", "(shared 2)"… when the name is
/// taken; never an overwrite.
class ImportPlan {
  ImportPlan._({
    required this.shared,
    required this.ids,
    required this.newSongs,
    required this.existing,
    required this.renamed,
    this.newSet,
    this.sameSet,
  });

  final SharedImport shared;

  /// The library song id each shared song becomes, by index.
  final List<String> ids;

  /// Songs to add (When I press Start off).
  final List<Song> newSongs;

  /// How many of the shared songs you already have.
  final int existing;

  /// New songs whose name was taken: (shared name, the name they get).
  final List<(String, String)> renamed;

  /// The set to add, or null (songs alone, or [sameSet]).
  final Setlist? newSet;

  /// An identical set you already have: it opens instead.
  final Setlist? sameSet;

  /// How many shared songs have more than one part (or a Gradual one).
  int get withParts =>
      shared.songs.where((s) => partsPlay(s.parts, s.end)).length;

  static ImportPlan of(
    Library library,
    SharedImport shared,
    String Function() newId,
  ) {
    final pool = [...library.songs];
    final libraryIds = {for (final s in library.songs) s.id};
    final ids = <String>[];
    final newSongs = <Song>[];
    final renamed = <(String, String)>[];
    final reused = <String>{};
    for (final song in shared.songs) {
      final key = musicKey(song);
      final same = pool
          .where((s) => _sameName(s.name, song.name) && musicKey(s) == key)
          .firstOrNull;
      if (same != null) {
        ids.add(same.id);
        if (libraryIds.contains(same.id)) reused.add(same.id);
        continue;
      }
      final name = _freeName(song.name, {for (final s in pool) s.name});
      final added = Song.withParts(
        id: newId(),
        name: name,
        parts: song.parts,
        end: song.end,
        editedAt: DateTime.now(),
      );
      pool.add(added);
      newSongs.add(added);
      ids.add(added.id);
      if (name != song.name) renamed.add((song.name, name));
    }
    Setlist? newSet, sameSet;
    if (shared.setName case final name?) {
      final songIds = [for (final i in shared.order) ids[i]];
      sameSet = library.setlists
          .where(
            (s) => _sameName(s.name, name) && _listEquals(s.songIds, songIds),
          )
          .firstOrNull;
      if (sameSet == null) {
        newSet = Setlist(
          id: newId(),
          name: _freeName(name, {for (final s in library.setlists) s.name}),
          songIds: songIds,
        );
      }
    }
    return ImportPlan._(
      shared: shared,
      ids: ids,
      newSongs: newSongs,
      existing: reused.length,
      renamed: renamed,
      newSet: newSet,
      sameSet: sameSet,
    );
  }

  /// [name], or the first of "name (shared)", "name (shared 2)"… that
  /// isn't in [taken].
  static String _freeName(String name, Set<String> taken) {
    if (!taken.contains(name)) return name;
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? '$name (shared)' : '$name (shared $n)';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// [have] is [shared], or an earlier "(shared)" copy of it.
  static bool _sameName(String have, String shared) =>
      have == shared ||
      RegExp('^${RegExp.escape(shared)} \\(shared( \\d+)?\\)\$').hasMatch(have);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
