import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';

void main() {
  final waltz = MetronomePattern(
    beatsPerBar: 3,
    stepsPerBeat: 2,
    steps: const [
      StepLevel.accent,
      StepLevel.silent,
      StepLevel.normal,
      StepLevel.silent,
      StepLevel.normal,
      StepLevel.silent,
    ],
  );

  /// Through a real JSON string, as on disk.
  Library roundTrip(Library library) =>
      Library.fromJson(jsonDecode(jsonEncode(library.toJson())));

  test('pattern survives JSON', () {
    expect(MetronomePattern.fromJson(waltz.toJson()), waltz);
  });

  test('library survives JSON', () {
    final library = Library(
      songs: [
        Song(id: 'a', name: 'Waltz', bpm: 90, pattern: waltz),
        const Song(
          id: 'b',
          name: 'Rock',
          bpm: 128,
          pattern: MetronomePattern.standard(),
        ),
      ],
      setlists: const [
        Setlist(id: 's', name: 'Friday gig', songIds: ['b', 'a']),
      ],
      lastBpm: 97,
      lastPattern: waltz,
      visualOffset: const Duration(milliseconds: 20),
    );
    final copy = roundTrip(library);
    expect(copy.songs.map((s) => [s.id, s.name, s.bpm, s.pattern]), [
      ['a', 'Waltz', 90, waltz],
      ['b', 'Rock', 128, const MetronomePattern.standard()],
    ]);
    expect(copy.setlists.single.name, 'Friday gig');
    expect(copy.setlists.single.songIds, ['b', 'a']);
    expect(copy.lastBpm, 97);
    expect(copy.lastPattern, waltz);
    expect(copy.visualOffset, const Duration(milliseconds: 20));
  });

  test('empty library has app defaults', () {
    const library = Library.empty;
    expect(library.songs, isEmpty);
    expect(library.setlists, isEmpty);
    expect(library.lastBpm, 120);
    expect(library.lastPattern, const MetronomePattern.standard());
    expect(library.visualOffset, Duration.zero);
    expect(roundTrip(library).lastBpm, 120);
  });

  test('invalid data is rejected', () {
    expect(() => Library.fromJson({'version': 1}), throwsA(anything));
    expect(
      () => MetronomePattern.fromJson({
        'beatsPerBar': 1,
        'stepsPerBeat': 1,
        'steps': ['loud'],
      }),
      throwsA(anything),
    );
  });

  test('newer file versions are rejected rather than misread', () {
    final json = Library.empty.toJson()..['version'] = 99;
    expect(() => Library.fromJson(json), throwsFormatException);
  });
}
