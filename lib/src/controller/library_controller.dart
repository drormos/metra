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

  List<Song> get songs => _library.songs;
  List<Setlist> get setlists => _library.setlists;

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
