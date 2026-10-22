import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/model/whats_new.dart';
import 'package:metra/src/storage/library_store.dart';

void main() {
  late Directory dir;
  late LibraryController library;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('metra_whats_new');
    library = await LibraryController.load(
      LibraryStore(File('${dir.path}/library.json')),
    );
  });

  tearDown(() async {
    WhatsNew.releases = const [];
    await library.flush(); // don't delete the folder under a pending save
    dir.deleteSync(recursive: true);
  });

  const notes = '''
# What's new

## 1.4.0 · Oct 2026
- One
- Two

## 1.3.0 · Sep 2026
- Old
''';

  test('parses versions newest first, with their lines', () {
    final releases = WhatsNew.parse(notes);
    expect(releases.map((r) => r.version), ['1.4.0', '1.3.0']);
    expect(releases.first.heading, '1.4.0 · Oct 2026');
    expect(releases.first.lines, ['One', 'Two']);
  });

  test('after an update: dot and block; opening Settings clears the dot; '
      '"Got it" the block; the next version shows again', () {
    WhatsNew.releases = WhatsNew.parse(notes);
    expect(WhatsNew.showDot(library), isTrue);
    expect(WhatsNew.showBlock(library), isTrue);
    WhatsNew.settingsOpened(library);
    expect(WhatsNew.showDot(library), isFalse);
    expect(WhatsNew.showBlock(library), isTrue, reason: 'until Got it');
    WhatsNew.markSeen(library);
    expect(WhatsNew.showBlock(library), isFalse);
    WhatsNew.releases = WhatsNew.parse('## 1.5.0 · Nov 2026\n- New\n$notes');
    expect(WhatsNew.showDot(library), isTrue);
    expect(WhatsNew.showBlock(library), isTrue);
  });

  test('a fresh install counts as seen (no dot, no block)', () {
    WhatsNew.releases = WhatsNew.parse(notes);
    WhatsNew.markSeen(library);
    expect(WhatsNew.showDot(library), isFalse);
    expect(WhatsNew.showBlock(library), isFalse);
  });

  test('no notes: nothing shows', () {
    expect(WhatsNew.showDot(library), isFalse);
    expect(WhatsNew.showBlock(library), isFalse);
  });

  test('the asset\'s top version is the app version in pubspec.yaml', () {
    final top = WhatsNew.parse(File(WhatsNew.asset).readAsStringSync()).first;
    final version = RegExp(
      r'^version: (\S+)\+',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(top.version, version);
    expect(top.lines, isNotEmpty);
  });
}
