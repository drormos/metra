import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PRIVACY.md promises no network access and no permission prompts; the
/// app's own manifest must not ask (tool/release.sh also checks the merged
/// release manifest, which includes what dependencies add).
void main() {
  test('the manifest asks for no internet and no notification permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
    expect(manifest, isNot(contains('android.permission.POST_NOTIFICATIONS')));
  });
}
