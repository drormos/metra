import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'click_sound.dart';
import 'metronome_pattern.dart';

@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.bpm,
    required this.pattern,
    this.editedAt,
  });

  final String id;
  final String name;
  final int bpm;
  final MetronomePattern pattern;

  /// When the song was last created or saved; null for songs from before
  /// this was recorded (they sort as oldest in "Recently edited").
  final DateTime? editedAt;

  Song copyWith({
    String? name,
    int? bpm,
    MetronomePattern? pattern,
    DateTime? editedAt,
  }) => Song(
    id: id,
    name: name ?? this.name,
    bpm: bpm ?? this.bpm,
    pattern: pattern ?? this.pattern,
    editedAt: editedAt ?? this.editedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bpm': bpm,
    'pattern': pattern.toJson(),
    'editedAt': editedAt?.millisecondsSinceEpoch,
  };

  factory Song.fromJson(Map<String, Object?> json) => Song(
    id: json['id'] as String,
    name: json['name'] as String,
    bpm: json['bpm'] as int,
    pattern: MetronomePattern.fromJson(json['pattern'] as Map<String, Object?>),
    editedAt: switch (json['editedAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
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
    this.clickSound = ClickSound.classic,
    this.themeMode = ThemeMode.system,
    this.vibrate = true,
    this.activeSetlistId,
    this.currentSongId,
    this.currentPosition = -1,
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
  final ClickSound clickSound;

  /// System (follow the OS), dark or light.
  final ThemeMode themeMode;

  /// "Vibrate on touch": can only turn haptics off; the phone's own
  /// vibration setting still applies.
  final bool vibrate;

  /// The loaded setlist; null is Free play (the first-launch default).
  final String? activeSetlistId;

  /// The song last loaded, and its position in the active setlist (-1 if
  /// none or not in it), so the app reopens where it was left.
  final String? currentSongId;
  final int currentPosition;

  Library copyWith({
    List<Song>? songs,
    List<Setlist>? setlists,
    int? lastBpm,
    MetronomePattern? lastPattern,
    Duration? visualOffset,
    ClickSound? clickSound,
    ThemeMode? themeMode,
    bool? vibrate,
  }) => Library(
    songs: songs ?? this.songs,
    setlists: setlists ?? this.setlists,
    lastBpm: lastBpm ?? this.lastBpm,
    lastPattern: lastPattern ?? this.lastPattern,
    visualOffset: visualOffset ?? this.visualOffset,
    clickSound: clickSound ?? this.clickSound,
    themeMode: themeMode ?? this.themeMode,
    vibrate: vibrate ?? this.vibrate,
    activeSetlistId: activeSetlistId,
    currentSongId: currentSongId,
    currentPosition: currentPosition,
  );

  /// The mode and current song; nulls here are meaningful (Free play, no
  /// song), so they don't go through [copyWith].
  Library withSession({
    required String? setlistId,
    required String? songId,
    required int position,
  }) => Library(
    songs: songs,
    setlists: setlists,
    lastBpm: lastBpm,
    lastPattern: lastPattern,
    visualOffset: visualOffset,
    clickSound: clickSound,
    themeMode: themeMode,
    vibrate: vibrate,
    activeSetlistId: setlistId,
    currentSongId: songId,
    currentPosition: position,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'lastBpm': lastBpm,
    'lastPattern': lastPattern.toJson(),
    'visualOffsetMs': visualOffset.inMilliseconds,
    'clickSound': clickSound.name,
    'themeMode': themeMode.name,
    'vibrate': vibrate,
    'activeSetlistId': activeSetlistId,
    'currentSongId': currentSongId,
    'currentPosition': currentPosition,
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
      // Optional (older files lack it); an unknown name falls back rather
      // than discarding the whole library.
      clickSound:
          ClickSound.values.asNameMap()[json['clickSound']] ??
          ClickSound.classic,
      themeMode:
          ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
      vibrate: json['vibrate'] as bool? ?? true, // older files: on
      // Optional: older files open in Free play.
      activeSetlistId: json['activeSetlistId'] as String?,
      currentSongId: json['currentSongId'] as String?,
      currentPosition: json['currentPosition'] as int? ?? -1,
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
