import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/share_text.dart';

MetronomePattern _meter(int beats, [int unit = 4]) => MetronomePattern.simple(
  beatsPerBar: beats,
  stepsPerBeat: 1,
  beatUnit: unit,
);

Song _plain(String name, int bpm, [MetronomePattern? p]) => Song(
  id: name,
  name: name,
  bpm: bpm,
  pattern: p ?? const MetronomePattern.standard(),
);

Song _parts(String name, List<(int, int, MetronomePattern)> parts) =>
    Song.withParts(
      id: name,
      name: name,
      parts: [
        for (final (i, (from, to, p)) in parts.indexed)
          SongPart(
            id: 'p$i',
            name: 'Part $i',
            bars: 4,
            tempoStart: from,
            tempoEnd: to,
            pattern: p,
          ),
      ],
    );

/// ui-spec.md "Set ⌄" › "Share".
void main() {
  const four = MetronomePattern.standard();

  test('a mixed set: plain songs, songs with parts, the count and the '
      'last line', () {
    final songs = [
      _plain('Midnight Engine', 148),
      _plain('Odd One', 172, _meter(7, 8)),
      _parts('Glass Harbor', [
        (120, 120, four),
        (128, 128, _meter(2)),
        (120, 140, four), // Gradual: its end counts
      ]),
      _parts('Long Road', [
        (98, 98, four),
        (110, 110, four),
        (120, 120, four),
        (140, 140, four),
        (130, 130, four),
      ]),
    ];
    expect(
      setlistShareText(
        Setlist(
          id: 's',
          name: 'Fri · The Blue Room',
          songIds: [for (final s in songs) s.id],
        ),
        songs,
      ),
      'Fri · The Blue Room (4 songs)\n'
      '1. Midnight Engine · 148\n'
      '2. Odd One · 172 · 7/8\n'
      '3. Glass Harbor · 120, 128, 140 · 4/4, 2/4\n'
      '4. Long Road · 98–140 (5 tempos)\n'
      '\n'
      'Shared from Metra',
    );
  });

  test('parts: one tempo reads like a plain song; all 4/4 says nothing; '
      'a signature not 4/4 lists them; 4 or more are counted', () {
    expect(
      songShareLine(_parts('A', [(100, 100, four), (100, 100, four)])),
      'A · 100',
    );
    expect(
      songShareLine(_parts('B', [(100, 100, _meter(3)), (90, 90, _meter(3))])),
      'B · 100, 90 · 3/4',
    );
    expect(
      songShareLine(
        _parts('C', [
          (100, 100, four),
          (100, 100, _meter(3)),
          (100, 100, _meter(5)),
          (100, 100, _meter(7, 8)),
        ]),
      ),
      'C · 100 · 4 time signatures',
    );
  });

  test('one song: "(1 song)"', () {
    expect(
      setlistShareText(const Setlist(id: 's', name: 'Solo', songIds: ['x']), [
        _plain('x', 90),
      ]).split('\n').first,
      'Solo (1 song)',
    );
  });
}
