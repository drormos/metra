import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'click_sound.dart';
import 'click_volumes.dart';
import 'metronome_pattern.dart';

@immutable
class Song {
  const Song({
    required this.id,
    required this.name,
    required this.bpm,
    required this.pattern,
    this.countIn = 0,
    this.editedAt,
    this.playedAt,
  });

  final String id;
  final String name;
  final int bpm;
  final MetronomePattern pattern;

  /// Bars of count-in before the song (0 = off), like its tempo
  /// (ui-spec.md "When I press Start").
  final int countIn;

  /// When the song was last loaded into the click (any mode), for the
  /// Songs tab's "most recently played"; null if never or an older file.
  final DateTime? playedAt;

  /// When the song was last created or saved; null for songs from before
  /// this was recorded (they sort as oldest in "Recently edited").
  final DateTime? editedAt;

  Song copyWith({
    String? name,
    int? bpm,
    MetronomePattern? pattern,
    int? countIn,
    DateTime? editedAt,
    DateTime? playedAt,
  }) => Song(
    id: id,
    name: name ?? this.name,
    bpm: bpm ?? this.bpm,
    pattern: pattern ?? this.pattern,
    countIn: countIn ?? this.countIn,
    editedAt: editedAt ?? this.editedAt,
    playedAt: playedAt ?? this.playedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'bpm': bpm,
    'pattern': pattern.toJson(),
    'countIn': countIn,
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'playedAt': playedAt?.millisecondsSinceEpoch,
  };

