import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/model/song_part.dart';
import 'package:metra/src/model/song_plan.dart';

const _four = MetronomePattern.standard();
final _three = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

SongPart _part(
  String id,
  int? bars,
  int from, [
  int? to,
  MetronomePattern? p,
]) => SongPart(
  id: id,
  name: id,
  bars: bars,
  tempoStart: from,
  tempoEnd: to ?? from,
  pattern: p ?? _four,
);

void main() {
  SongPlan plan(
    List<SongPart> parts, {
    SongEnd end = SongEnd.stop,
    OnStart onStart = OnStart.off,
    int start = 0,
  }) => SongPlan(parts: parts, end: end, onStart: onStart, startPart: start);

  test('bars map to parts in order; past the end of a stopping song, none', () {
    final p = plan([
      _part('a', 2, 100),
      _part('b', 1, 100),
      _part('c', 3, 100),
    ]);
    expect(
      [for (var b = 0; b < 7; b++) p.locate(b)],
      [
        (part: 0, bar: 0),
        (part: 0, bar: 1),
        (part: 1, bar: 0),
        (part: 2, bar: 0),
        (part: 2, bar: 1),
        (part: 2, bar: 2),
        null,
      ],
    );
    expect(p.endsAt(6, Duration.zero), isTrue);
    expect(p.endsAt(5, Duration.zero), isFalse);
  });

  test('loop goes back to part 1, however long it runs', () {
    final p = plan([_part('a', 2, 100), _part('b', 1, 100)], end: SongEnd.loop);
    expect(p.locate(3), (part: 0, bar: 0));
    expect(p.locate(3000 * 3 + 2), (part: 1, bar: 0));
    expect(p.endsAt(3000, Duration.zero), isFalse);
  });

  test('an open last part runs until Stop', () {
    final p = plan([_part('a', 1, 100), _part('b', null, 100)]);
    expect(p.locate(10000), (part: 1, bar: 9999));
    expect(p.endsAt(10000, Duration.zero), isFalse);
  });

  test('a start part and jumps replace what follows', () {
    final p = plan([
      _part('a', 4, 100),
      _part('b', 4, 100),
      _part('c', 4, 100),
    ], start: 1);
    expect(p.locate(0), (part: 1, bar: 0));
    expect(p.locate(4), (part: 2, bar: 0));
    p.jump(2, 0);
    expect(p.locate(1), (part: 1, bar: 1));
    expect(p.locate(2), (part: 0, bar: 0));
    p.jump(1, 2); // replaces the later jump
    expect(p.locate(2), (part: 2, bar: 1));
  });

  test('patterns change only on a part\'s first bar', () {
    final p = plan([_part('a', 2, 100), _part('b', 2, 100, null, _three)]);
    expect(p.patternAt(0), _four);
    expect(p.patternAt(1), isNull);
    expect(p.patternAt(2), _three);
    expect(p.patternAt(3), isNull);
  });

  test('Gradual: every beat, linear, reaching To on the last beat; steady: '
      'its first beat only', () {
    final p = plan([_part('a', 2, 60, 130), _part('b', 1, 90)]);
    // 8 beats from 60 to 130: +10 a beat.
    expect(
      [for (var beat = 0; beat < 4; beat++) p.tempoAt(0, beat, 0)],
      [60, 70, 80, 90],
    );
    expect(p.tempoAt(1, 3, 0), 130);
    expect(p.tempoAt(2, 0, 0), 90);
    expect(p.tempoAt(2, 1, 0), isNull, reason: 'a hand-set tempo holds');
  });

  test('a one-beat Gradual part plays To; an open part is steady', () {
    final one = _part(
      'a',
      1,
      60,
      120,
      MetronomePattern.simple(beatsPerBar: 1, stepsPerBeat: 1),
    );
    expect(one.tempoAtBeat(0), 120);
    expect(_part('b', null, 60, 120).gradual, isFalse);
  });

  test('speed up is ignored; Stop after still ends it', () {
    final p = plan(
      [_part('a', 8, 100), _part('b', null, 100)],
      onStart: const OnStart(
        speedUp: true,
        every: 1,
        stopOn: true,
        stopBy: StopBy.bars,
        stopBars: 3,
      ),
    );
    expect(p.tempoAt(2, 0, 100), isNull);
    expect(p.endsAt(3, Duration.zero), isTrue);
  });

  test('a ramp holds at its ends: a beat past the last plays To (found by '
      'parts_fuzz_test session 831 at 2000 sessions)', () {
    final down = _part('a', 1, 140, 40);
    expect(down.tempoAtBeat(3), 40);
    expect(down.tempoAtBeat(11), 40);
    expect(down.tempoAtBeat(-1), 140);
  });
}
