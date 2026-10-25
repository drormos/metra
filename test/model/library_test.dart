import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';

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
        Song(
          id: 'a',
          name: 'Waltz',
          bpm: 90,
          pattern: waltz,
          onStart: OnStart(
            countInOn: true,
            countInBars: 2,
            speedUp: true,
            upTo: 160,
            stopOn: true,
          ),
        ),
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
      lastOnStart: const OnStart(countInOn: true, countInBars: 1),
      visualOffset: const Duration(milliseconds: 20),
    );
    final copy = roundTrip(library);
    expect(copy.songs.map((s) => s.onStart), [
      const OnStart(
        countInOn: true,
        countInBars: 2,
        speedUp: true,
        upTo: 160,
        stopOn: true,
      ),
      OnStart.off,
    ]);
    expect(copy.lastOnStart, const OnStart(countInOn: true, countInBars: 1));
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

  test('a bad entry is skipped; the rest of the library loads', () {
    final json = jsonDecode(
      jsonEncode(
        Library.empty
            .copyWith(
              songs: [
                Song(id: 'a', name: 'Good', bpm: 90, pattern: waltz),
                Song(id: 'b', name: 'Bad', bpm: 100, pattern: waltz),
              ],
              setlists: [
                const Setlist(id: 's', name: 'Good', songIds: ['a', 'b']),
                const Setlist(id: 't', name: 'Bad', songIds: []),
              ],
            )
            .toJson(),
      ),
    );
    (json['songs'] as List)[1]['parts'] = [
      {'tempoStart': 'fast'},
    ];
    (json['setlists'] as List)[1]['songIds'] = null;
    json['lastPattern'] = {'steps': 'garbage'};
    json['visualOffsetMs'] = null;
    final library = Library.fromJson(json);
    expect([for (final s in library.songs) s.name], ['Good']);
    expect([for (final s in library.setlists) s.name], ['Good']);
    expect(library.lastPattern, Library.empty.lastPattern);
    expect(library.visualOffset, Duration.zero);
  });

  test('newer file versions are rejected rather than misread', () {
    final json = Library.empty.toJson()..['version'] = 99;
    expect(() => Library.fromJson(json), throwsA(isA<NewerLibraryException>()));
  });

  test('click sound survives JSON; missing or unknown falls back', () {
    final cowbell = Library.empty.copyWith(clickSound: ClickSound.cowbell);
    expect(roundTrip(cowbell).clickSound, ClickSound.cowbell);
    final old = Library.empty.toJson()..remove('clickSound');
    expect(Library.fromJson(old).clickSound, ClickSound.woodblock);
    final odd = Library.empty.toJson()..['clickSound'] = 'kazoo';
    expect(Library.fromJson(odd).clickSound, ClickSound.woodblock);
    final classic = Library.empty.toJson()..['clickSound'] = 'classic';
    expect(
      Library.fromJson(classic).clickSound,
      ClickSound.woodblock,
      reason: 'Classic was removed',
    );
  });

  test('theme mode survives JSON; missing falls back to system', () {
    final dark = Library.empty.copyWith(themeMode: ThemeMode.dark);
    expect(roundTrip(dark).themeMode, ThemeMode.dark);
    final old = Library.empty.toJson()..remove('themeMode');
    expect(Library.fromJson(old).themeMode, ThemeMode.system);
  });

  test('volumes survive JSON; missing means defaults; odd values clamp', () {
    expect(Library.empty.volumes, ClickVolumes.defaults);
    const quiet = ClickVolumes(accent: 0.5, beat: 0.3, subdivision: 0);
    expect(roundTrip(Library.empty.copyWith(volumes: quiet)).volumes, quiet);
    final old = Library.empty.toJson()..remove('volumes');
    expect(Library.fromJson(old).volumes, ClickVolumes.defaults);
    expect(
      ClickVolumes.fromJson({'accent': 3, 'beat': -1}),
      const ClickVolumes(accent: 1, beat: 0, subdivision: 0.45),
    );
    expect(ClickVolumes.defaults.polyrhythm, 0.7);
    const loud = ClickVolumes(polyrhythm: 0.9);
    expect(roundTrip(Library.empty.copyWith(volumes: loud)).volumes, loud);
  });

  test('"Vibrate on touch" survives JSON; missing means on', () {
    expect(Library.empty.vibrate, isTrue);
    final off = Library.empty.copyWith(vibrate: false);
    expect(roundTrip(off).vibrate, isFalse);
    expect(
      off.withSession(setlistId: null, songId: null, position: -1).vibrate,
      isFalse,
    );
    final old = Library.empty.toJson()..remove('vibrate');
    expect(Library.fromJson(old).vibrate, isTrue);
  });

  test('session (setlist, song, position) survives JSON; missing is Free '
      'play', () {
    final session = Library.empty
        .copyWith(
          songs: [
            Song(id: 'a', name: 'A', bpm: 90, pattern: waltz),
            Song(id: 'b', name: 'B', bpm: 90, pattern: waltz),
          ],
          setlists: [
            const Setlist(id: 's', name: 'S', songIds: ['b', 'b', 'b', 'a']),
          ],
        )
        .withSession(setlistId: 's', songId: 'a', position: 3);
    final copy = roundTrip(session);
    expect(copy.activeSetlistId, 's');
    expect(copy.currentSongId, 'a');
    expect(copy.currentPosition, 3);
    expect(roundTrip(copy.copyWith(lastBpm: 99)).activeSetlistId, 's');

    final old = Library.empty.toJson()
      ..remove('activeSetlistId')
      ..remove('currentSongId')
      ..remove('currentPosition');
    final fromOld = Library.fromJson(old);
    expect(fromOld.activeSetlistId, isNull);
    expect(fromOld.currentPosition, -1);
  });

  test('a song keeps when it was last played; older files: null', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final song = Song(
      id: 'a',
      name: 'A',
      bpm: 90,
      pattern: waltz,
      playedAt: at,
    );
    expect(Song.fromJson(song.toJson()).playedAt, at);
    expect(Song.fromJson(song.toJson()..remove('playedAt')).playedAt, isNull);
  });

  test('a song without editedAt (older file) loads with null', () {
    final json = const Song(
      id: 'x',
      name: 'Old',
      bpm: 90,
      pattern: MetronomePattern.standard(),
    ).toJson()..remove('editedAt');
    expect(Song.fromJson(json).editedAt, isNull);
  });
}
