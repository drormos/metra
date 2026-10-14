import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ui-spec.md: all colors live in the theme file, none in widgets.
void main() {
  test('only theme.dart defines colors', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            !file.path.endsWith('theme.dart'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (RegExp(r'Color\(0x|\bColors\.[a-z]').hasMatch(line))
              '${file.path}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });
}
