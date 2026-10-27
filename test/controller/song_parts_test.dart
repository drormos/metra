import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/storage/library_store.dart';

import '../audio/fake_click_output.dart';

const _ms = Duration(milliseconds: 1);
const _four = MetronomePattern.standard();
final _three = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);
final _two = MetronomePattern.simple(beatsPerBar: 2, stepsPerBeat: 1);

SongPart _part(String id, int bars, int from, [int? to, MetronomePattern? p]) =>
    SongPart(
      id: id,
      name: id,
      bars: bars,
      tempoStart: from,
      tempoEnd: to ?? from,
      pattern: p ?? _four,
    );

/// Songs with parts (ui-spec.md "Song parts"), on the fake engine clock.
void main() {
  late FakeClickOutput output;
  late MetronomeController controller;

  setUp(() {
    output = FakeClickOutput()..time = _ms * 1000;
    controller = MetronomeController(output);
  });
  tearDown(() => controller.dispose());

  // Tops the scheduler up at the fake engine time.
  void runTo(int ms) {
    while (output.time < _ms * ms) {
      output.time += _ms * 25;
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    }
  }

  /// Live clicks up to [ms], as (ms, accent?), rounded to 0.1 ms.
  List<(double, bool)> clicks(int ms) => [
    for (final c in output.live)
      if (c.at <= _ms * ms)
        ((c.at.inMicroseconds / 100).round() / 10, c.level == StepLevel.accent),
  ];

  void load(List<SongPart> parts, {SongEnd end = SongEnd.stop}) =>
      controller.loadSong(
        bpm: 0,
        pattern: _four,
        parts: parts,
        end: end,
        onStart: controller.onStart,
      );

  test('one part: nothing changes (no parts held, the song\'s own tempo); '
      'a renamed one is kept but plays as before', () {
    final plain = SongPart.steady(
      id: SongPart.firstId,
      name: SongPart.firstName,
      bars: 1,
      bpm: 90,
      pattern: _three,
    );
    controller.loadSong(bpm: 90, pattern: _three, parts: [plain]);
    expect(controller.parts, isNull);
    expect(controller.partPosition, isNull);
    expect(controller.bpm, 90);
    controller.loadSong(bpm: 90, pattern: _three, parts: [_part('a', 1, 90)]);
    expect(controller.parts, hasLength(1));
    expect(controller.playsParts, isFalse);
  });

  test('each part starts on a bar line in its own time signature and '
      'tempo; an odd one-bar part; Loop last part runs on', () async {
    load([
      _part('a', 1, 120),
      _part('b', 1, 120, null, _two),
      _part('c', 1, 60, null, _three),
    ], end: SongEnd.loopLastPart);
    expect(controller.bpm, 120);
    await controller.play(); // beat 1 at 1120
    runTo(7300);
    expect(clicks(7200), [
      (1120, true), (1620, false), (2120, false), (2620, false), // a, 4/4
      (3120, true), (3620, false), // b, 2/4
      (4120, true), (5120, false), (6120, false), // c, 3/4 at 60
      (7120, true),
    ]);
    expect(controller.bpm, 60);
    expect(controller.pattern, _three);
    expect(controller.partPosition, (part: 2, bar: 0), reason: 'again');
    runTo(30000);
    expect(controller.isPlaying, isTrue);
    controller.stop();
    expect(controller.bpm, 120, reason: 'ready to start over');
    expect(controller.pattern, _four);
  });

  test('Gradual changes tempo on every beat, reaching To on the last beat; '
      'the next part starts at its own tempo', () async {
    load([
      _part('a', 1, 60, 120),
      _part('b', 1, 90),
    ], end: SongEnd.loopLastPart);
    await controller.play();
    runTo(4500);
    // 60, 80, 100, 120 bpm: 1000, 750, 600, 500 ms; then 90 bpm.
    expect(clicks(4000).map((c) => c.$1), [1120, 2120, 2870, 3470, 3970]);
    runTo(3000);
    controller.stop();
  });

  test('the BPM follows the live tempo beat by beat', () async {
    load([
      _part('a', 1, 60, 120),
      _part('b', 1, 90),
    ], end: SongEnd.loopLastPart);
    await controller.play();
    runTo(2200);
    expect(controller.bpm, 80);
    runTo(3500);
    expect(controller.bpm, 120);
    runTo(4000);
    expect(controller.bpm, 90);
  });

  test('loop song: back to part 1 on the bar line; the count-in plays once, in '
      'the first part\'s meter', () async {
    controller.setCountIn(1);
    load([
      _part('a', 1, 120, null, _two),
      _part('b', 1, 120, null, _three),
    ], end: SongEnd.loopSong);
    await controller.play();
    runTo(6200);
    expect(clicks(6000), [
      (1120, true), (1620, false), // count-in, 2/4
      (2120, true), (2620, false), // a
      (3120, true), (3620, false), (4120, false), // b
      (4620, true), (5120, false), // a again
      (5620, true), // b again
    ]);
    expect(controller.countingIn, isFalse);
    expect(controller.isPlaying, isTrue);
  });

  test('loop last part: the last part again and again until Stop; a '
      'Gradual one restarts its ramp; the song never ends', () async {
    var ended = 0;
    controller.onSongEnd = () => ended++;
    load([
      _part('a', 1, 120, null, _two),
      _part('b', 1, 60, 120),
    ], end: SongEnd.loopLastPart);
    await controller.play(); // beat 1 at 1120
    runTo(9000);
    // a: 2 beats at 120; b: 60, 80, 100, 120 bpm (1000, 750, 600, 500),
    // then b again from 60.
    expect(clicks(8000).map((c) => c.$1), [
      1120, 1620, // a
      2120, 3120, 3870, 4470, // b
      4970, 5970, 6720, 7320, 7820, // b again
    ]);
    expect(controller.partPosition?.part, 1);
    runTo(60000);
    expect(controller.isPlaying, isTrue);
    expect(ended, 0);
    controller.stop();
  });

  test('End: Stop stops at the end of the last part and says the song '
      'ended; Stop after says nothing', () async {
    var ended = 0;
    controller.onSongEnd = () => ended++;
    load([_part('a', 1, 120), _part('b', 1, 120)]);
    await controller.play();
    runTo(5300);
    expect(output.live.last.at, _ms * 4620, reason: 'eight beats');
    expect(controller.isPlaying, isFalse);
    expect(ended, 1);

    controller.setOnStart(
      const OnStart(stopOn: true, stopBy: StopBy.bars, stopBars: 1),
    );
    await controller.play();
    runTo(9000);
    expect(controller.isPlaying, isFalse);
    expect(ended, 1);
  });

  test('speed up is ignored for a song with parts', () async {
    controller.setOnStart(const OnStart(speedUp: true, changeBy: 10, every: 1));
    load([_part('a', 4, 120), _part('b', 1, 120)], end: SongEnd.loopLastPart);
    await controller.play();
    runTo(9000);
    expect(controller.bpm, 120);
    expect(controller.startBpm, 120);
  });

  group('going to a part', () {
    test('playing: on the next bar line', () async {
      load([_part('a', 4, 120), _part('b', 4, 90, null, _three)]);
      await controller.play();
      runTo(1700); // in bar 1
      controller.jumpToPart(1);
      runTo(5300);
      expect(clicks(5200).where((c) => c.$2).map((c) => c.$1), [
        1120,
        3120, // b, the next bar line
        5120, // 3 beats at 90
      ]);
      expect(controller.partPosition, (part: 1, bar: 1));
    });

    test('stopped: Start begins there, the count-in in its tempo and '
        'time signature', () async {
      controller.setCountIn(1);
      load([_part('a', 4, 120), _part('b', 4, 90, null, _three)]);
      controller.jumpToPart(1);
      expect(controller.partPosition, (part: 1, bar: 0));
      expect(controller.bpm, 90);
      expect(controller.pattern, _three);
      await controller.play();
      runTo(3300);
      expect(clicks(3200).map((c) => c.$1), [1120, 1786.7, 2453.3, 3120]);
      expect(controller.countingIn, isFalse);
      controller.stop();
      expect(controller.bpm, 90, reason: 'still starts there');
    });
  });

  test('a tempo change moves the current part, both ends of a Gradual one; '
      'the change holds until the part ends', () async {
    load([
      _part('a', 2, 100),
      _part('b', 2, 60, 120),
      _part('c', 1, 80),
    ], end: SongEnd.loopLastPart);
    controller.setBpm(110);
    expect(controller.parts![0].tempoStart, 110);
    controller.jumpToPart(1);
    controller.setBpm(70);
    expect(
      (controller.parts![1].tempoStart, controller.parts![1].tempoEnd),
      (70, 130),
    );
    controller.jumpToPart(0);
    await controller.play();
    runTo(1300);
    controller.setBpm(150); // part a, while it plays
    runTo(3000);
    expect(controller.bpm, 150, reason: 'holds through the part');
    expect(controller.parts![0].tempoStart, 150);
    controller.stop();
  });

  test('an edit just before the next part, already on its way, changes only '
      'the current part; the next one plays as it is', () async {
    load([_part('a', 1, 120), _part('b', 2, 60, null, _two)]);
    await controller.play();
    runTo(3050); // b's first beat (3120) is handed over, not yet heard
    expect(controller.partPosition, (part: 0, bar: 0));
    controller
      ..cycleBeat(1)
      ..setBpm(150);
    expect(controller.parts![0].tempoStart, 150);
    expect(controller.parts![0].pattern.beatLevels[1], StepLevel.accent);
    runTo(5300);
    expect(clicks(5200), [
      (1120, true), (1620, false), (2120, false), (2620, false),
      (3120, true), (4120, false), (5120, true), // b: 2/4 at 60
    ]);
    expect(controller.parts![1], _part('b', 2, 60, null, _two));
  });

  group('the parts page\'s edits while playing (no restart)', () {
    test('a plain song that gains a part goes on in its first part, the bar '
        'playing now its first bar', () async {
      controller.loadSong(bpm: 120, pattern: _four);
      await controller.play(); // beat 1 at 1120
      runTo(1700); // in bar 0
      controller.setParts([_part('a', 2, 120), _part('b', 1, 60, null, _two)]);
      expect(controller.playsParts, isTrue);
      runTo(6300);
      // Bars 0 and 1 of a, then b (2/4 at 60) at 5120.
      expect(clicks(6200).where((c) => c.$2).map((c) => c.$1), [
        1120,
        3120,
        5120,
      ]);
      expect(controller.pattern, _two);
      controller.stop();
    });

    test(
      'a new tempo for the part playing applies from the next beat',
      () async {
        load([
          _part('a', 4, 120),
          _part('b', 1, 120),
        ], end: SongEnd.loopLastPart);
        await controller.play();
        runTo(1300);
        controller.setParts([_part('a', 4, 60), _part('b', 1, 120)]);
        runTo(4000);
        expect(controller.bpm, 60);
        final times = clicks(4000).map((c) => c.$1).toList();
        expect(times.first, 1120, reason: 'no restart on beat 1');
        expect(times[2] - times[1], 1000);
        controller.stop();
      },
    );

    test('left with one looping bar, it plays on as a plain song', () async {
      load([_part('a', 1, 120), _part('b', 1, 120)]);
      await controller.play();
      runTo(1300);
      controller.setParts([
        SongPart.steady(
          id: SongPart.firstId,
          name: SongPart.firstName,
          bars: 1,
          bpm: 120,
          pattern: _four,
        ),
      ], end: SongEnd.loopLastPart);
      expect(controller.parts, isNull);
      runTo(9000);
      expect(controller.isPlaying, isTrue, reason: 'no song end any more');
      controller.stop();
    });
  });

  group('heads-up before a part changes', () {
    // At engine time [ms]: "next in N bars [details]" / "next in N beats
    // [details]", or null.
    String? up(int ms) {
      final h = controller.headsUpAt(_ms * ms);
      if (h == null) return null;
      final when = h.bars != null ? '${h.bars} bars' : '${h.beats}';
      final details = headsUpDetails(h.current, h.next);
      return '${h.next.name} in $when${details.isEmpty ? '' : ' · $details'}';
    }

    // Runs to [ms] in 5 ms steps, noting each change of the heads-up as
    // (time, text).
    List<(int, String?)> trace(int ms) {
      final changes = <(int, String?)>[];
      String? last = '-';
      while (output.time < _ms * ms) {
        output.time += _ms * 5;
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        final now = output.time.inMilliseconds;
        final u = up(now);
        if (u != last) changes.add((now, last = u));
      }
      return changes;
    }

    test(
      '2 bars before, then the beats of the last bar, on the beat; a '
      '1-bar part counts down at once; time signature and tempo changes '
      'shown; a Gradual part counts its own beats; Loop song warns',
      () async {
        load([
          _part('a', 5, 120), // 4/4, a bar is 2 s: a long part
          _part('b', 1, 90, null, _two), // a beat is 666.7 ms
          _part('c', 3, 60, 120), // Gradual
        ], end: SongEnd.loopSong);
        await controller.play(); // a from 1120
        final changes = trace(30000);
        // a, then b: on each beat, from what you hear.
        expect(changes.take(9).toList(), [
          (1005, null),
          (7120, 'b in 2 bars · 2/4 · 90'),
          (9120, 'b in 4 · 2/4 · 90'),
          (9620, 'b in 3 · 2/4 · 90'),
          (10120, 'b in 2 · 2/4 · 90'),
          (10620, 'b in 1 · 2/4 · 90'),
          // b: one bar of 2/4, counting down at once; c starts at 60.
          (11120, 'c in 2 · 4/4 · 60'),
          (11790, 'c in 1 · 4/4 · 60'),
          // c (3 bars): short, so it counts bars from its first.
          (12455, 'a in 3 bars'),
        ]);
        // c (60 → 120, its beats getting shorter): then 2 bars, then its
        // last bar's four beats; Loop song back to a, at 120 where c ends
        // (no tempo); a is long: the normal line.
        final c = changes.skip(9).take(6).toList();
        expect(
          [for (final x in c) x.$2],
          ['a in 2 bars', 'a in 4', 'a in 3', 'a in 2', 'a in 1', null],
        );
        final beats = [for (var i = 2; i < 6; i++) c[i].$1 - c[i - 1].$1];
        expect(beats.first, greaterThan(beats.last), reason: 'speeding up');
        controller.stop();
      },
    );

    test('nothing before the song stops, while the last part loops, or '
        'during a count-in', () async {
      controller.setCountIn(1);
      load([_part('a', 1, 120), _part('b', 2, 120)]);
      await controller.play(); // count-in from 1120, a from 3120
      expect(trace(12000), [
        (1005, null), // the count-in included
        (3120, 'b in 4'),
        (3620, 'b in 3'),
        (4120, 'b in 2'),
        (4620, 'b in 1'),
        (5120, null), // the song stops after b: nothing
      ]);
      controller.stop();
      controller.setCountIn(0);
      load([_part('a', 1, 120), _part('b', 1, 120)], end: SongEnd.loopLastPart);
      await controller.play();
      // From Start, before the first beat sounds: already the countdown.
      expect(
        [for (final c in trace(30000)) c.$2],
        [
          'b in 4',
          'b in 3',
          'b in 2',
          'b in 1',
          null, // then b loops: no more
        ],
      );
      controller.stop();
    });

    test('Sound on part changes: a new part\'s first beat raised, in the '
        'engine; not the start, not another pass of a looping part', () async {
      controller.setPartChangeSound(true);
      load([
        _part('a', 1, 120, null, _two),
        _part('b', 1, 120),
      ], end: SongEnd.loopSong);
      await controller.play(); // a 1120, 1620; b 2120…3620; a 4120
      runTo(4500);
      expect(
        [
          for (final c in output.live)
            if (c.at <= _ms * 4500) (c.at.inMilliseconds, c.raised),
        ],
        [
          (1120, false), (1620, false), // a: the start isn't a change
          (2120, true), (2620, false), (3120, false), (3620, false), // b
          (4120, true), // a again
        ],
      );
      controller.stop();
      // Off: nothing raised.
      controller.setPartChangeSound(false);
      output.clicks.clear();
      await controller.play();
      runTo(9000);
      expect(output.live.where((c) => c.raised), isEmpty);
      controller.stop();
      // Loop last part: its passes aren't changes.
      controller.setPartChangeSound(true);
      output.clicks.clear();
      load([_part('a', 1, 120), _part('b', 1, 120)], end: SongEnd.loopLastPart);
      await controller.play();
      final start = output.time.inMilliseconds;
      runTo(start + 9000);
      expect(output.live.where((c) => c.raised), hasLength(1), reason: 'a → b');
      controller.stop();
    });
  });

  group('with the library', () {
    late Directory dir;
    late LibraryController library;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('metra_parts');
      library = await LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      );
      library.attach(controller);
    });
    tearDown(() async {
      await library.flush();
      dir.deleteSync(recursive: true);
    });

    Song addParts(String name, List<SongPart> parts) => library.addSong(
      name: name,
      bpm: 0,
      pattern: _four,
      parts: parts,
      end: SongEnd.stop,
    );

    test('in a set, a song whose parts end leaves the next song ready; it '
        'never starts by itself', () async {
      final first = addParts('First', [_part('a', 1, 120), _part('b', 1, 120)]);
      final next = library.addSong(name: 'Next', bpm: 90, pattern: _three);
      final set = library.saveSetlist(
        name: 'Set',
        songIds: [first.id, next.id],
      );
      library.loadSetlist(set.id, controller);
      await controller.play();
      runTo(5300);
      expect(controller.isPlaying, isFalse);
      expect(library.currentSong!.name, 'Next');
      expect(controller.bpm, 90);
    });

    test('in a set, with the parts page open, a song that ends stays '
        'loaded, back at part 1, wherever it started', () async {
      final first = addParts('First', [_part('a', 1, 120), _part('b', 1, 120)]);
      final next = library.addSong(name: 'Next', bpm: 90, pattern: _three);
      final set = library.saveSetlist(
        name: 'Set',
        songIds: [first.id, next.id],
      );
      library.loadSetlist(set.id, controller);
      library.editingParts = true;
      await controller.playFrom(1);
      runTo(5300);
      expect(controller.isPlaying, isFalse);
      expect(library.currentSong!.name, 'First');
      expect(controller.partPosition, (part: 0, bar: 0));
    });

    test('changes are unsaved changes: Revert brings the parts back, Save '
        'stores them', () {
      final song = addParts('Song', [_part('a', 2, 100), _part('b', 2, 140)]);
      library.playSingleSong(song, controller);
      expect(library.songChanged(controller), isFalse);
      controller.setBpm(104);
      expect(library.songChanged(controller), isTrue);
      library.revertSong(controller);
      expect(library.songChanged(controller), isFalse);
      expect(controller.parts![0].tempoStart, 100);
      controller.setBpm(104);
      library.saveToSong(controller);
      expect(library.songById(song.id)!.parts[0].tempoStart, 104);
      expect(library.songById(song.id)!.parts, hasLength(2));
      expect(library.songChanged(controller), isFalse);
    });
  });
}
