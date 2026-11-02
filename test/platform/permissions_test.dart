import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PRIVACY.md promises no network access and one permission prompt, the
/// microphone for the tuner; the
/// app's own manifest must not ask (tool/release.sh also checks the merged
/// release manifest, which includes what dependencies add).
void main() {
  test('the manifest asks for no internet and no notification permission', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('android.permission.INTERNET')));
    expect(manifest, isNot(contains('android.permission.POST_NOTIFICATIONS')));
  });

  test('the microphone is the only permission to approve', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final asked = RegExp(r'uses-permission android:name="([^"]+)"')
        .allMatches(manifest)
        .map((m) => m[1])
        .toSet();
    expect(asked, {
      'android.permission.WAKE_LOCK',
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      'android.permission.RECORD_AUDIO',
    });
  });
}
