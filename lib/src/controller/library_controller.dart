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
  bool _saveFailed = false;

  /// The last save failed; cleared by the next one that works.
  bool get saveFailed => _saveFailed;

  ThemeMode get themeMode => _library.themeMode;

  void setThemeMode(ThemeMode mode) {
    if (mode != themeMode) _update(_library.copyWith(themeMode: mode));
  }

  /// "Vibrate on touch" (default on).
  bool get vibrate => _library.vibrate;

  void setVibrate(bool on) {
    if (on != vibrate) _update(_library.copyWith(vibrate: on));
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

  /// Single song mode: a library song loaded without a setlist.
  bool get singleSong => activeSetlist == null && currentSong != null;

  /// Free play: unloads the song (and any setlist). The click keeps
  /// exactly what it sounds like, unsaved changes included; the song in
  /// the library is untouched.
  void detachSong() => _update(
    _library.withSession(setlistId: null, songId: null, position: -1),
  );

  /// Loads a setlist, or Free play with null (which detaches the song).
  /// Only the mode changes: the click keeps going as it is.
  void setActiveSetlist(String? id) {
    if (id == null) return detachSong();
    final list = setlists.firstWhere((l) => l.id == id);
    _update(
      _library
          .copyWith(
            setlists: [
              for (final l in setlists)
                l.id == id ? l.copyWith(playedAt: DateTime.now()) : l,
            ],
          )
          .withSession(
            setlistId: id,
            songId: _library.currentSongId,
            position: list.songIds.indexOf(_library.currentSongId ?? ''),
          ),
    );
  }

  /// Choosing a set: loads it at its first song (while playing, restarts
  /// on beat 1), even if it's already loaded.
  void loadSetlist(String id, MetronomeController metronome) {
    setActiveSetlist(id);
    final songs = visibleSongs;
    if (songs.isNotEmpty) playSong(songs.first, metronome, index: 0);
  }

  /// Sets loaded most recently first; never-played sets after them, in
  /// creation order.
  List<Setlist> get setlistsRecentlyPlayed {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [...setlists]
      ..sort((a, b) => (b.playedAt ?? epoch).compareTo(a.playedAt ?? epoch));
  }

  /// Songs of the active setlist in order, or all songs in Free play.
  List<Song> get visibleSongs {
    final list = activeSetlist;
    if (list == null) return songs;
    return [for (final id in list.songIds) ?songById(id)];
  }

  /// The song last loaded into the metronome.
  /// With a setlist loaded, only a song in that set counts: one removed
  /// from it (or deleted) leaves the set with no current song, and "next"
  /// is then its first song.
  Song? get currentSong {
    final id = _library.currentSongId;
    final list = activeSetlist;
    if (id == null || (list != null && !list.songIds.contains(id))) {
      return null;
    }
    return songById(id);
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
  /// while playing it restarts on beat 1 at the song's tempo.
  void playSong(Song song, MetronomeController metronome, {int? index}) {
    metronome.loadSong(bpm: song.bpm, pattern: song.pattern);
    _update(
      _library.withSession(
        setlistId: _library.activeSetlistId,
        songId: song.id,
        position: index ?? visibleSongs.indexWhere((s) => s.id == song.id),
      ),
    );
  }

  /// A song from the library: always Single song mode, unloading any
  /// setlist (choosing the set again starts at its first song). While
  /// playing it restarts on beat 1 at the song's tempo.
  void playSingleSong(Song song, MetronomeController metronome) {
    metronome.loadSong(bpm: song.bpm, pattern: song.pattern);
    _update(
      _library.withSession(setlistId: null, songId: song.id, position: -1),
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

  /// Whether main-screen changes (tempo, time signature, subdivision, beat
  /// states) make [metronome] differ from the loaded song. They play but
  /// aren't stored until [saveToSong]; loading a song discards them.
  bool songChanged(MetronomeController metronome) {
    final song = currentSong;
    return song != null &&
        (song.bpm != metronome.bpm || song.pattern != metronome.pattern);
  }

  /// Stores the main-screen changes in the loaded song (every set gets them).
  void saveToSong(MetronomeController metronome) {
    if (currentSong case final song?) updateSongFromMetronome(song, metronome);
  }

  /// Back to the loaded song's stored values; while playing, each change
  /// applies as on the main screen (no restart on beat 1).
  void revertSong(MetronomeController metronome) {
    if (currentSong case final song?) {
      metronome.applyEdit(bpm: song.bpm, pattern: song.pattern);
    }
  }

  /// "Save as new song": a library song from what the click plays now,
  /// made the loaded song (the click carries on, no restart). In setlist
  /// mode [placement] puts it in the set; otherwise, and with
  /// [SongPlacement.none], the app ends in Single song mode. The original
  /// song is untouched everywhere.
  Song saveAsNewSong(
    String name,
    MetronomeController metronome, {
    SongPlacement placement = SongPlacement.replace,
  }) {
    final index = currentIndex;
    final list = activeSetlist;
    final song = addSong(
      name: name,
      bpm: metronome.bpm,
      pattern: metronome.pattern,
    );
    if (list == null || index < 0 || placement == SongPlacement.none) {
      _update(
        _library.withSession(setlistId: null, songId: song.id, position: -1),
      );
      return song;
    }
    final ids = [...list.songIds];
    final position = placement == SongPlacement.replace ? index : index + 1;
    if (placement == SongPlacement.replace) {
      ids[index] = song.id;
    } else {
      ids.insert(position, song.id);
    }
    _update(
      _library
          .copyWith(
            setlists: [
              for (final l in setlists)
                l.id == list.id ? l.copyWith(songIds: ids) : l,
            ],
          )
          .withSession(setlistId: list.id, songId: song.id, position: position),
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

  /// Removes the entries at [indices] (only those occurrences; the songs
  /// stay in the library). Returns the set as it was, for Undo through
  /// [updateSetlist].
  Setlist removeEntries(String setlistId, Set<int> indices) {
    final list = setlists.firstWhere((s) => s.id == setlistId);
    updateSetlist(
      list.copyWith(
        songIds: [
          for (final (i, id) in list.songIds.indexed)
            if (!indices.contains(i)) id,
        ],
      ),
    );
    return list;
  }

  /// Removes the entry at [index] (a song may appear more than once).
  void removeFromSetlist(String setlistId, int index) {
    final list = setlists.firstWhere((s) => s.id == setlistId);
    updateSetlist(list.copyWith(songIds: [...list.songIds]..removeAt(index)));
  }

  /// Moves the entry at [oldIndex] so it ends up at [newIndex]. In the
  /// active set, the current song keeps being current (its position
  /// follows), so next/previous continue from it.
  void reorderSetlist(String setlistId, int oldIndex, int newIndex) {
    final current = currentIndex; // before the move
    final list = setlists.firstWhere((s) => s.id == setlistId);
    final ids = [...list.songIds];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    updateSetlist(list.copyWith(songIds: ids));
    if (setlistId != _library.activeSetlistId || current < 0) return;
    var moved = current == oldIndex
        ? newIndex
        : current - (oldIndex < current ? 1 : 0);
    if (current != oldIndex && newIndex <= moved) moved++;
    _update(
      _library.withSession(
        setlistId: setlistId,
        songId: _library.currentSongId,
        position: moved,
      ),
    );
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
    final song = Song(
      id: _newId(),
      name: name,
      bpm: bpm,
      pattern: pattern,
      editedAt: DateTime.now(),
    );
    _update(_library.copyWith(songs: [...songs, song]));
    return song;
  }

  /// A default name for a new song: "Song N", N the lowest number not
  /// already used (worked out from the current names every time).
  String newSongName() =>
      _newName('Song', [for (final song in songs) song.name]);

  /// "Setlist N", like [newSongName].
  String newSetlistName() =>
      _newName('Setlist', [for (final list in setlists) list.name]);

  /// A name for a copy of [song]: its name plus the next free number
  /// ("Dead Weight 2"); a copy of a copy counts on ("Dead Weight 3").
  String copyName(Song song) => _newName(
    song.name.replaceFirst(RegExp(r' \d+$'), ''),
    [for (final s in songs) s.name],
    start: 2,
  );

  static String _newName(String prefix, List<String> names, {int start = 1}) {
    final taken = {for (final name in names) _nameKey(name)};
    var n = start;
    while (taken.contains(_nameKey('$prefix $n'))) {
      n++;
    }
    return '$prefix $n';
  }

  /// Names compare without case or surrounding spaces.
  static String _nameKey(String name) => name.trim().toLowerCase();

  /// Whether another song (not [exceptId]) already has [name].
  bool songNameTaken(String name, {String? exceptId}) => songs.any(
    (song) => song.id != exceptId && _nameKey(song.name) == _nameKey(name),
  );

  /// Whether another setlist (not [exceptId]) already has [name].
  bool setlistNameTaken(String name, {String? exceptId}) => setlists.any(
    (list) => list.id != exceptId && _nameKey(list.name) == _nameKey(name),
  );

  void updateSong(Song song) {
    final edited = song.copyWith(editedAt: DateTime.now());
    _update(
      _library.copyWith(
        songs: [for (final s in songs) s.id == song.id ? edited : s],
      ),
    );
  }

  /// Most recently created or saved first; songs without a time last.
  List<Song> get songsRecentlyEdited {
    // Songs saved before edit times were recorded sort as oldest.
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [...songs]
      ..sort((a, b) => (b.editedAt ?? epoch).compareTo(a.editedAt ?? epoch));
  }

  /// Deletes songs from the library and every set. Deleting the loaded
  /// song switches to Free play; the click keeps going as it is.
  void deleteSongs(Set<String> ids) {
    final deleted = _library.copyWith(
      songs: [
        for (final s in songs)
          if (!ids.contains(s.id)) s,
      ],
      setlists: [
        for (final list in setlists)
          list.copyWith(
            songIds: [
              for (final s in list.songIds)
                if (!ids.contains(s)) s,
            ],
          ),
      ],
    );
    _update(
      ids.contains(_library.currentSongId)
          ? deleted.withSession(setlistId: null, songId: null, position: -1)
          : deleted,
    );
  }

  void deleteSong(String id) => deleteSongs({id});

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

  /// Never deletes songs. Deleting the loaded set switches to Free play,
  /// keeping the click as it sounds.
  void deleteSetlists(Set<String> ids) {
    final deleted = _library.copyWith(
      setlists: [
        for (final s in setlists)
          if (!ids.contains(s.id)) s,
      ],
    );
    _update(
      ids.contains(_library.activeSetlistId)
          ? deleted.withSession(setlistId: null, songId: null, position: -1)
          : deleted,
    );
  }

  void deleteSetlist(String id) => deleteSetlists({id});

  /// Restores the last session's tempo, pattern, flash offset, click
  /// sound and volumes into [metronome], then saves them whenever they
  /// change.
  void attach(MetronomeController metronome) {
    metronome
      ..setBpm(_library.lastBpm)
      ..setPattern(_library.lastPattern)
      ..setVisualOffset(_library.visualOffset)
      ..setClickSound(_library.clickSound, preview: false)
      ..setVolumes(_library.volumes);
    metronome.addListener(() {
      if (metronome.bpm == _library.lastBpm &&
          metronome.pattern == _library.lastPattern &&
          metronome.visualOffset == _library.visualOffset &&
          metronome.clickSound == _library.clickSound &&
          metronome.volumes == _library.volumes) {
        return;
      }
      _update(
        _library.copyWith(
          lastBpm: metronome.bpm,
          lastPattern: metronome.pattern,
          visualOffset: metronome.visualOffset,
          clickSound: metronome.clickSound,
          volumes: metronome.volumes,
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
        _setSaveFailed(false);
      } catch (e) {
        debugPrint('Saving library failed: $e');
        _setSaveFailed(true);
      }
    }
    _writing = null;
  }

  void _setSaveFailed(bool failed) {
    if (failed == _saveFailed) return;
    _saveFailed = failed;
    notifyListeners();
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_idCounter++}';
}

/// Where "Save as new song" puts the new song in the loaded set.
enum SongPlacement {
  /// Takes the loaded song's place (same position).
  replace,

  /// Right after the loaded song; both stay.
  addAfter,

  /// Not in the set: the app leaves it (Single song mode).
  none,
}