  factory Song.fromJson(Map<String, Object?> json) => Song(
    id: json['id'] as String,
    name: json['name'] as String,
    bpm: json['bpm'] as int,
    pattern: MetronomePattern.fromJson(json['pattern'] as Map<String, Object?>),
    countIn: json['countIn'] as int? ?? 0, // older files: off
    editedAt: switch (json['editedAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
    playedAt: switch (json['playedAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null, // never played, or an older file
    },
  );
}

/// An ordered list of songs, by id.
@immutable
class Setlist {
  const Setlist({
    required this.id,
    required this.name,
    required this.songIds,
    this.playedAt,
  });

  final String id;
  final String name;
  final List<String> songIds;

  /// When the set was last loaded, for "Recently played"; null if never.
  final DateTime? playedAt;

  Setlist copyWith({String? name, List<String>? songIds, DateTime? playedAt}) =>
      Setlist(
        id: id,
        name: name ?? this.name,
        songIds: songIds ?? this.songIds,
        playedAt: playedAt ?? this.playedAt,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'songIds': songIds,
    'playedAt': playedAt?.millisecondsSinceEpoch,
  };

  factory Setlist.fromJson(Map<String, Object?> json) => Setlist(
    id: json['id'] as String,
    name: json['name'] as String,
    songIds: [for (final id in json['songIds'] as List) id as String],
    playedAt: switch (json['playedAt']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null, // never played, or an older file
    },
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
    this.lastCountIn = 0,
    this.clickSound = ClickSound.woodblock,
    this.themeMode = ThemeMode.system,
    this.vibrate = true,
    this.volumes = ClickVolumes.defaults,
    this.activeSetlistId,
    this.currentSongId,
    this.currentPosition = -1,
    this.swipeHintSeen = false,
    this.songsHintSeen = false,
    this.setsHintSeen = false,
    this.tipsSeen = const {},
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

  /// The click's count-in (Free play's own after a fresh launch).
  final int lastCountIn;
  final Duration visualOffset;
  final ClickSound clickSound;

  /// System (follow the OS), dark or light.
  final ThemeMode themeMode;

  /// "Vibrate on touch": can only turn haptics off; the phone's own
  /// vibration setting still applies.
  final bool vibrate;

  final ClickVolumes volumes;

  /// The loaded setlist; null is Free play (the first-launch default).
  final String? activeSetlistId;

  /// The song last loaded, and its position in the active setlist (-1 if
  /// none or not in it), so the app reopens where it was left.
  final String? currentSongId;
  final int currentPosition;

  /// The set panel's one-time swipe hint has been shown (never again).
  final bool swipeHintSeen;

  /// The same, for the Songs list (its own flag).
  final bool songsHintSeen;

  /// The same, for the sets view.
  final bool setsHintSeen;

  /// One-time tips already shown, by name (e.g. the main screen's
  /// "edit right here" lines).
  final Set<String> tipsSeen;

  Library copyWith({
    List<Song>? songs,
    List<Setlist>? setlists,
    int? lastBpm,
    MetronomePattern? lastPattern,
    int? lastCountIn,
    Duration? visualOffset,
    ClickSound? clickSound,
    ThemeMode? themeMode,
    bool? vibrate,
    ClickVolumes? volumes,
    bool? swipeHintSeen,
    bool? songsHintSeen,
    bool? setsHintSeen,
    Set<String>? tipsSeen,
  }) => Library(
    songs: songs ?? this.songs,
    setlists: setlists ?? this.setlists,
    lastBpm: lastBpm ?? this.lastBpm,
    lastPattern: lastPattern ?? this.lastPattern,
    lastCountIn: lastCountIn ?? this.lastCountIn,
    visualOffset: visualOffset ?? this.visualOffset,
    clickSound: clickSound ?? this.clickSound,
    themeMode: themeMode ?? this.themeMode,
    vibrate: vibrate ?? this.vibrate,
    volumes: volumes ?? this.volumes,
    activeSetlistId: activeSetlistId,
    currentSongId: currentSongId,
    currentPosition: currentPosition,
    swipeHintSeen: swipeHintSeen ?? this.swipeHintSeen,
    songsHintSeen: songsHintSeen ?? this.songsHintSeen,
    setsHintSeen: setsHintSeen ?? this.setsHintSeen,
    tipsSeen: tipsSeen ?? this.tipsSeen,
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
    lastCountIn: lastCountIn,
    visualOffset: visualOffset,
    clickSound: clickSound,
    themeMode: themeMode,
    vibrate: vibrate,
    volumes: volumes,
    activeSetlistId: setlistId,
    currentSongId: songId,
    currentPosition: position,
    swipeHintSeen: swipeHintSeen,
    songsHintSeen: songsHintSeen,
    setsHintSeen: setsHintSeen,
    tipsSeen: tipsSeen,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'lastBpm': lastBpm,
    'lastPattern': lastPattern.toJson(),
    'lastCountIn': lastCountIn,
    'visualOffsetMs': visualOffset.inMilliseconds,
    'clickSound': clickSound.name,
    'themeMode': themeMode.name,
    'vibrate': vibrate,
    'volumes': volumes.toJson(),
    'activeSetlistId': activeSetlistId,
    'currentSongId': currentSongId,
    'currentPosition': currentPosition,
    'swipeHintSeen': swipeHintSeen,
    'songsHintSeen': songsHintSeen,
    'setsHintSeen': setsHintSeen,
    'tipsSeen': tipsSeen.toList(),
    'songs': [for (final song in songs) song.toJson()],
    'setlists': [for (final setlist in setlists) setlist.toJson()],
  };

  /// Throws on a malformed file, and on files from a newer app version. A
  /// bad song, setlist or setting is skipped or falls back, so one broken
  /// entry doesn't hide the rest of the library.
  factory Library.fromJson(Map<String, Object?> json) {
    final fileVersion = json['version'] as int;
    if (fileVersion > version) throw NewerLibraryException(fileVersion);
    final songs = json['songs'] as List;
    final setlists = json['setlists'] as List;
    return Library(
      lastBpm: _orNull(() => json['lastBpm'] as int) ?? empty.lastBpm,
      lastPattern:
          _orNull(
            () => MetronomePattern.fromJson(
              json['lastPattern'] as Map<String, Object?>,
            ),
          ) ??
          empty.lastPattern,
      lastCountIn: json['lastCountIn'] as int? ?? 0,
      visualOffset: Duration(milliseconds: json['visualOffsetMs'] as int? ?? 0),
      // Optional (older files lack it); an unknown name falls back rather
      // than discarding the whole library.
      clickSound:
          ClickSound.values.asNameMap()[json['clickSound']] ??
          ClickSound.woodblock,
      themeMode:
          ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
      vibrate: json['vibrate'] as bool? ?? true, // older files: on
      volumes: switch (json['volumes']) {
        final Map<String, Object?> v => ClickVolumes.fromJson(v),
        _ => ClickVolumes.defaults, // older files
      },
      // Optional: older files open in Free play.
      activeSetlistId: json['activeSetlistId'] as String?,
      currentSongId: json['currentSongId'] as String?,
      currentPosition: json['currentPosition'] as int? ?? -1,
      swipeHintSeen: json['swipeHintSeen'] as bool? ?? false,
      songsHintSeen: json['songsHintSeen'] as bool? ?? false,
      setsHintSeen: json['setsHintSeen'] as bool? ?? false,
      tipsSeen: {...?(json['tipsSeen'] as List?)?.cast<String>()},
      songs: [
        for (final song in songs)
          ?_orNull(() => Song.fromJson(song as Map<String, Object?>)),
      ],
      setlists: [
        for (final setlist in setlists)
          ?_orNull(() => Setlist.fromJson(setlist as Map<String, Object?>)),
      ],
    );
  }

  static T? _orNull<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}

/// The file was saved by a newer app version (after a downgrade). It is
/// left as it is, so updating the app again opens it.
class NewerLibraryException implements Exception {
  const NewerLibraryException(this.fileVersion);

  final int fileVersion;

  @override
  String toString() =>
      'Library version $fileVersion is newer than ${Library.version}';
}
