import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fonts are bundled assets (ui-spec.md: never fetched at runtime).
/// This catches a missing or broken file before it shows up as a fallback
/// font on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (family, files) in [
    ('Saira', ['Saira-Medium.ttf', 'Saira-SemiBold.ttf']),
    (
      'SairaExtraCondensed',
      ['SairaExtraCondensed-SemiBold.ttf', 'SairaExtraCondensed-Bold.ttf'],
    ),
  ]) {
    test('$family loads from the bundle', () async {
      final loader = FontLoader(family);
      for (final file in files) {
        loader.addFont(rootBundle.load('assets/fonts/$file'));
      }
      await loader.load();
    });
  }
}
