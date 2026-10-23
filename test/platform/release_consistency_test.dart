import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/whats_new.dart';

/// A version name can't ship with stale notes: the pubspec's version, the
/// top What's new entry (the in-app block and the Play notes) and the top
/// released CHANGELOG section agree (see the release skill).
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final version = RegExp(
    r'^version: (\d+\.\d+\.\d+)\+(\d+)$',
    multiLine: true,
  ).firstMatch(pubspec)!;

  test('the top What\'s new entry is the current version', () {
    final top = WhatsNew.parse(
      File(WhatsNew.asset).readAsStringSync(),
    ).first;
    expect(top.version, version[1], reason: 'assets/whats_new.md');
    expect(top.lines, isNotEmpty);
  });

  test('the top released CHANGELOG section is the current version', () {
    final released = RegExp(
      r'^## \[(\d+\.\d+\.\d+)\] - \d{4}-\d{2}-\d{2}$',
      multiLine: true,
    ).firstMatch(File('CHANGELOG.md').readAsStringSync());
    expect(released?[1], version[1], reason: 'CHANGELOG.md');
  });
}
