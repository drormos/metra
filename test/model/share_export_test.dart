import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/model/share_export.dart';

const _four = MetronomePattern.standard();

/// Every music feature: a Gradual part, 7/8 in eighths with an accent, a
/// muted beat and a toggled cell, a polyrhythm with a pulse accented,
/// several parts, "Loop song"; and When I press Start, which isn't sent.
final _harbor = Song.withParts(
  id: 'harbor',
  name: 'Glass Harbor',
  end: SongEnd.loopSong,
  onStart: const OnStart(countInOn: true, practiceOn: true, stopOn: true),
  parts: [
    const SongPart.steady(
      id: 'a',
      name: 'Intro',
      bars: 4,
      bpm: 120,
      pattern: _four,
    ),
    SongPart(
      id: 'b',
      name: 'Break',
      bars: 1,
      tempoStart: 128,
      tempoEnd: 128,
      pattern: MetronomePattern.simple(beatsPerBar: 2, stepsPerBeat: 1),
    ),
    SongPart(
      id: 'c',
      name: 'Chorus',
      bars: 8,
      tempoStart: 128,
      tempoEnd: 140,
      pattern:
          MetronomePattern.simple(beatsPerBar: 7, stepsPerBeat: 2, beatUnit: 8)
              .cycleBeat(2)
              .cycleBeat(3)
              .cycleBeat(3)
              .toggleCell(4, 1)
              .withPolyrhythm(3)
              .cyclePulse(1),
    ),
  ],
);

Song _plain(String id, String name, int bpm, [OnStart on = OnStart.off]) =>
    Song(id: id, name: name, bpm: bpm, pattern: _four, onStart: on);

Library _library(List<Song> songs, [List<Setlist> sets = const []]) => Library(
  songs: songs,
  setlists: sets,
  lastBpm: 120,
  lastPattern: _four,
  visualOffset: Duration.zero,
);

/// The export of [payload] as a data line, for shapes the app doesn't make.
String _line(Object payload) =>
    'metra1:${base64Url.encode(gzip.encode(utf8.encode(jsonEncode(payload))))}';

