import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/main.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/song_map.dart';
import 'package:metra/src/ui/stage_screen.dart';
import 'package:metra/src/ui/tempo_ruler.dart';

import '../audio/fake_click_output.dart';

import 'package:metra/src/ui/theme.dart';

import 'test_theme.dart';

const _four = MetronomePattern.standard();
final _three = MetronomePattern.simple(beatsPerBar: 3, stepsPerBeat: 1);

/// The main screen and stage mode for a song with parts (ui-spec.md "Main
/// screen for a song with parts").
void main() {
  late Directory dir;
  late FakeClickOutput output;
  late MetronomeController metronome;
  late LibraryController library;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_song_map'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save may still be writing; harmless.
    }
  });

  // Intro (2 bars, 100), Verse (4 bars, 3/4, 120), Outro (8 bars, 90,
  // looping: the default end).
  final threeParts = [
    SongPart.steady(id: 'i', name: 'Intro', bars: 2, bpm: 100, pattern: _four),
    SongPart.steady(id: 'v', name: 'Verse', bars: 4, bpm: 120, pattern: _three),
    SongPart.steady(id: 'o', name: 'Outro', bars: 8, bpm: 90, pattern: _four),
  ];

  /// "Dead Weight" with [parts] (or one plain part) as a single song;
  /// [stage] puts it in a set in stage mode.
  Future<void> pump(
    WidgetTester tester, {
    List<SongPart>? parts,
    bool stage = false,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (_) async => null,
    );
    output = FakeClickOutput()..time = const Duration(seconds: 1);
    metronome = MetronomeController(output);
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    library.attach(metronome);
    final song = library.addSong(
      name: 'Dead Weight',
      bpm: 120,
      pattern: _four,
      parts: parts,
    );
    library.markSongsHintSeen();
    if (stage) {
      final set = library.saveSetlist(name: 'Set', songIds: [song.id]);
      library
        ..markTipSeen(LibraryController.stageTip)
        ..loadSetlist(set.id, metronome)
        ..enterStageMode(metronome);
      await tester.pumpWidget(
        MetraApp(controller: metronome, library: library),
      );
    } else {
      library.playSingleSong(song, metronome);
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: MetronomeScreen(controller: metronome, library: library),
        ),
      );
    }
    await tester.pump();
  }

  // The engine clock and the frames together, to [ms].
  Future<void> runTo(WidgetTester tester, int ms) async {
    while (output.time < Duration(milliseconds: ms)) {
      output.time += const Duration(milliseconds: 20);
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  String line(WidgetTester tester) {
    final playing = find.byKey(MetronomeScreen.countInLineKey);
    final key = playing.evaluate().isNotEmpty
        ? MetronomeScreen.countInLineKey
        : MetronomeScreen.tempoNameKey;
    return tester.widget<Text>(find.byKey(key)).data!;
  }

  /// Slides the map by [dx], a finger's moves in steps.
  Future<void> slide(WidgetTester tester, double dx) async {
    final g = await tester.startGesture(tester.getCenter(find.byType(SongMap)));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(Offset(dx / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Taps the map [dx] px right of its needle.
  Future<void> tapMap(WidgetTester tester, double dx) async {
    await tester.tapAt(tester.getCenter(find.byType(SongMap)) + Offset(dx, 0));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a one-part song keeps the tempo ruler; with parts the map '
      'takes its slot, same place and height', (tester) async {
    await pump(tester);
    expect(find.byType(TempoRuler), findsOneWidget);
    expect(find.byType(SongMap), findsNothing);
    final ruler = tester.getRect(find.byType(TempoRuler));
    await pump(tester, parts: threeParts);
    expect(find.byType(TempoRuler), findsNothing);
    expect(tester.getRect(find.byType(SongMap)), ruler);
    expect(line(tester), 'Intro · bar 1 of 2 · next: Verse');
  });

  testWidgets('stopped: a tap goes to the part (the start point, its tempo '
      'and meter); a slide snaps to the part under the needle', (tester) async {
    await pump(tester, parts: threeParts);
    // Intro 0–28 px, Verse 31–87, Outro from 90.
    await tapMap(tester, 40);
    expect(metronome.partPosition, (part: 1, bar: 0));
    expect(metronome.bpm, 120);
    expect(metronome.pattern, _three);
    expect(line(tester), 'Verse · bar 1 of 4 · next: Outro');
    // Past the touch slop, ~70 px of map: from the Verse into the Outro.
    await slide(tester, -90);
    expect(metronome.partPosition?.part, 2);
    expect(line(tester), 'Outro · bar 1 of 8 · looping');
    await slide(tester, 200);
    expect(metronome.partPosition?.part, 0);
  });

  testWidgets('playing: the line follows the song; a tap jumps at once; '
      'the map follows', (tester) async {
    await pump(tester, parts: threeParts);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    // Intro at 100 bpm from 1120: bars of 2.4 s.
    await runTo(tester, 1700);
    expect(line(tester), 'Intro · bar 1 of 2 · next: Verse');
    await tapMap(tester, 100); // the Outro
    await runTo(tester, 1800); // its beat 1 a guard after the tap
    expect(metronome.partPosition, (part: 2, bar: 0));
    expect(line(tester), 'Outro · bar 1 of 8 · looping');
    expect(metronome.bpm, 90);
    metronome.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('heads-up: the last bar\'s name a white tag counting the '
      'beats; bars out, bold; a long part, the normal line', (tester) async {
    await pump(tester, parts: threeParts);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    Text tag() => tester.widget<Text>(
      find.descendant(
        of: find.byKey(MetronomeScreen.headsUpTagKey),
        matching: find.byType(Text),
      ),
    );
    Finder text(String data) => find.descendant(
      of: find.byKey(MetronomeScreen.headsUpKey),
      matching: find.text(data),
    );
    // Between Start and the first beat (1120): already the heads-up, not
    // the normal line first.
    await runTo(tester, 1040);
    expect(text('Verse in 2 bars'), findsOneWidget);
    // Intro (2 bars at 100, from 1120): a short part counts bars from its
    // first, then its last bar's beats.
    await runTo(tester, 1700);
    expect(text('Verse in 2 bars'), findsOneWidget);
    expect(find.byKey(MetronomeScreen.headsUpTagKey), findsNothing);
    await runTo(tester, 3700);
    expect(tag().data, 'Verse in 4');
    expect(text(' · 3/4 · 120'), findsOneWidget);
    final box = tester.widget<Container>(
      find.byKey(MetronomeScreen.headsUpTagKey),
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      MetraColors.stageBlack.text,
      reason: 'white tag',
    );
    expect(tag().style!.color, MetraColors.stageBlack.background);
    await runTo(tester, 4300); // beat 2 at 4120
    expect(tag().data, 'Verse in 3');
    // Verse (4 bars of 3/4 at 120, from 5920): short too, from bar 1.
    await runTo(tester, 6000);
    expect(text('Outro in 4 bars'), findsOneWidget);
    // Its bar 3 (from 8920): 2 bars out, bold.
    await runTo(tester, 9000);
    final bold = tester.widget<Text>(text('Outro in 2 bars'));
    expect(bold.style!.fontWeight, FontWeight.w700);
    expect(text(' · 4/4 · 90'), findsOneWidget);
    expect(find.byKey(MetronomeScreen.headsUpTagKey), findsNothing);
    // The Outro (8 bars, from 11920, looping): the normal line.
    await runTo(tester, 12000);
    expect(find.byKey(MetronomeScreen.headsUpKey), findsNothing);
    expect(line(tester), 'Outro · bar 1 of 8 · looping');
    metronome.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('with Stop after, the line shows both, part first', (
    tester,
  ) async {
    await pump(tester, parts: threeParts);
    metronome.setOnStart(
      const OnStart(stopOn: true, stopBy: StopBy.bars, stopBars: 12),
    );
    // From the Outro (8 bars): the short parts count down instead.
    await tapMap(tester, 100);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    await runTo(tester, 1700);
    expect(line(tester), 'Outro · bar 1 of 8 · 12 bars left');
    metronome.setOnStart(
      const OnStart(stopOn: true, stopTime: Duration(minutes: 4, seconds: 13)),
    );
    await runTo(tester, 2200);
    expect(line(tester), 'Outro · bar 1 of 8 · 4:12 left');
    metronome.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('−5…+5 and Tap change the current part only; the change stays '
      'through other parts, as an unsaved change', (tester) async {
    await pump(tester, parts: threeParts);
    await tester.tap(find.text('+5'));
    await tester.pump();
    await tapMap(tester, 40); // to the Verse
    await tester.tap(find.text('−1'));
    await tester.pump();
    expect([for (final p in metronome.parts!) p.tempoStart], [105, 119, 90]);
    expect(library.songChanged(metronome), isTrue);
    await tapMap(tester, -40); // back to the Intro
    expect(metronome.bpm, 105, reason: 'kept');
    library.revertSong(metronome);
    expect([for (final p in metronome.parts!) p.tempoStart], [100, 120, 90]);
  });

  testWidgets('TalkBack: an adjustable "Song map"; up/down moves part by '
      'part', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, parts: threeParts);
    final map = find.bySemanticsLabel('Song map');
    expect(
      tester.getSemantics(map),
      isSemantics(
        label: 'Song map',
        value: 'Intro, part 1 of 3',
        increasedValue: 'Verse, part 2 of 3',
        isSlider: true,
        hasIncreaseAction: true,
      ),
    );
    tester.semantics.increase(find.semantics.byLabel('Song map'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(metronome.partPosition?.part, 1);
    handle.dispose();
  });

  testWidgets('stage mode: the map under the BPM, taps only', (tester) async {
    await pump(tester, parts: threeParts, stage: true);
    expect(find.byType(StageScreen), findsOneWidget);
    expect(find.byType(SongMap), findsOneWidget);
    await slide(tester, -150);
    expect(metronome.partPosition?.part, 0, reason: 'no sliding');
    await tapMap(tester, 40);
    expect(metronome.partPosition?.part, 1);
  });

  testWidgets('Free play never holds a song: the map goes, the click keeps '
      'the part it was on', (tester) async {
    await pump(tester, parts: threeParts);
    await tapMap(tester, 40); // the Verse
    library.detachSong();
    await tester.pump();
    expect(metronome.parts, isNull);
    expect(find.byType(TempoRuler), findsOneWidget);
    expect(metronome.bpm, 120);
    expect(metronome.pattern, _three);
  });

  test('map positions: to scale, a short part never thinner than 24 px', () {
    final blocks = SongMap.layout(threeParts);
    expect([for (final b in blocks) b.x], [0, 31, 90]);
    expect(SongMap.position(threeParts, blocks, 1, 2, 0.5), 31 + 2.5 / 4 * 56);
    expect(SongMap.position(threeParts, blocks, 2, 4, 0), 90 + 4 * 14);
    final short = SongMap.layout([
      SongPart.steady(id: 'a', name: 'a', bars: 1, bpm: 90, pattern: _four),
    ]);
    expect(short.single.width, SongMap.minWidth);
  });
}
