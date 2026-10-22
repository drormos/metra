import 'dart:math';

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

  // This session only (a fresh launch starts in Free play): where the
  // Setlists and Songs tabs return to.
  ({String id, String? songId, int position})? _sessionSet;
  String? _sessionSongId;

  // A tab shown with nothing to load (no songs / no sets yet).
  ModeTab? _emptyTab;

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
  void detachSong() {
    _emptyTab = null;
    _update(_library.withSession(setlistId: null, songId: null, position: -1));
  }

  /// The mode tab that is current. An empty Songs / Setlists tab (nothing
  /// to load yet) is Free play underneath: no song, the click unchanged.
  ModeTab get tab {
    if (activeSetlist != null) return ModeTab.setlists;
    if (singleSong) return ModeTab.songs;
    return switch (_emptyTab) {
      ModeTab.songs when songs.isEmpty => ModeTab.songs,
      ModeTab.setlists when setlists.isEmpty => ModeTab.setlists,
      _ => ModeTab.freePlay,
    };
  }

  /// The Setlists tab: back to the set used this session, at the same
  /// song; otherwise the most recently used set (or the first) at song 1.
  /// No sets: the tab shows its empty state. Already there: nothing.
  void openSetlistsTab(MetronomeController metronome) {
    if (tab == ModeTab.setlists) return;
    final session = _sessionSet;
    if (session != null && setlists.any((l) => l.id == session.id)) {
      setActiveSetlist(session.id);
      final songs = visibleSongs;
      final p = session.position;
      final index = p >= 0 && p < songs.length && songs[p].id == session.songId
          ? p
          : songs.indexWhere((s) => s.id == session.songId);
      if (index >= 0) return playSong(songs[index], metronome, index: index);
      if (songs.isNotEmpty) playSong(songs.first, metronome, index: 0);
      return;
    }
    final recent = setlistsRecentlyPlayed;
    if (recent.isEmpty) return _showEmpty(ModeTab.setlists);
    loadSetlist(recent.first.id, metronome);
  }

  /// The Songs tab: back to the song used this session; otherwise the
  /// most recently played song (or the first A–Z). No songs: the tab shows
  /// its empty state. Already there: nothing.
  void openSongsTab(MetronomeController metronome) {
    if (tab == ModeTab.songs) return;
    final session = _sessionSongId;
    final song =
        (session == null ? null : songById(session)) ??
        _mostRecentlyPlayed ??
        (songs.isEmpty ? null : songsAZ.first);
    if (song == null) return _showEmpty(ModeTab.songs);
    playSingleSong(song, metronome);
  }

  Song? get _mostRecentlyPlayed {
    Song? latest;
    for (final song in songs) {
      final at = song.playedAt;
      if (at != null && (latest == null || at.isAfter(latest.playedAt!))) {
        latest = song;
      }
    }
    return latest;
  }

  void _showEmpty(ModeTab tab) {
    detachSong();
    _emptyTab = tab;
    notifyListeners();
  }

  /// Loads a setlist, or Free play with null (which detaches the song).
  /// Only the mode changes: the click keeps going as it is.
  void setActiveSetlist(String? id) {
    if (id == null) return detachSong();
    _emptyTab = null;
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

  /// What next/previous step through: the set in setlist mode, the whole
  /// library A–Z in Single song mode, nothing in Free play.
  List<Song> get _stepSongs => activeSetlist != null
      ? visibleSongs
      : singleSong
      ? songsAZ
      : const [];

  int get _stepIndex => activeSetlist != null
      ? currentIndex
      : _stepSongs.indexWhere((s) => s.id == _library.currentSongId);

  /// With no current song in the set, "next" is its first song.
  bool get hasNext =>
      (activeSetlist != null || singleSong) &&
      _stepIndex < _stepSongs.length - 1;
  bool get hasPrevious =>
      (activeSetlist != null || singleSong) && _stepIndex > 0;

  /// The song next/previous would load, or null at the ends.
  Song? get songAfter => hasNext ? _stepSongs[_stepIndex + 1] : null;
  Song? get songBefore => hasPrevious ? _stepSongs[_stepIndex - 1] : null;

  /// Load [song] ([index] = its position in [visibleSongs], if known);
  /// while playing it restarts on beat 1 at the song's tempo.
  void playSong(Song song, MetronomeController metronome, {int? index}) {
    metronome.loadSong(bpm: song.bpm, pattern: song.pattern);
    _emptyTab = null;
    _update(
      _played(song.id).withSession(
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
    _emptyTab = null;
    _update(
      _played(song.id)
          .withSession(setlistId: null, songId: song.id, position: -1),
    );
  }

  /// The library with [songId] marked as just loaded.
  Library _played(String songId) {
    final now = DateTime.now();
    return _library.copyWith(
      songs: [
        for (final s in songs) s.id == songId ? s.copyWith(playedAt: now) : s,
      ],
    );
  }

  /// Steps through the set, or the library A–Z in Single song mode (it
  /// stays Single song); stops at the ends instead of wrapping, so an
  /// extra press on stage can't jump back to the first song.
  void nextSong(MetronomeController metronome) => _stepBy(1, metronome);

  void previousSong(MetronomeController metronome) => _stepBy(-1, metronome);

  void _stepBy(int delta, MetronomeController metronome) {
    final song = delta > 0 ? songAfter : songBefore;
    if (song == null) return;
    if (activeSetlist == null) return playSingleSong(song, metronome);
    playSong(song, metronome, index: _stepIndex + delta);
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
    bool fresh = false,
  }) {
    final index = currentIndex;
    final list = activeSetlist;
    final song = addSong(
      name: name,
      bpm: metronome.bpm,
      pattern: metronome.pattern,
    );
    _freshSongId = fresh ? song.id : null;
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

  /// The set panel's swipe-to-remove: the entry at [index] leaves the set
  /// (never the library). In the active set, removing an entry before the
  /// current one moves the position back ("4/12" → "3/11"). Removing the
  /// current song itself hands over (ui-spec.md "Removing what's loaded"):
  /// the song now at that position, else the new last, loads; an empty set
  /// stays loaded with no song and the click as it is.
  void removeSongAt(
    String setlistId,
    int index,
    MetronomeController metronome,
  ) {
    final active = setlistId == _library.activeSetlistId;
    final current = active ? currentIndex : -1;
    final list = setlists.firstWhere((s) => s.id == setlistId);
    final ids = [...list.songIds]..removeAt(index);
    if (index != current) {
      _updateEntries(
        list,
        ids,
        position: current > index ? current - 1 : current,
      );
      return;
    }
    _updateEntries(list, ids, position: -1);
    _takeOverInSet(index, metronome);
  }

  /// Undo of [removeSongAt]: [songId] back at [index], the position
  /// following it. [wasCurrent]: it loads again (normal loading rules).
  void insertSongAt(
    String setlistId,
    int index,
    String songId,
    MetronomeController metronome, {
    bool wasCurrent = false,
  }) {
    final active = setlistId == _library.activeSetlistId;
    final current = active ? currentIndex : -1;
    final list = setlists.firstWhere((s) => s.id == setlistId);
    _updateEntries(
      list,
      [...list.songIds]..insert(min(index, list.songIds.length), songId),
      position: current >= index ? current + 1 : current,
    );
    if (wasCurrent) _loadAgain(setlistId, songId, index, metronome);
  }

  /// The current song of the active set is gone: the song now at
  /// [position] loads, else the last one; with none left the set stays
  /// loaded, empty, and the click keeps what it sounds like.
  void _takeOverInSet(int position, MetronomeController metronome) {
    final list = activeSetlist;
    if (list == null) return;
    final songs = visibleSongs;
    if (songs.isEmpty) {
      _update(
        _library.withSession(setlistId: list.id, songId: null, position: -1),
      );
      return;
    }
    final i = min(position, songs.length - 1);
    playSong(songs[i], metronome, index: i);
  }

  /// Undo makes [songId] current again: in its set at [position], or as
  /// Single song (null [setlistId]).
  void _loadAgain(
    String? setlistId,
    String songId,
    int position,
    MetronomeController metronome,
  ) {
    final song = songById(songId);
    if (song == null) return;
    if (setlistId == null) return playSingleSong(song, metronome);
    if (!setlists.any((l) => l.id == setlistId)) return;
    if (_library.activeSetlistId != setlistId) setActiveSetlist(setlistId);
    final songs = visibleSongs;
    final index =
        position >= 0 && position < songs.length && songs[position].id == songId
        ? position
        : songs.indexWhere((s) => s.id == songId);
    playSong(song, metronome, index: index < 0 ? null : index);
  }

  void _updateEntries(Setlist list, List<String> ids, {required int position}) {
    final updated = _library.copyWith(
      setlists: [
        for (final s in setlists)
          s.id == list.id ? s.copyWith(songIds: ids) : s,
      ],
    );
    _update(
      list.id == _library.activeSetlistId && position >= 0
          ? updated.withSession(
              setlistId: list.id,
              songId: _library.currentSongId,
              position: position,
            )
          : updated,
    );
  }

  /// Renames a set; an empty name keeps the old one. Duplicates allowed.
  void renameSetlist(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = setlists.firstWhere((s) => s.id == id);
    if (list.name != trimmed) updateSetlist(list.copyWith(name: trimmed));
  }

  /// A new set ("Setlist N") at the top of the recently played order.
  Setlist createSetlist() {
    final setlist = Setlist(
      id: _newId(),
      name: newSetlistName(),
      songIds: const [],
      playedAt: DateTime.now(),
    );
    _update(_library.copyWith(setlists: [...setlists, setlist]));
    return setlist;
  }

  /// The sets view's swipe-to-delete. Deleting the loaded set hands over
  /// (ui-spec.md "Removing what's loaded"): the most recently used other
  /// set loads at song 1; with none left, setlist mode stays with no set
  /// and the click as it is. Returns what [restoreSetlist] needs.
  DeletedSetlist? deleteSetlistAt(String id, MetronomeController metronome) {
    final index = setlists.indexWhere((s) => s.id == id);
    if (index < 0) return null;
    final loaded = id == _library.activeSetlistId;
    final deleted = (
      setlist: setlists[index],
      index: index,
      loaded: loaded
          ? (songId: _library.currentSongId, position: _library.currentPosition)
          : null,
    );
    deleteSetlists({id});
    if (loaded) {
      final others = setlistsRecentlyPlayed;
      others.isEmpty
          ? _showEmpty(ModeTab.setlists)
          : loadSetlist(others.first.id, metronome);
    }
    return deleted;
  }

  /// Undo of [deleteSetlistAt]: the set back in place, as it was; if it
  /// was loaded, loaded again at the same song.
  void restoreSetlist(DeletedSetlist deleted, MetronomeController metronome) {
    final setlist = deleted.setlist;
    if (setlists.any((s) => s.id == setlist.id)) return;
    _update(
      _library.copyWith(
        setlists: [...setlists]
          ..insert(min(deleted.index, setlists.length), setlist),
      ),
    );
    final loaded = deleted.loaded;
    if (loaded == null) return;
    final songId = loaded.songId;
    if (songId == null || !setlist.songIds.contains(songId)) {
      return setActiveSetlist(setlist.id);
    }
    _loadAgain(setlist.id, songId, loaded.position, metronome);
  }

  /// The set panel's one-time swipe hint (stored, never repeats).
  bool get swipeHintSeen => _library.swipeHintSeen;

  void markSwipeHintSeen() {
    if (!swipeHintSeen) _update(_library.copyWith(swipeHintSeen: true));
  }

  /// The Songs list's own one-time swipe hint.
  bool get songsHintSeen => _library.songsHintSeen;

  void markSongsHintSeen() {
    if (!songsHintSeen) _update(_library.copyWith(songsHintSeen: true));
  }

  /// The sets view's own one-time hint.
  bool get setsHintSeen => _library.setsHintSeen;

  void markSetsHintSeen() {
    if (!setsHintSeen) _update(_library.copyWith(setsHintSeen: true));
  }

  /// Whether the one-time tip [name] was shown.
  bool tipSeen(String name) => _library.tipsSeen.contains(name);

  void markTipSeen(String name) {
    if (tipSeen(name)) return;
    _update(_library.copyWith(tipsSeen: {..._library.tipsSeen, name}));
  }

  /// The song "+ New song" just made (not saved), until another loads.
  String? get freshSongId => _freshSongId;
  String? _freshSongId;

  /// Renames a song; an empty name keeps the old one. Duplicates allowed.
  void renameSong(String id, String name) {
    final trimmed = name.trim();
    final song = songById(id);
    if (trimmed.isEmpty || song == null || song.name == trimmed) return;
    updateSong(song.copyWith(name: trimmed));
  }

  /// The Songs list's swipe-to-delete (after its dialog): the song leaves
  /// the library and every set, handing over if it was loaded (see
  /// [deleteSongs]). Returns what [restoreSong] needs to put it all back.
  DeletedSong? deleteSongForUndo(String id, MetronomeController metronome) {
    final index = songs.indexWhere((s) => s.id == id);
    if (index < 0) return null;
    final places = {
      for (final list in setlists)
        if (list.songIds.contains(id))
          list.id: [
            for (final (i, s) in list.songIds.indexed)
              if (s == id) i,
          ],
    };
    final deleted = (
      song: songs[index],
      index: index,
      places: places,
      current: currentSong?.id == id
          ? (
              setlistId: _library.activeSetlistId,
              position: _library.currentPosition,
            )
          : null,
    );
    deleteSongs({id}, metronome);
    return deleted;
  }

  /// Undo of [deleteSongForUndo]: the song back in the library and in each
  /// set at its old positions; if it was loaded, loaded again.
  void restoreSong(DeletedSong deleted, MetronomeController metronome) {
    if (songById(deleted.song.id) != null) return;
    List<String> withSong(List<String> ids, List<int> positions) {
      final restored = [...ids];
      for (final p in positions) {
        restored.insert(min(p, restored.length), deleted.song.id);
      }
      return restored;
    }

    _update(
      _library.copyWith(
        songs: [...songs]
          ..insert(min(deleted.index, songs.length), deleted.song),
        setlists: [
          for (final list in setlists)
            switch (deleted.places[list.id]) {
              final positions? => list.copyWith(
                songIds: withSong(list.songIds, positions),
              ),
              _ => list,
            },
        ],
      ),
    );
    final current = deleted.current;
    if (current != null) {
      _loadAgain(
        current.setlistId,
        deleted.song.id,
        current.position,
        metronome,
      );
    }
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

  void updateSong(Song song) {
    final edited = song.copyWith(editedAt: DateTime.now());
    _update(
      _library.copyWith(
        songs: [for (final s in songs) s.id == song.id ? edited : s],
      ),
    );
  }

  /// Deletes songs from the library and every set. Deleting the loaded
  /// song hands over and keeps the mode (ui-spec.md "Removing what's
  /// loaded"): Single song loads the next song A–Z (else the previous); in
  /// a set the entry now in its place (else the last) loads; with nothing
  /// left the mode stays, empty, with the click as it is.
  void deleteSongs(Set<String> ids, MetronomeController metronome) {
    final set = activeSetlist;
    final current = currentSong;
    final hit = current != null && ids.contains(current.id);
    // The replacement, chosen before anything goes: Single song, the next
    // song A–Z still there, else the previous; in a set, the entry that
    // will sit where the current one was.
    Song? next;
    var position = -1;
    if (hit && set == null) {
      final az = songsAZ;
      final at = az.indexWhere((s) => s.id == current.id);
      bool kept(Song s) => !ids.contains(s.id);
      next =
          az.skip(at + 1).where(kept).firstOrNull ??
          az.take(at).toList().reversed.where(kept).firstOrNull;
    } else if (hit) {
      final songs = visibleSongs;
      position = [
        for (final s in songs.take(currentIndex))
          if (!ids.contains(s.id)) s,
      ].length;
    }
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
    // A loaded song that isn't current any more (taken out of the active
    // set earlier) just goes.
    _update(
      !hit && ids.contains(_library.currentSongId)
          ? deleted.withSession(
              setlistId: _library.activeSetlistId,
              songId: null,
              position: -1,
            )
          : deleted,
    );
    if (!hit) return;
    // Hand over (ui-spec.md "Removing what's loaded"); the mode stays.
    if (set != null) return _takeOverInSet(position, metronome);
    if (next != null) return playSingleSong(next, metronome);
    _showEmpty(ModeTab.songs);
  }

  void deleteSong(String id, MetronomeController metronome) =>
      deleteSongs({id}, metronome);

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
    final before = _library;
    _library = library;
    // Only a change of mode or song counts: the session stored by the last
    // run (until main detaches it) is not this session's.
    final moved =
        library.activeSetlistId != before.activeSetlistId ||
        library.currentSongId != before.currentSongId ||
        library.currentPosition != before.currentPosition;
    if (moved) {
      if (activeSetlist case final set?) {
        _sessionSet = (
          id: set.id,
          songId: library.currentSongId,
          position: library.currentPosition,
        );
      } else if (singleSong) {
        _sessionSongId = library.currentSongId;
      }
    }
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

/// The main screen's mode tabs (ui-spec.md "Mode tabs").
enum ModeTab { songs, freePlay, setlists }

/// A song taken out by [LibraryController.deleteSongForUndo]: the song,
/// its place in the library, and its positions in each set (by set id).
typedef DeletedSong = ({
  Song song,
  int index,
  Map<String, List<int>> places,
  ({String? setlistId, int position})? current,
});

/// A set taken out by [LibraryController.deleteSetlistAt]: the set, its
/// place, and the song it was on if it was the loaded one.
typedef DeletedSetlist = ({
  Setlist setlist,
  int index,
  ({String? songId, int position})? loaded,
});
