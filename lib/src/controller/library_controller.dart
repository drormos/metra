import 'package:flutter/material.dart'
    show ChangeNotifier, ThemeMode, debugPrint, visibleForTesting;

import '../model/library.dart';
import '../model/metronome_pattern.dart';
import '../storage/library_store.dart';
import 'metronome_controller.dart';

/// Songs, setlists and saved settings. Every change is saved right away.
class LibraryController extends ChangeNotifier {
  LibraryController._(this._store, this._library);

  static Future<LibraryController> load(LibraryStore store) async =>
      LibraryController._(store, await store.load());

  final LibraryStore _store;
  Library _library;
  // Coalesced saving: one write at a time, always of the latest library.
  Library? _unsaved;
  Future<void>? _writing;
  int _idCounter = 0;

  ThemeMode get themeMode => _library.themeMode;

  void setThemeMode(ThemeMode mode) {
    if (mode != themeMode) _update(_library.copyWith(themeMode: mode));
  }

  List<Song> get songs => _library.songs;
  List<Setlist> get setlists => _library.setlists;

  /// The loaded setlist; null is Free play. A deleted set reads as Free
  /// play.
  Setlist? get activeSetlist {
    for (final list in setlists) {
      if (list.id == _library.activeSetlistId) return list;
    }
    return null;
  }

  /// Loads a setlist, or Free play with null. Only the mode changes: the
  /// click keeps going as it is.
  void setActiveSetlist(String? id) {
    final position = id == null
        ? -1
        : (setlists
                  .where((l) => l.id == id)
                  .firstOrNull
                  ?.songIds
                  .indexOf(_library.currentSongId ?? '') ??
              -1);
    _update(
      _library.withSession(
        setlistId: id,
        songId: _library.currentSongId,
        position: position,
      ),
    );
  }

  /// Songs of the active setlist in order, or all songs in Free play.
  List<Song> get visibleSongs {
    final list = activeSetlist;
    if (list == null) return songs;
    return [for (final id in list.songIds) ?songById(id)];
  }

  /// The song last loaded into the metronome.
  Song? get currentSong {
    final id = _library.currentSongId;
    return id == null ? null : songById(id);
  }

  /// Where the current song sits in [visibleSongs], or -1.
  int get currentIndex {
    final songs = visibleSongs;
    final id = _library.currentSongId;
    final saved = _library.currentPosition;
    if (saved >= 0 && saved < songs.length && songs[saved].id == id) {
      return saved; // disambiguates a song listed twice
    }
    return songs.indexWhere((s) => s.id == id);
  }

  /// Only inside a setlist (hands-free needs an order). With no current
  /// song in the set, "next" is its first song.
  bool get hasNext =>
      activeSetlist != null && currentIndex < visibleSongs.length - 1;
  bool get hasPrevious => activeSetlist != null && currentIndex > 0;

  /// Load [song] ([index] = its position in [visibleSongs], if known);
  /// while playing it takes over at the next bar line.
  void playSong(Song song, MetronomeController metronome, {int? index}) {
    metronome.switchTo(bpm: song.bpm, pattern: song.pattern);
    _update(
      _library.withSession(
        setlistId: _library.activeSetlistId,
        songId: song.id,
        position: index ?? visibleSongs.indexWhere((s) => s.id == song.id),
      ),
    );
  }

  /// Steps through [visibleSongs]; stops at the ends instead of wrapping,
  /// so an extra press on stage can't jump back to the first song.
  void nextSong(MetronomeController metronome) {
    if (!hasNext) return;
    final i = currentIndex + 1;
    playSong(visibleSongs[i], metronome, index: i);
  }

  void previousSong(MetronomeController metronome) {
    if (!hasPrevious) return;
    final i = currentIndex - 1;
    playSong(visibleSongs[i], metronome, index: i);
  }

  /// Saves the metronome's tempo and pattern as a new song, added to the
  /// selected setlist if there is one.
  Song saveCurrentAsSong(String name, MetronomeController metronome) {
    final song = addSong(
      name: name,
      bpm: metronome.bpm,
      pattern: metronome.pattern,
    );
    final list = activeSetlist;
    if (list != null) addToSetlist(list.id, song.id);
    _update(
      _library.withSession(
        setlistId: _library.activeSetlistId,
        songId: song.id,
        position: list == null ? -1 : visibleSongs.length - 1,
      ),
    );
    return song;
  }

  /// Overwrites [song]'s tempo and pattern with the metronome's.
  void updateSongFromMetronome(Song song, MetronomeController metronome) =>
      updateSong(song.copyWith(bpm: metronome.bpm, pattern: metronome.pattern));

