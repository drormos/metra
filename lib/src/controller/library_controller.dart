import 'package:flutter/foundation.dart';

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
  Future<void> _lastSave = Future.value();
  int _idCounter = 0;
  String? _selectedSetlistId;
  String? _currentSongId;
  // Position in [visibleSongs]; disambiguates a song listed twice.
  int _currentIndex = -1;

  List<Song> get songs => _library.songs;
  List<Setlist> get setlists => _library.setlists;

  /// The setlist shown in the song panel; null shows all songs.
  Setlist? get selectedSetlist {
    for (final list in setlists) {
      if (list.id == _selectedSetlistId) return list;
    }
    return null;
  }

  void selectSetlist(String? id) {
    _selectedSetlistId = id;
    notifyListeners();
  }

  /// Songs of the selected setlist in order, or all songs.
  List<Song> get visibleSongs {
    final list = selectedSetlist;
    if (list == null) return songs;
    return [for (final id in list.songIds) ?songById(id)];
  }

  /// The song last loaded into the metronome.
  Song? get currentSong =>
      _currentSongId == null ? null : songById(_currentSongId!);

  /// Where the current song sits in [visibleSongs], or -1.
  int get currentIndex {
    final songs = visibleSongs;
    if (_currentIndex >= 0 &&
        _currentIndex < songs.length &&
        songs[_currentIndex].id == _currentSongId) {
      return _currentIndex;
    }
    return songs.indexWhere((s) => s.id == _currentSongId);
  }

  /// With no current song in the list, "next" is the first song.
  bool get hasNext => currentIndex < visibleSongs.length - 1;
  bool get hasPrevious => currentIndex > 0;

  /// Load [song] ([index] = its position in [visibleSongs], if known);
  /// while playing it takes over at the next bar line.
  void playSong(Song song, MetronomeController metronome, {int? index}) {
    metronome.switchTo(bpm: song.bpm, pattern: song.pattern);
    _currentSongId = song.id;
    _currentIndex = index ?? visibleSongs.indexWhere((s) => s.id == song.id);
    notifyListeners();
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
    final list = selectedSetlist;
    if (list != null) addToSetlist(list.id, song.id);
    _currentSongId = song.id;
    _currentIndex = visibleSongs.length - 1;
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

  /// Restores the last session's tempo, pattern and flash offset into
  /// [metronome], then saves them whenever they change.
  void attach(MetronomeController metronome) {
    metronome
      ..setBpm(_library.lastBpm)
      ..setPattern(_library.lastPattern)
      ..setVisualOffset(_library.visualOffset);
    metronome.addListener(() {
      if (metronome.bpm == _library.lastBpm &&
          metronome.pattern == _library.lastPattern &&
          metronome.visualOffset == _library.visualOffset) {
        return;
      }
      _update(
        _library.copyWith(
          lastBpm: metronome.bpm,
          lastPattern: metronome.pattern,
          visualOffset: metronome.visualOffset,
        ),
      );
    });
  }

  /// Completes when every save so far has been written.
  @visibleForTesting
  Future<void> flush() => _lastSave;

  void _update(Library library) {
    _library = library;
    notifyListeners();
    // A failed write leaves the previous file intact; the next change
    // retries with the full library.
    _lastSave = _store
        .save(library)
        .catchError((Object e) => debugPrint('Saving library failed: $e'));
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_idCounter++}';
}
