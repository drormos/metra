import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';

import 'sample_library.dart';

/// The saved format can't change by accident: [sampleLibrary] serialized
/// today must match the snapshot of the current version. A difference
/// means the format changed: bump the version with a migration and a new
/// snapshot (.agents/skills/data-format-change/SKILL.md).
void main() {
  const howTo =
      'The saved data format changed. Follow the data-format-change skill '
      '(.agents/skills/data-format-change/SKILL.md): add a migration step, '
      'bump Library.version (latestVersion), and add '
      'test/fixtures/library_v<N>/ generated from sampleLibrary.';
  final dir = Directory('test/fixtures/library_v${Library.version}');

  // `WRITE_SNAPSHOT=1 flutter test test/storage/schema_guard_test.dart`
  // writes the snapshot for the current version (after bumping it). Never
  // overwrites an existing one: an old format's snapshot stays as it is.
  if (Platform.environment['WRITE_SNAPSHOT'] == '1') {
    test('write the snapshot', () {
      expect(dir.existsSync(), isFalse, reason: '${dir.path} exists');
      dir.createSync(recursive: true);
      const encoder = JsonEncoder.withIndent('  ');
      File(
        '${dir.path}/library.json',
      ).writeAsStringSync('${encoder.convert(sampleLibrary.libraryJson())}\n');
      File(
        '${dir.path}/settings.json',
      ).writeAsStringSync('${encoder.convert(sampleLibrary.settingsJson())}\n');
    });
    return;
  }

  test('a snapshot exists for the current format', () {
    expect(dir.existsSync(), isTrue, reason: howTo);
  });

  for (final (file, json) in [
    ('library.json', sampleLibrary.libraryJson()),
    ('settings.json', sampleLibrary.settingsJson()),
  ]) {
    test('$file matches the version ${Library.version} snapshot', () {
      final snapshot = File('${dir.path}/$file');
      expect(snapshot.existsSync(), isTrue, reason: howTo);
      expect(json, jsonDecode(snapshot.readAsStringSync()), reason: howTo);
    });
  }

  test('the sample round-trips (so the snapshot is complete)', () {
    final copy = Library.fromJson({
      ...sampleLibrary.settingsJson(),
      ...sampleLibrary.libraryJson(),
    });
    expect(copy.toJson(), sampleLibrary.toJson());
  });
}
