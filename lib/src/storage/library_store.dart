import 'dart:convert';
import 'dart:io';

import '../model/library.dart';
import '../model/library_migrations.dart';

/// Saves the [Library] in two JSON files side by side: [file]
/// (`library.json`: songs and setlists) and [settingsFile]
/// (`settings.json`: app settings, the session and one-time flags).
///
/// Each write goes to a temp file that is then renamed over the real one,
/// so a crash mid-write never leaves a half-written file; a file whose
/// content hasn't changed isn't rewritten (a tempo drag only touches
/// settings). Saves run one at a time in call order.
///
/// Loading migrates any older format (library_migrations.dart). A version
/// 1 file (one combined `library.json`) is copied to [backupFile] first,
/// and the copy is deleted after the next successful save. An unreadable
/// file is moved into [corruptDir] (the newest [keepCorrupt] are kept) and
/// the rest still loads: broken settings keep the songs, a broken library
/// keeps the settings.
class LibraryStore {
  LibraryStore(this.file)
    : settingsFile = File('${file.parent.path}/settings.json');

  final File file;
  final File settingsFile;

  File get backupFile => File('${file.path}.v1-backup');
  Directory get corruptDir => Directory('${file.parent.path}/corrupt');

  /// Unreadable files kept for recovery, newest first.
  static const keepCorrupt = 3;

  Future<void> _writes = Future.value();
  // What's on disk now, so unchanged files aren't rewritten.
  String? _onDiskLibrary;
  String? _onDiskSettings;
  bool _backupPending = false;

  /// Whether anything was ever saved here (false on a fresh install).
  Future<bool> exists() async =>
      await file.exists() || await settingsFile.exists();

  /// Throws, touching nothing, for a file from a newer app version
  /// ([NewerLibraryException]) or one that can't be kept aside: saving
  /// over it would lose it.
  Future<Library> load() async {
    // Whatever is on disk now wasn't necessarily written by this store.
    _onDiskLibrary = null;
    _onDiskSettings = null;
    await _tidyCorrupt();
    final library = await _read(file);
    if (library != null && library['version'] == 1) {
      // One combined file, from before the split: keep the original until
      // the migrated library has been saved.
      if (!await backupFile.exists()) await file.copy(backupFile.path);
      _backupPending = true;
      final parsed = _parse(library);
      if (parsed != null) return parsed;
      await _setAside(file);
      return Library.empty;
    }
    final settings = await _read(settingsFile);
    const base = <String, Object?>{
      'version': latestVersion,
      'songs': [],
      'setlists': [],
    };
    // The library file's version is the format's; the settings carry
    // nothing else that's the library's.
    final settingsPart = {
      for (final MapEntry(:key, :value) in (settings ?? const {}).entries)
        if (!libraryKeys.contains(key) && key != 'version') key: value,
    };
    final both = _parse({...base, ...settingsPart, ...?library});
    if (both != null) return both;
    // One of them is broken: keep it aside and the other one.
    final songsOnly = library == null ? null : _parse({...base, ...library});
    if (songsOnly != null) {
      await _setAside(settingsFile);
      return songsOnly;
    }
    await _setAside(file);
    final settingsOnly = _parse({...base, ...settingsPart});
    if (settingsOnly != null) return settingsOnly;
    await _setAside(settingsFile);
    return Library.empty;
  }

  /// The file's JSON, or null when it's missing or unreadable (then it's
  /// moved aside). A newer version throws.
  Future<Map<String, Object?>?> _read(File f) async {
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, Object?>;
      final version = json['version'];
      if (version is int && version > Library.version) {
        throw NewerLibraryException(version);
      }
      return json;
    } on NewerLibraryException {
      rethrow;
    } catch (_) {
      await _setAside(f);
      return null;
    }
  }

  static Library? _parse(Map<String, Object?> json) {
    try {
      return Library.fromJson(json);
    } on NewerLibraryException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<void> _setAside(File f) async {
    if (!await f.exists()) return;
    await corruptDir.create(recursive: true);
    final name = f.uri.pathSegments.last;
    final aside = File(
      '${corruptDir.path}/$name.corrupt-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await f.rename(aside.path);
    } on FileSystemException {
      await f.copy(aside.path);
    }
    // Newest = set aside most recently (a rename keeps the old time).
    await aside.setLastModified(DateTime.now());
    await _tidyCorrupt();
  }

  /// Moves older `*.corrupt-*` files from beside the library into
  /// [corruptDir], then keeps only the newest [keepCorrupt].
  Future<void> _tidyCorrupt() async {
    final dir = file.parent;
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.contains('.corrupt-')) {
        await corruptDir.create(recursive: true);
        final name = entity.uri.pathSegments.last;
        await entity.rename('${corruptDir.path}/$name');
      }
    }
    if (!await corruptDir.exists()) return;
    final files = (await corruptDir.list().toList()).whereType<File>().toList();
    if (files.length <= keepCorrupt) return;
    final stamped = [for (final f in files) (f, await f.lastModified())]
      ..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (f, _) in stamped.skip(keepCorrupt)) {
      await f.delete();
    }
  }

  Future<void> save(Library library) {
    final write = _writes.then((_) => _write(library));
    // A failed write must not block the ones queued after it.
    _writes = write.catchError((_) {});
    return write;
  }

  Future<void> _write(Library library) async {
    final settings = jsonEncode(library.settingsJson());
    final songs = jsonEncode(library.libraryJson());
    if (settings != _onDiskSettings) {
      await _atomic(settingsFile, settings);
      _onDiskSettings = settings;
    }
    if (songs != _onDiskLibrary) {
      await _atomic(file, songs);
      _onDiskLibrary = songs;
    }
    if (_backupPending) {
      _backupPending = false;
      if (await backupFile.exists()) await backupFile.delete();
    }
  }

  static Future<void> _atomic(File target, String content) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(content, flush: true);
    await temp.rename(target.path);
  }
}
