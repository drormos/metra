import 'package:flutter/material.dart' show ThemeMode, immutable;

import 'click_sound.dart';
import 'click_volumes.dart';
import 'library_migrations.dart';
import 'metronome_pattern.dart';
import 'on_start.dart';
import 'song_part.dart';

export 'song_part.dart';

/// A song: its parts, played in order (ui-spec.md "Song parts"), what
/// happens at its end, and its "When I press Start". Most songs have one
/// part, and then [bpm] and [pattern] are simply that part's.
@immutable
class Song {
  /// A one-part song: one bar of [bpm] and [pattern], looping until Stop
  /// (how every song played before parts).
  const Song({
    required this.id,
    required this.name,
    required this._bpm,
    required MetronomePattern this._pattern,
    this.onStart = OnStart.off,
    this.editedAt,
    this.playedAt,
  }) : _parts = null,
       end = SongEnd.loopLastPart;

  /// A song of [parts] (at least one).
  const Song.withParts({
    required this.id,
    required this.name,
    required List<SongPart> this._parts,
    this.end = SongEnd.loopLastPart,
    this.onStart = OnStart.off,
    this.editedAt,
    this.playedAt,
  }) : _bpm = 0,
       _pattern = null;

  final String id;
  final String name;

  // A one-part song keeps its tempo and pattern here (so it can be
  // const), otherwise its parts.
  final int _bpm;
  final MetronomePattern? _pattern;
  final List<SongPart>? _parts;

  /// The parts in order; one bar for a one-part song.
  List<SongPart> get parts =>
      _parts ??
      [
        SongPart.steady(
          id: SongPart.firstId,
          name: SongPart.firstName,
          bars: 1,
          bpm: _bpm,
          pattern: _pattern!,
        ),
      ];

  /// "When the song ends": stop, loop the song, or loop its last part.
  final SongEnd end;

  /// The first part's tempo and pattern: a one-part song's own.
  int get bpm => _parts?.first.tempoStart ?? _bpm;
  MetronomePattern get pattern => _parts?.first.pattern ?? _pattern!;

  /// Count-in, speed up, stop after: part of the song like its tempo
  /// (ui-spec.md "When I press Start").
  final OnStart onStart;

  /// When the song was last loaded into the click (any mode), for the
  /// Songs tab's "most recently played"; null if never or an older file.
  final DateTime? playedAt;

  /// When the song was last created or saved; null for songs from before
  /// this was recorded (they sort as oldest in "Recently edited").
  final DateTime? editedAt;

