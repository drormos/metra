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

  /// An unreadable file is renamed aside (kept for recovery) and an empty
  /// library is returned, so the app still starts.
  Future<Library> load() async {
    if (!await file.exists()) return Library.empty;
    try {
      final json = jsonDecode(await file.readAsString());
      return Library.fromJson(json as Map<String, Object?>);
    } catch (_) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await file.rename('${file.path}.corrupt-$stamp');
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