  void addToSetlist(String setlistId, String songId) {
    final list = setlists.firstWhere((s) => s.id == setlistId);
    updateSetlist(list.copyWith(songIds: [...list.songIds, songId]));
  }

  /// Removes the entry at [index] (a song may appear more than once).
  void removeFromSetlist(String setlistId, int index) {
    final list = setlists.firstWhere((s) => s.id == setlistId);
    updateSetlist(list.copyWith(songIds: [...list.songIds]..removeAt(index)));
  }

  /// Moves the entry at [oldIndex] so it ends up at [newIndex].
  void reorderSetlist(String setlistId, int oldIndex, int newIndex) {
    final list = setlists.firstWhere((s) => s.id == setlistId);
    final ids = [...list.songIds];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    updateSetlist(list.copyWith(songIds: ids));
  }

  Song? songById(String id) {
    for (final song in songs) {
      if (song.id == id) return song;
    }
    return null;
  }

  Song addSong({
    required String name,
    required int bpm,
    required MetronomePattern pattern,
  }) {
    final song = Song(id: _newId(), name: name, bpm: bpm, pattern: pattern);
    _update(_library.copyWith(songs: [...songs, song]));
    return song;
  }

  void updateSong(Song song) => _update(
    _library.copyWith(
      songs: [for (final s in songs) s.id == song.id ? song : s],
    ),
  );

  /// Also removes the song from every setlist.
  void deleteSong(String id) => _update(
    _library.copyWith(
      songs: [
        for (final s in songs)
          if (s.id != id) s,
      ],
      setlists: [
        for (final list in setlists)
          list.copyWith(
            songIds: [
              for (final s in list.songIds)
                if (s != id) s,
            ],
          ),
      ],
    ),
  );

  /// Every song, A–Z by name (case-insensitive): the library's order.
  List<Song> get songsAZ =>
      [...songs]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Setlists that contain [songId].
  List<Setlist> setlistsUsing(String songId) => [
    for (final list in setlists)
      if (list.songIds.contains(songId)) list,
  ];

  /// Saves an edited setlist ([id] null creates one) in one change.
  Setlist saveSetlist({
    String? id,
    required String name,
    required List<String> songIds,
  }) {
    if (id == null) {
      final setlist = Setlist(id: _newId(), name: name, songIds: songIds);
      _update(_library.copyWith(setlists: [...setlists, setlist]));
      return setlist;
    }
    final setlist = Setlist(id: id, name: name, songIds: songIds);
    updateSetlist(setlist);
    return setlist;
  }

  Setlist addSetlist(String name) {
    final setlist = Setlist(id: _newId(), name: name, songIds: const []);
    _update(_library.copyWith(setlists: [...setlists, setlist]));
    return setlist;
  }

  void updateSetlist(Setlist setlist) => _update(
    _library.copyWith(
      setlists: [for (final s in setlists) s.id == setlist.id ? setlist : s],
    ),
  );

  void deleteSetlist(String id) => _update(
    _library.copyWith(
      setlists: [
        for (final s in setlists)
          if (s.id != id) s,
      ],
    ),
  );

  /// Restores the last session's tempo, pattern, flash offset and click
  /// sound into [metronome], then saves them whenever they change.
  void attach(MetronomeController metronome) {
    metronome
      ..setBpm(_library.lastBpm)
      ..setPattern(_library.lastPattern)
      ..setVisualOffset(_library.visualOffset)
      ..setClickSound(_library.clickSound, preview: false);
    metronome.addListener(() {
      if (metronome.bpm == _library.lastBpm &&
          metronome.pattern == _library.lastPattern &&
          metronome.visualOffset == _library.visualOffset &&
          metronome.clickSound == _library.clickSound) {
        return;
      }
      _update(
        _library.copyWith(
          lastBpm: metronome.bpm,
          lastPattern: metronome.pattern,
          visualOffset: metronome.visualOffset,
          clickSound: metronome.clickSound,
        ),
      );
    });
  }

  /// Completes when every save so far has been written.
  @visibleForTesting
  Future<void> flush() => _writing ?? Future.value();

  void _update(Library library) {
    _library = library;
    notifyListeners();
    _unsaved = library;
    _writing ??= _writeAll();
  }

  /// Rapid changes (a tempo drag) collapse into one write of the latest
  /// state per file write, not one per change. A failed write leaves the
  /// previous file intact; the next change retries with the full library.
  Future<void> _writeAll() async {
    for (var library = _unsaved; library != null; library = _unsaved) {
      _unsaved = null;
      try {
        await _store.save(library);
      } catch (e) {
        debugPrint('Saving library failed: $e');
      }
    }
    _writing = null;
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_idCounter++}';
}