  /// [bpm] and [pattern] change the first part (a Gradual one keeps its
  /// change: both ends shift); [parts] replaces them all.
  Song copyWith({
    String? name,
    int? bpm,
    MetronomePattern? pattern,
    List<SongPart>? parts,
    SongEnd? end,
    OnStart? onStart,
    DateTime? editedAt,
    DateTime? playedAt,
  }) {
    var list = parts ?? this.parts;
    if (bpm != null || pattern != null) {
      final first = list.first;
      final shift = bpm == null ? 0 : bpm - first.tempoStart;
      list = [
        first.copyWith(
          tempoStart: first.tempoStart + shift,
          tempoEnd: first.tempoEnd + shift,
          pattern: pattern,
        ),
        ...list.skip(1),
      ];
    }
    return Song.withParts(
      id: id,
      name: name ?? this.name,
      parts: list,
      end: end ?? this.end,
      onStart: onStart ?? this.onStart,
      editedAt: editedAt ?? this.editedAt,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parts': [for (final part in parts) part.toJson()],
    'endBehavior': end.name,
    'onStart': onStart.toJson(),
    'editedAt': editedAt?.millisecondsSinceEpoch,
    'playedAt': playedAt?.millisecondsSinceEpoch,
  };

  /// A broken part doesn't cost the song (its name and other parts); a
  /// song with no part left is skipped by the caller.
  factory Song.fromJson(Map<String, Object?> json) {
    final parts = [
      for (final part in json['parts'] as List)
        ?Library._orNull(() => SongPart.fromJson(part as Map<String, Object?>)),
    ];
    if (parts.isEmpty) throw const FormatException('A song with no parts');
    return Song.withParts(
      id: json['id'] as String,
      name: json['name'] as String,
      parts: parts,
      end:
          SongEnd.values.asNameMap()[json['endBehavior']] ??
          SongEnd.loopLastPart,
      onStart: OnStart.fromJson(json['onStart'] as Map<String, Object?>),
      editedAt: switch (json['editedAt']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      },
      playedAt: switch (json['playedAt']) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null, // never played
      },
    );
  }
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
    this.lastOnStart = OnStart.off,
    this.clickSound = ClickSound.woodblock,
    this.themeMode = ThemeMode.system,
    this.vibrate = true,
    this.partChangeSound = false,
    this.keepScreenOn = KeepScreenOn.whileOpen,
    this.volumes = ClickVolumes.defaults,
    this.activeSetlistId,
    this.currentSongId,
    this.currentPosition = -1,
    this.tipsSeen = const {},
    this.stageMode = false,
  });

  static const empty = Library(
    songs: [],
    setlists: [],
    lastBpm: 120,
    lastPattern: MetronomePattern.standard(),
    visualOffset: Duration.zero,
  );

  /// The saved format's version (see library_migrations.dart; older files
  /// are migrated on load, saving always writes this one).
  static const version = latestVersion;

  final List<Song> songs;
  final List<Setlist> setlists;
  final int lastBpm;
  final MetronomePattern lastPattern;

  /// The click's count-in, speed up, stop after (Free play's own after a
  /// fresh launch).
  final OnStart lastOnStart;
  final Duration visualOffset;
  final ClickSound clickSound;

  /// System (follow the OS), dark or light.
  final ThemeMode themeMode;

  /// "Vibrate on touch": can only turn haptics off; the phone's own
  /// vibration setting still applies.
  final bool vibrate;

  /// "Sound on part changes": the first beat of each new part a higher
  /// click.
  final bool partChangeSound;

  /// "Keep screen on": while Metra is open, or only while playing.
  final KeepScreenOn keepScreenOn;

  final ClickVolumes volumes;

  /// The loaded setlist; null is Free play (the first-launch default).
  final String? activeSetlistId;

  /// The song last loaded, and its position in the active setlist (-1 if
  /// none or not in it), so the app reopens where it was left.
  final String? currentSongId;
  final int currentPosition;

  /// One-time tips already shown, by name (e.g. the main screen's
  /// "edit right here" lines, each list's swipe hint).
  final Set<String> tipsSeen;

  /// In stage mode (on the active set) until it's exited, even across a
  /// relaunch (ui-spec.md "Stage mode").
  final bool stageMode;

  Library copyWith({
    List<Song>? songs,
    List<Setlist>? setlists,
    int? lastBpm,
    MetronomePattern? lastPattern,
    OnStart? lastOnStart,
    Duration? visualOffset,
    ClickSound? clickSound,
    ThemeMode? themeMode,
    bool? vibrate,
    bool? partChangeSound,
    KeepScreenOn? keepScreenOn,
    ClickVolumes? volumes,
    Set<String>? tipsSeen,
    bool? stageMode,
  }) => Library(
    songs: songs ?? this.songs,
    setlists: setlists ?? this.setlists,
    lastBpm: lastBpm ?? this.lastBpm,
    lastPattern: lastPattern ?? this.lastPattern,
    lastOnStart: lastOnStart ?? this.lastOnStart,
    visualOffset: visualOffset ?? this.visualOffset,
    clickSound: clickSound ?? this.clickSound,
    themeMode: themeMode ?? this.themeMode,
    vibrate: vibrate ?? this.vibrate,
    partChangeSound: partChangeSound ?? this.partChangeSound,
    keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    volumes: volumes ?? this.volumes,
    activeSetlistId: activeSetlistId,
    currentSongId: currentSongId,
    currentPosition: currentPosition,
    tipsSeen: tipsSeen ?? this.tipsSeen,
    stageMode: stageMode ?? this.stageMode,
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
    lastOnStart: lastOnStart,
    visualOffset: visualOffset,
    clickSound: clickSound,
    themeMode: themeMode,
    vibrate: vibrate,
    partChangeSound: partChangeSound,
    keepScreenOn: keepScreenOn,
    volumes: volumes,
    activeSetlistId: setlistId,
    currentSongId: songId,
    currentPosition: position,
    tipsSeen: tipsSeen,
    stageMode: stageMode,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'lastBpm': lastBpm,
    'lastPattern': lastPattern.toJson(),
    'lastOnStart': lastOnStart.toJson(),
    'visualOffsetMs': visualOffset.inMilliseconds,
    'clickSound': clickSound.name,
    'themeMode': themeMode.name,
    'vibrate': vibrate,
    'partChangeSound': partChangeSound,
    'keepScreenOn': keepScreenOn.name,
    'volumes': volumes.toJson(),
    'activeSetlistId': activeSetlistId,
    'currentSongId': currentSongId,
    'currentPosition': currentPosition,
    'tipsSeen': tipsSeen.toList(),
    'stageMode': stageMode,
    'songs': [for (final song in songs) song.toJson()],
    'setlists': [for (final setlist in setlists) setlist.toJson()],
  };

  /// Any saved version, as one map (both files' contents): migrated to the
  /// latest format, parsed, then [repaired]. Throws on a file from a newer
  /// app version, and on a malformed one (no song or setlist lists). A bad
  /// song, setlist or setting is skipped or falls back, so one broken entry
  /// doesn't hide the rest of the library.
  factory Library.fromJson(Map<String, Object?> json) {
    final fileVersion = json['version'] as int;
    if (fileVersion > version) throw NewerLibraryException(fileVersion);
    final latest = migrate(json);
    final songs = latest['songs'] as List;
    final setlists = latest['setlists'] as List;
    T read<T>(String key, T fallback) =>
        _orNull(() => latest[key] as T) ?? fallback;
    return Library(
      lastBpm: read('lastBpm', empty.lastBpm),
      lastPattern:
          _orNull(
            () => MetronomePattern.fromJson(
              latest['lastPattern'] as Map<String, Object?>,
            ),
          ) ??
          empty.lastPattern,
      lastOnStart:
          _orNull(
            () =>
                OnStart.fromJson(latest['lastOnStart'] as Map<String, Object?>),
          ) ??
          OnStart.off,
      visualOffset: Duration(milliseconds: read('visualOffsetMs', 0)),
      clickSound:
          ClickSound.values.asNameMap()[latest['clickSound']] ??
          ClickSound.woodblock,
      themeMode:
          ThemeMode.values.asNameMap()[latest['themeMode']] ?? ThemeMode.system,
      vibrate: read('vibrate', true),
      partChangeSound: read('partChangeSound', false),
      keepScreenOn:
          KeepScreenOn.values.asNameMap()[latest['keepScreenOn']] ??
          KeepScreenOn.whileOpen,
      volumes:
          _orNull(
            () => ClickVolumes.fromJson(
              latest['volumes'] as Map<String, Object?>,
            ),
          ) ??
          ClickVolumes.defaults,
      activeSetlistId: read<String?>('activeSetlistId', null),
      currentSongId: read<String?>('currentSongId', null),
      currentPosition: read('currentPosition', -1),
      tipsSeen: {
        ...?_orNull(() => (latest['tipsSeen'] as List).whereType<String>()),
      },
      stageMode: read('stageMode', false),
      songs: [
        for (final song in songs)
          ?_orNull(() => Song.fromJson(song as Map<String, Object?>)),
      ],
      setlists: [
        for (final setlist in setlists)
          ?_orNull(() => Setlist.fromJson(setlist as Map<String, Object?>)),
      ],
    ).repaired();
  }

  /// The library made consistent (never throws): duplicate song or setlist
  /// ids keep their first entry; set entries for songs that don't exist are
  /// dropped (a song listed twice stays); tempos, time signatures and the
  /// flash offset are clamped into range; the session (set, song,
  /// position) points at what exists or is cleared.
  Library repaired() {
    int bpm(int v) => v.clamp(30, 300);
    final songIds = <String>{};
    final fixedSongs = [
      for (final song in songs)
        if (songIds.add(song.id)) song.copyWith(parts: _fixParts(song.parts)),
    ];
    final setIds = <String>{};
    final fixedSets = [
      for (final set in setlists)
        if (setIds.add(set.id))
          set.copyWith(
            songIds: [
              for (final id in set.songIds)
                if (songIds.contains(id)) id,
            ],
          ),
    ];
    final active = fixedSets.where((s) => s.id == activeSetlistId).firstOrNull;
    final songId = songIds.contains(currentSongId) ? currentSongId : null;
    var position = -1;
    if (active != null && songId != null) {
      final ids = active.songIds;
      position =
          currentPosition >= 0 &&
              currentPosition < ids.length &&
              ids[currentPosition] == songId
          ? currentPosition
          : ids.indexOf(songId);
    }
    final offset = visualOffset.inMilliseconds.clamp(-200, 500);
    return Library(
      songs: fixedSongs,
      setlists: fixedSets,
      lastBpm: bpm(lastBpm),
      lastPattern: _fixPattern(lastPattern),
      lastOnStart: lastOnStart,
      visualOffset: Duration(milliseconds: offset),
      clickSound: clickSound,
      themeMode: themeMode,
      vibrate: vibrate,
      partChangeSound: partChangeSound,
      keepScreenOn: keepScreenOn,
      volumes: volumes,
      activeSetlistId: active?.id,
      currentSongId: songId,
      currentPosition: position,
      tipsSeen: tipsSeen,
      // Stage mode plays a set: without one it's over.
      stageMode: stageMode && active != null,
    );
  }

  /// Tempos and patterns in range, and 1–999 bars.
  static List<SongPart> _fixParts(List<SongPart> parts) => [
    for (final part in parts)
      part.copyWith(
        bars: part.bars.clamp(1, 999),
        tempoStart: part.tempoStart.clamp(30, 300),
        tempoEnd: part.tempoEnd.clamp(30, 300),
        pattern: _fixPattern(part.pattern),
      ),
  ];

  /// 1–16 beats, 1–4 clicks per beat, a 4 or 8 unit.
  static MetronomePattern _fixPattern(MetronomePattern p) {
    var fixed = p;
    if (fixed.beatsPerBar > maxBeats) fixed = fixed.withBeats(maxBeats);
    if (fixed.stepsPerBeat > 4) fixed = fixed.withSubdivision(4);
    if (fixed.beatUnit != 4 && fixed.beatUnit != 8) {
      fixed = fixed.withBeats(fixed.beatsPerBar, beatUnit: 4);
    }
    return fixed;
  }

  /// The most beats a bar can have (the time signature controls' limit).
  static const maxBeats = 16;

  /// The settings file's part of [toJson] (everything but songs and sets).
  Map<String, Object?> settingsJson() => {
    for (final MapEntry(:key, :value) in toJson().entries)
      if (!libraryKeys.contains(key)) key: value,
  };

  /// The library file's part of [toJson].
  Map<String, Object?> libraryJson() => {
    'version': version,
    'songs': [for (final song in songs) song.toJson()],
    'setlists': [for (final setlist in setlists) setlist.toJson()],
  };

  static T? _orNull<T>(T Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }
}

/// Settings → "Keep screen on" (ui-spec.md "Behavior").
enum KeepScreenOn { whileOpen, whilePlaying }

/// The file was saved by a newer app version (after a downgrade). It is
/// left as it is, so updating the app again opens it.
class NewerLibraryException implements Exception {
  const NewerLibraryException(this.fileVersion);

  final int fileVersion;

  @override
  String toString() =>
      'Library version $fileVersion is newer than ${Library.version}';
}
