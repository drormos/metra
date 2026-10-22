import 'dart:convert';
import 'dart:io';

import '../model/library.dart';

/// Saves the [Library] as one JSON file.
///
/// Writes go to a temp file that is then renamed over the real one, so a
/// crash mid-write never leaves a half-written library. Saves run one at a
/// time in call order.
class LibraryStore {
  LibraryStore(this.file);

  final File file;
  Future<void> _writes = Future.value();

  /// An unreadable file is moved aside (kept for recovery) and an empty
  /// library is returned, so the app still starts. Throws, touching
  /// nothing, for a file from a newer app version
  /// ([NewerLibraryException]) or one that can't be kept aside: saving
  /// over it would lose it.
  /// Whether a library was ever saved here (false on a fresh install).
  Future<bool> exists() => file.exists();

  Future<Library> load() async {
    if (!await file.exists()) return Library.empty;
    try {
      final json = jsonDecode(await file.readAsString());
      return Library.fromJson(json as Map<String, Object?>);
    } on NewerLibraryException {
      rethrow;
    } catch (_) {
      final aside =
          '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      try {
        await file.rename(aside);
      } on FileSystemException {
        await file.copy(aside);
      }
      return Library.empty;
    }
  }

  Future<void> save(Library library) {
    final write = _writes.then((_) => _write(library));
    // A failed write must not block the ones queued after it.
    _writes = write.catchError((_) {});
    return write;
  }

  Future<void> _write(Library library) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(library.toJson()), flush: true);
    await temp.rename(file.path);
  }
}
