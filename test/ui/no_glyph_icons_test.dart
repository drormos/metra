import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ui-spec.md "Song parts" fixes: no text glyphs for icons (▶ ■ ✓ ∞ ⌄ ›
/// …): Android draws some as colored emoji. Every icon is a vector icon.
void main() {
  test('no symbol glyphs in what the screens show', () {
    // Arrows, technical symbols, shapes, dingbats, ∞, ‹ ›, emoji.
    final glyph = RegExp(
      '[←-⇿⌀-⏿■-◿☀-➿∞'
      '‹›⬀-⯿️]',
    );
    final offenders = [
      for (final file in Directory('lib/src/ui').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final (i, line) in file.readAsLinesSync().indexed)
            if (!line.trim().startsWith('//') &&
                glyph.hasMatch(line) &&
                // The run line turns the speed-up arrow into an icon.
                !line.contains("label.startsWith('"))
              '${file.path}:${i + 1}: ${line.trim()}',
    ];
    expect(offenders, isEmpty);
  });
}
