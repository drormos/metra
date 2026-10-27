import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';

/// Writes store/demo/ (the store screenshots' library):
/// `flutter test tool/store/gen_demo_test.dart`.
void main() {
  test('demo library', () {
    final edited = DateTime(2026, 10, 20, 12);
    var n = 0;
    Song song(
      String name,
      int bpm,
      MetronomePattern p, {
      OnStart onStart = OnStart.off,
    }) => Song(
      id: 'demo-${n++}',
      name: name,
      bpm: bpm,
      pattern: p,
      onStart: onStart,
      editedAt: edited,
    );
    MetronomePattern simple(int beats, int steps, [int unit = 4]) =>
        MetronomePattern.simple(
          beatsPerBar: beats,
          stepsPerBeat: steps,
          beatUnit: unit,
        );
    const a = StepLevel.accent, r = StepLevel.normal;

    final midnight = song('Midnight Engine', 148, simple(4, 2));
    final copper = song('Copper Sky', 98, simple(4, 2));
    final staticBloom = song('Static Bloom', 132, simple(4, 2));
    final northbound = song('Northbound', 120, simple(4, 2));
    final paper = song('Paper Crowns', 92, simple(4, 3));
    final lanterns = song(
      'Seven Lanterns',
      140,
      MetronomePattern.fromBeats(
        [a, r, a, r, a, r, r],
        stepsPerBeat: 2,
        beatUnit: 8,
      ).withPolyrhythm(3),
    );
    final slowBurn = song(
      'Slow Burn',
      68,
      MetronomePattern.fromBeats(
        [a, r, r, a, r, r, a, r, r, a, r, r],
        stepsPerBeat: 1,
        beatUnit: 8,
      ),
    );
    final ghost = song(
      'Ghost Lights',
      116,
      MetronomePattern.fromBeats(
        [a, r, r, a, r, r],
        stepsPerBeat: 1,
        beatUnit: 8,
      ),
    );
    final hollow = song(
      'Hollow Pines',
      84,
      MetronomePattern.fromBeats(
        [a, r, r, a, r, r],
        stepsPerBeat: 1,
        beatUnit: 8,
      ),
    );
    final redLine = song('Red Line', 160, simple(4, 2));
    final lastDance = song('Last Dance', 104, simple(3, 1));
    final breakdown = song('Breakdown', 174, simple(4, 4));
    final ladder = song(
      'Paradiddle Ladder',
      80,
      simple(4, 4),
      onStart: const OnStart(
        countInOn: true,
        speedUp: true,
        changeBy: 5,
        every: 4,
        upTo: 120,
      ),
    );
    final strokes = song(
      'Single Strokes',
      100,
      simple(4, 4),
      onStart: const OnStart(stopOn: true, stopTime: Duration(minutes: 5)),
    );
    // A song with parts for the store shots (heads-up, parts page, stage
    // mode): a 1-bar 2/4 break and a Gradual chorus.
    SongPart part(String name, int bars, int from, [int? to, int beats = 4]) =>
        SongPart(
          id: 'demo-part-${n++}',
          name: name,
          bars: bars,
          tempoStart: from,
          tempoEnd: to ?? from,
          pattern: simple(beats, 2),
        );
    final harbor = Song.withParts(
      id: 'demo-${n++}',
      name: 'Glass Harbor',
      parts: [
        part('Intro', 4, 120),
        part('Verse', 8, 120),
        part('Break', 1, 128, null, 2),
        part('Chorus', 8, 128, 140),
        part('Bridge', 4, 132),
        part('Outro', 4, 120),
      ],
      end: SongEnd.stop,
      onStart: const OnStart(countInOn: true),
      editedAt: edited,
    );
    final threeFour = song(
      'Three Over Four',
      90,
      simple(4, 1).withPolyrhythm(3),
    );

    final gig = [
      midnight,
      harbor,
      copper,
      staticBloom,
      northbound,
      paper,
      lanterns,
      slowBurn,
      ghost,
      hollow,
      redLine,
      lastDance,
    ];
    final library = Library(
      songs: [...gig, breakdown, ladder, strokes, threeFour],
      setlists: [
        Setlist(
          id: 'set-blue-room',
          name: 'Fri · The Blue Room',
          songIds: [for (final s in gig) s.id],
          playedAt: DateTime(2026, 10, 23, 20),
        ),
        Setlist(
          id: 'set-wedding',
          name: 'Sat · Wedding',
          songIds: [
            for (final s in [
              lastDance,
              paper,
              northbound,
              ghost,
              copper,
              midnight,
              redLine,
            ])
              s.id,
          ],
          playedAt: DateTime(2026, 10, 22, 18),
        ),
        Setlist(
          id: 'set-practice',
          name: 'Daily practice',
          songIds: [
            for (final s in [ladder, strokes, threeFour]) s.id,
          ],
          playedAt: DateTime(2026, 10, 21, 9),
        ),
      ],
      lastBpm: 120,
      lastPattern: const MetronomePattern.standard(),
      visualOffset: Duration.zero,
      themeMode: ThemeMode.dark,
      tipsSeen: const {
        'edit-first-load',
        'edit-new-song',
        'edit-first-change',
        'set-swipe-hint',
        'songs-swipe-hint',
        'sets-swipe-hint',
        'examples-added',
        'whats-new-dot:1.5.2',
        'whats-new:1.5.2',
        'whats-new-dot:1.6.0',
        'whats-new:1.6.0',
        'stage-dnd-tip',
      },
    ).repaired();
    const enc = JsonEncoder.withIndent('  ');
    File('store/demo/library.json')
        .writeAsStringSync('${enc.convert(library.libraryJson())}\n');
    File('store/demo/settings.json')
        .writeAsStringSync('${enc.convert(library.settingsJson())}\n');
  });
}