/// ui-spec.md "Sharing sets and songs".
void main() {
  var n = 0;
  String newId() => 'new-${n++}';
  setUp(() => n = 0);

  test('a song round-trips every music feature; When I press Start isn\'t '
      'sent (it arrives off); the message reads: line, help, data', () {
    final text = exportSongText(_harbor);
    final lines = text.split('\n');
    expect(lines.first, 'Glass Harbor · 120, 128, 140 · 4/4, 2/4, 7/8');
    expect(lines[2], importHelp);
    expect(lines.last, startsWith('metra1:'));
    expect(lines.last, matches(RegExp(r'^metra1:[A-Za-z0-9_-]+$')));
    final read = parseShared(text)!;
    expect(read.isSet, isFalse);
    final song = read.songs.single;
    expect(song.name, 'Glass Harbor');
    expect(musicKey(song), musicKey(_harbor));
    expect(song.end, SongEnd.loopSong);
    expect(
      [for (final p in song.parts) p.pattern],
      [for (final p in _harbor.parts) p.pattern],
    );
    expect(song.parts[2].tempoEnd, 140);
    expect(song.onStart, OnStart.off);
    expect(text, isNot(contains('countIn')));
  });

  test('a set keeps its order (a song twice too) and its name', () {
    final rock = _plain('rock', 'Rock', 100);
    final set = Setlist(
      id: 's',
      name: 'Fri · The Blue Room',
      songIds: const [],
    );
    final text = exportSetText(set, [_harbor, rock, _harbor]);
    expect(text.split('\n').first, 'Fri · The Blue Room (3 songs)');
    expect(text, isNot(contains('Shared from Metra')));
    final read = parseShared(text)!;
    expect(read.setName, 'Fri · The Blue Room');
    expect([for (final s in read.songs) s.name], ['Glass Harbor', 'Rock']);
    expect(read.order, [0, 1, 0]);
  });

  test('found anywhere in pasted text; nothing Metra-shaped is null', () {
    final data = exportSongText(_harbor).split('\n').last;
    expect(parseShared('fwd: look at this\n$data\nthanks!'), isNotNull);
    expect(parseShared('just a chat message'), isNull);
    expect(parseShared('metra1:not-really-data'), isNull);
    expect(parseShared(_line({'v': 1})), isNull);
  });

  test('a newer payload: unknown fields ignored, an unreadable song '
      'skipped and counted, the rest added', () {
    final good = jsonDecode(
      utf8.decode(
        gzip.decode(
          base64Url.decode(
            base64Url.normalize(
              exportSongText(_harbor).split('\n').last.substring(7),
            ),
          ),
        ),
      ),
    ) as Map<String, Object?>;
    final song = (good['songs'] as List).single as Map<String, Object?>;
    final read = parseShared(
      _line({
        'v': 7,
        'future': {'anything': true},
        'set': {
          'name': 'Tour',
          'order': [0, 1, 0],
          'color': 'red',
        },
        'songs': [
          {...song, 'mood': 'happy'},
          {'name': 'From the future', 'sections': []},
        ],
      }),
    )!;
    expect(read.skipped, 1);
    expect([for (final s in read.songs) s.name], ['Glass Harbor']);
    expect(read.order, [0, 0], reason: 'the skipped song leaves the order');
    expect(musicKey(read.songs.single), musicKey(_harbor));
  });

  test('importing the same set twice: the second time nothing is added, '
      'the set you have opens', () {
    final rock = _plain('rock', 'Rock', 100);
    final text = exportSetText(
      const Setlist(id: 's', name: 'Fri', songIds: []),
      [_harbor, rock],
    );
    var library = _library(const []);
    final first = ImportPlan.of(library, parseShared(text)!, newId);
    expect(first.newSongs, hasLength(2));
    expect(first.existing, 0);
    expect(first.newSet!.name, 'Fri');
    library = _library(first.newSongs, [first.newSet!]);
    final again = ImportPlan.of(library, parseShared(text)!, newId);
    expect(again.newSongs, isEmpty);
    expect(again.existing, 2);
    expect(again.newSet, isNull);
    expect(again.sameSet!.id, first.newSet!.id);
  });

  test('a second set sharing songs with the first points at them: no '
      'duplicates; your own When I press Start stays', () {
    final mine = Song.withParts(
      id: 'mine',
      name: 'Glass Harbor',
      parts: _harbor.parts,
      end: _harbor.end,
      onStart: const OnStart(countInOn: true),
    );
    final rock = _plain('rock', 'Rock', 100);
    final library = _library([mine, rock]);
    final text = exportSetText(
      const Setlist(id: 's', name: 'Sat', songIds: []),
      [_harbor, rock, _plain('x', 'New one', 90)],
    );
    final plan = ImportPlan.of(library, parseShared(text)!, newId);
    expect(plan.existing, 2);
    expect([for (final s in plan.newSongs) s.name], ['New one']);
    expect(plan.newSet!.songIds, ['mine', 'rock', plan.newSongs.single.id]);
    expect(plan.newSongs.single.onStart, OnStart.off);
  });

  test('same name, different music: "(shared)", then "(shared 2)"; yours '
      'never changes; an earlier "(shared)" copy with the same music is '
      'used; a different same-name set becomes "(shared)"', () {
    final mine = _plain('mine', 'Glass Harbor', 90);
    final copy = Song.withParts(
      id: 'copy',
      name: 'Glass Harbor (shared)',
      parts: _harbor.parts,
      end: _harbor.end,
    );
    final library = _library(
      [mine],
      [
        const Setlist(id: 'fri', name: 'Fri', songIds: ['mine']),
      ],
    );
    final plan = ImportPlan.of(
      library,
      parseShared(
        exportSetText(const Setlist(id: 's', name: 'Fri', songIds: []), [
          _harbor,
        ]),
      )!,
      newId,
    );
    expect(plan.renamed, [('Glass Harbor', 'Glass Harbor (shared)')]);
    expect(plan.newSet!.name, 'Fri (shared)');
    expect(library.songs.single, mine, reason: 'never changed');

    // With that copy in the library: the same music finds it…
    final withCopy = _library([mine, copy]);
    final again = ImportPlan.of(
      withCopy,
      parseShared(exportSongText(_harbor))!,
      newId,
    );
    expect(again.ids, ['copy']);
    expect(again.newSongs, isEmpty);
    // …and a third, different version becomes "(shared 2)".
    final other = ImportPlan.of(
      withCopy,
      parseShared(exportSongText(_plain('z', 'Glass Harbor', 150)))!,
      newId,
    );
    expect(other.newSongs.single.name, 'Glass Harbor (shared 2)');
  });

  test('the version 1 export from build 101 still reads (golden)', () {
    final file = File('test/fixtures/export_v1/set.txt');
    if (Platform.environment['WRITE_SNAPSHOT'] == '1' && !file.existsSync()) {
      file
        ..createSync(recursive: true)
        ..writeAsStringSync(
          exportSetText(const Setlist(id: 's', name: 'Fri', songIds: []), [
            _harbor,
            _plain('rock', 'Rock', 100),
          ]),
        );
    }
    final read = parseShared(file.readAsStringSync())!;
    expect(read.setName, 'Fri');
    expect(musicKey(read.songs.first), musicKey(_harbor));
    expect(read.songs.last.parts.single.tempoStart, 100);
  });
}
