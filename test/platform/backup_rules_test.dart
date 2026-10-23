import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/storage/library_store.dart';

/// Android Auto Backup must carry the library and settings, and nothing
/// the store writes on the side (temp files, the version-1 copy, corrupt/).
void main() {
  const res = 'android/app/src/main/res/xml';
  final store = LibraryStore(File('/data/files/library.json'));
  String name(File f) => f.uri.pathSegments.last;

  for (final rules in ['backup_rules.xml', 'data_extraction_rules.xml']) {
    test('$rules includes exactly the store\'s two files', () {
      final xml = File('$res/$rules').readAsStringSync();
      final included = RegExp(r'<include domain="file" path="([^"]+)"')
          .allMatches(xml)
          .map((m) => m[1])
          .toSet();
      expect(included, {name(store.file), name(store.settingsFile)});
      expect(xml, isNot(contains('<exclude')), reason: 'an include list');
    });
  }

  test('the manifest uses both rule files', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });
}
