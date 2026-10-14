import 'package:flutter/foundation.dart';

import 'metronome_pattern.dart';

@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.bpm,
    required this.pattern,
  });

  final String id;
  final String name;
  final int bpm;
  final MetronomePattern pattern;

  Song copyWith({String? name, int? bpm, MetronomePattern? pattern}) => Song(
    id: id,
    name: name ?? this.name,
    bpm: bpm ?? this.bpm,
    pattern: pattern ?? this.pattern,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bpm': bpm,
    'pattern': pattern.toJson(),
  };

  factory Song.fromJson(Map<String, Object?> json) => Song(
    id: json['id'] as String,
    name: json['name'] as String,
    bpm: json['bpm'] as int,
    pattern: MetronomePattern.fromJson(json['pattern'] as Map<String, Object?>),
  );
}

/// An ordered list of songs, by id.
@immutable
class Setlist {
  const Setlist({required this.id, required this.name, required this.songIds});

  final String id;
  final String name;
  final List<String> songIds;

  Setlist copyWith({String? name, List<String>? songIds}) => Setlist(
    id: id,
    name: name ?? this.name,
    songIds: songIds ?? this.songIds,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'songIds': songIds};

  factory Setlist.fromJson(Map<String, Object?> json) => Setlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: [for (final id in json['songIds'] as List) id as String],
  );
}

/// Everything the app saves: songs, setlists, and the last session's
/// settings so the app reopens where it was left.
@immutable
class Library {
  const Library({
    required this.songs,
    required this.setlists,
    required this.lastBpm,
    required this.lastPattern,
    required this.visualOffset,
  });

  static const empty = Library(
    songs: [],
    setlists: [],
    lastBpm: 120,
    lastPattern: MetronomePattern.standard(),
    visualOffset: Duration.zero,
  );

  /// Bump when the format changes incompatibly.
  static const version = 1;

  final List<Song> songs;
  final List<Setlist> setlists;
  final int lastBpm;
  final MetronomePattern lastPattern;
  final Duration visualOffset;

  Library copyWith({
    List<Song>? songs,
    List<Setlist>? setlists,
    int? lastBpm,
    MetronomePattern? lastPattern,
    Duration? visualOffset,
  }) => Library(
    songs: songs ?? this.songs,
    setlists: setlists ?? this.setlists,
    lastBpm: lastBpm ?? this.lastBpm,
    lastPattern: lastPattern ?? this.lastPattern,
    visualOffset: visualOffset ?? this.visualOffset,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'lastBpm': lastBpm,
    'lastPattern': lastPattern.toJson(),
    'visualOffsetMs': visualOffset.inMilliseconds,
    'songs': [for (final song in songs) song.toJson()],
    'setlists': [for (final setlist in setlists) setlist.toJson()],
  };

  /// Throws on malformed data, and on files from a newer app version.
  factory Library.fromJson(Map<String, Object?> json) {
    final fileVersion = json['version'] as int;
    if (fileVersion > version) {
      throw FormatException(
        'Library version $fileVersion is newer than $version',
      );
    }
    return Library(
      lastBpm: json['lastBpm'] as int,
      lastPattern: MetronomePattern.fromJson(
        json['lastPattern'] as Map<String, Object?>,
      ),
      visualOffset: Duration(milliseconds: json['visualOffsetMs'] as int),
      songs: [
        for (final song in json['songs'] as List)
          Song.fromJson(song as Map<String, Object?>),
      ],
      setlists: [
        for (final setlist in json['setlists'] as List)
          Setlist.fromJson(setlist as Map<String, Object?>),
      ],
    );
  }
}
