import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart' show deleteConfirmKey;
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/on_start_sheet.dart';
import 'package:metra/src/ui/parts_page.dart';
import 'package:metra/src/ui/save_as_new_dialog.dart';
import 'package:metra/src/ui/swipe_row.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/time_signature_sheet.dart';
import 'package:metra/src/ui/value_stepper.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

/// The parts page (ui-spec.md "Song parts" → "The parts page").
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_parts_page'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  /// The main screen with "Dead Weight" (120, 4/4) loaded as a single
  /// song, unless [freePlay].
  Future<void> pump(WidgetTester tester, {bool freePlay = false}) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    metronome = MetronomeController(FakeClickOutput());
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
      pattern: const MetronomePattern.standard(),
    );
    library.markSongsHintSeen();
    if (!freePlay) library.playSingleSong(song, metronome);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  Future<void> openPage(WidgetTester tester) async {
    await tester.longPress(find.byKey(MetronomeScreen.titleBlockKey));
    await tester.pumpAndSettle();
    expect(find.byType(PartsPage), findsOneWidget);
  }

  String summary(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(PartsPage.summaryKey)).data!;
  List<SongPart> parts() => metronome.parts ?? library.currentSong!.parts;
  List<String> names() => [for (final p in parts()) p.name];
  Finder chip(Key group, String text) =>
      find.descendant(of: find.byKey(group), matching: find.text(text));

  Future<void> tapIn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('getting there', () {
    testWidgets('"Song parts ›" at the bottom of the Rhythm panel, with the '
        'count; long-pressing the title too', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(find.text('Song parts'), findsOneWidget);
      expect(find.text('1 part'), findsOneWidget);
      await tapIn(tester, find.byKey(SongPartsRow.rowKey));
      expect(find.byType(PartsPage), findsOneWidget);
      expect(find.byType(TimeSignatureSheet), findsNothing);
      expect(find.text('Dead Weight'), findsWidgets);
      expect(summary(tester), '1 part · 1 bar, then loops Part 1');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openPage(tester);
    });

    testWidgets('in Free play the row saves as a song first, then opens the '
        'page', (tester) async {
      await pump(tester, freePlay: true);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      await tapIn(tester, find.text(SongPartsRow.saveFirst));
      await tester.tap(find.byKey(SaveAsNewKeys.save));
      await tester.pumpAndSettle();
      expect(find.byType(PartsPage), findsOneWidget);
      expect(library.currentSong, isNotNull);
    });
  });

  testWidgets('"+ Add part" adds a copy of the last part with the next name, '
      'opened; the open part before it gets a length; it\'s an unsaved '
      'change: Discard (asked first) takes it back, Save stores it', (
    tester,
  ) async {
    await pump(tester);
    await openPage(tester);
    // Save / Discard fade in their reserved room.
    bool shown(Key key) =>
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byKey(key),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity ==
        1;
    expect(shown(PartsPage.saveKey), isFalse, reason: 'nothing unsaved');
    final title = tester.getTopLeft(find.byKey(PartsPage.nameKey));
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(names(), ['Part 1', 'Part 2']);
    expect(parts().map((p) => p.bars), [1, 1]);
    expect(summary(tester), '2 parts · 2 bars, then loops Part 2');
    expect(library.songChanged(metronome), isTrue);
    expect(shown(PartsPage.saveKey), isTrue);
    expect(shown(PartsPage.discardKey), isTrue);
    expect(tester.getTopLeft(find.byKey(PartsPage.nameKey)), title);
    expect(find.text('Save as new'), findsNothing);
    // Discard asks; Keep editing keeps the changes.
    await tapIn(tester, find.byKey(PartsPage.discardKey));
    expect(find.text('Discard changes to Dead Weight?'), findsOneWidget);
    expect(
      find.text('The song goes back to how it was last saved.'),
      findsOneWidget,
    );
    await tapIn(tester, find.text('Keep editing'));
    expect(names(), ['Part 1', 'Part 2']);
    await tapIn(tester, find.byKey(PartsPage.discardKey));
    expect(find.byKey(deleteConfirmKey), findsOneWidget);
    await tester.tap(find.byKey(deleteConfirmKey));
    await tester.pumpAndSettle();
    expect(find.byKey(deleteConfirmKey), findsNothing);
    expect(names(), ['Part 1']);
    expect(metronome.parts, isNull, reason: 'a plain song again');
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.saveKey));
    expect(library.currentSong!.parts, hasLength(2));
    expect(library.songChanged(metronome), isFalse);
    expect(shown(PartsPage.saveKey), isFalse);
  });

  testWidgets('while the page is open, a song that ends stays loaded '
      '(the library knows); after Back, a set moves on again', (tester) async {
    await pump(tester);
    await openPage(tester);
    expect(library.editingParts, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(library.editingParts, isFalse);
  });

  testWidgets('Back with unsaved changes: no question; they stay the '
      'song\'s unsaved changes on the main screen', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PartsPage), findsNothing);
    expect(library.songChanged(metronome), isTrue);
    expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
  });

  testWidgets('"When the song ends": three chips under the label, always '
      'shown; adding or removing parts never changes the choice; Loop last '
      'part marks the last block', (tester) async {
    await pump(tester);
    await openPage(tester);
    // A plain song loops its bar: the choice is there with one part too.
    expect(metronome.songEnd, SongEnd.loopLastPart);
    expect(find.byKey(PartsPage.loopIconKey), findsOneWidget);
    expect(find.text('Until you stop'), findsNothing);
    final label = tester.getTopLeft(find.text('When the song ends'));
    final stop = chip(PartsPage.endKey, 'Stop');
    expect(tester.getTopLeft(stop).dy, greaterThan(label.dy), reason: 'below');
    expect(chip(PartsPage.endKey, 'Loop song'), findsOneWidget);
    expect(chip(PartsPage.endKey, 'Loop last part'), findsOneWidget);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(metronome.songEnd, SongEnd.loopLastPart);
    await tester.dragUntilVisible(
      find.byKey(PartsPage.endKey),
      find.byType(ReorderableListView),
      const Offset(0, -100),
    );
    await tapIn(tester, chip(PartsPage.endKey, 'Loop song'));
    expect(metronome.songEnd, SongEnd.loopSong);
    expect(find.byKey(PartsPage.loopIconKey), findsNothing);
    expect(summary(tester), '2 parts · 2 bars · ≈ 0:04');
    await tapIn(tester, chip(PartsPage.endKey, 'Stop'));
    expect(metronome.songEnd, SongEnd.stop);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(metronome.songEnd, SongEnd.stop);
    tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(PartsPage.cardKey(0)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(parts(), hasLength(2));
    expect(metronome.songEnd, SongEnd.stop);
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Gradual: From the previous part\'s tempo, To this one\'s; the '
      'card reads 120 to 130', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, chip(PartsPage.tempoKindKey, 'Gradual'));
    expect((parts()[1].tempoStart, parts()[1].tempoEnd), (120, 130));
    // "120 → 130" on the card (the To field shows 130 too).
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    await tapIn(tester, find.byKey(ValueStepper.plusKey('To')));
    expect(parts()[1].tempoEnd, 131);
    await tapIn(tester, chip(PartsPage.tempoKindKey, 'Steady'));
    expect(parts()[1].gradual, isFalse);
  });

  testWidgets('swipe removes a part, with Undo; the last one can\'t go', (
    tester,
  ) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tester.drag(find.byKey(PartsPage.cardKey(1)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(names(), ['Part 1']);
    expect(find.text('Removed Part 2'), findsOneWidget);
    await tapIn(tester, find.byKey(PartsPage.undoKey));
    expect(names(), ['Part 1', 'Part 2']);
    await tester.drag(find.byKey(PartsPage.cardKey(0)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(PartsPage.cardKey(0)), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(parts(), hasLength(1), reason: 'the last part stays');
    await tester.pump(const Duration(seconds: 7));
  });

  testWidgets('Duplicate copies the part right after it; long-press drags '
      'to reorder', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey)); // Part 2
    await tapIn(tester, find.byKey(PartsPage.cardKey(1))); // closes it
    await tapIn(tester, find.byKey(PartsPage.cardKey(0)));
    await tapIn(tester, find.byKey(PartsPage.partNameKey));
    await tapIn(tester, find.text('Chorus').last);
    await tapIn(tester, find.byKey(PartsPage.duplicateKey));
    expect(names(), ['Chorus', 'Chorus', 'Part 2']);
    expect(parts()[0].id, isNot(parts()[1].id));
    await tapIn(tester, find.byKey(PartsPage.cardKey(1))); // close it
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(PartsPage.cardKey(2))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // One card up (60px + the 8px gap).
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, -12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(names(), ['Chorus', 'Part 2', 'Chorus']);
  });

  testWidgets('the strip opens the tapped part\'s card', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.stripKey(0)));
    expect(find.byKey(PartsPage.duplicateKey), findsOneWidget);
    expect(find.byKey(PartsPage.partNameKey), findsOneWidget);
  });

  testWidgets('Rhythm › edits the part\'s time signature', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.rhythmKey));
    await tester.tap(find.text('7/8'));
    await tester.pumpAndSettle();
    expect(parts()[1].pattern.timeSignature, '7/8');
    expect(parts()[0].pattern.timeSignature, '4/4');
  });

  testWidgets('"When I press Start": Speed up isn\'t for songs with parts', (
    tester,
  ) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MetronomeScreen.onStartKey));
    await tester.pumpAndSettle();
    expect(find.text(OnStartSheet.notForParts), findsOneWidget);
    expect(find.byType(SetlistGroup), findsOneWidget);
  });

  group('fixes after the first phone check', () {
    Future<void> drag(WidgetTester tester, Finder from, double dy) async {
      final gesture = await tester.startGesture(tester.getCenter(from));
      // A frame between the close (just before the lift) and the lift.
      await tester.pump(
        RowGestures.liftPress - const Duration(milliseconds: 20),
      );
      await tester.pump(kLongPressTimeout);
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(Offset(0, dy / 6));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('only the header lifts a card: held on an open card it '
        'closes and lifts in one gesture; held in the body, nothing', (
      tester,
    ) async {
      await pump(tester);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.addKey)); // Part 2, open
      // Held inside the open body (the accents): no lift, still open.
      // Scrolled without a drag: a held drag on the header would close it.
      final list = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(ReorderableListView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      list.jumpTo(list.maxScrollExtent);
      await tester.pumpAndSettle();
      await drag(tester, find.byKey(PartsPage.accentKey(0)), -80);
      expect(names(), ['Part 1', 'Part 2']);
      expect(find.byKey(PartsPage.duplicateKey), findsOneWidget);
      // Held on its header: closes, lifts, moves up one.
      list.jumpTo(0);
      await tester.pumpAndSettle();
      await drag(tester, find.byKey(PartsPage.cardKey(1)), -68);
      expect(names(), ['Part 2', 'Part 1']);
      expect(find.byKey(PartsPage.duplicateKey), findsNothing);
    });

    testWidgets('open card: Name, then Tempo, then Length', (tester) async {
      await pump(tester);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.addKey));
      double y(Key key) => tester.getTopLeft(find.byKey(key)).dy;
      final length = ValueStepper.plusKey('Length');
      expect(y(PartsPage.partNameKey), lessThan(y(PartsPage.tempoKindKey)));
      expect(y(PartsPage.tempoKindKey), lessThan(y(length)));
      expect(y(length), lessThan(y(PartsPage.rhythmKey)));
    });

    testWidgets('a stepper held repeats and speeds up', (tester) async {
      await pump(tester);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.cardKey(0)));
      final plus = find.byKey(ValueStepper.plusKey('BPM'));
      await tester.ensureVisible(plus);
      final gesture = await tester.startGesture(tester.getCenter(plus));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pump();
      // 2 s held: well past one step a tap.
      expect(metronome.bpm, greaterThan(135));
    });

    testWidgets('Play / Stop keeps its size; Stop is filled', (tester) async {
      await pump(tester);
      await openPage(tester);
      final play = tester.getSize(find.byKey(PartsPage.playKey));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      expect(tester.getSize(find.byKey(PartsPage.playKey)), play);
      expect(
        find.descendant(
          of: find.byKey(PartsPage.playKey),
          matching: find.byIcon(Icons.stop),
        ),
        findsOneWidget,
      );
      expect(tester.widget(find.byKey(PartsPage.playKey)), isA<FilledButton>());
      metronome.stop();
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('polish', () {
    SongPart part(String id, int bars, int from, int to, [int beats = 4]) =>
        SongPart(
          id: id,
          name: id,
          bars: bars,
          tempoStart: from,
          tempoEnd: to,
          pattern: MetronomePattern.simple(
            beatsPerBar: beats,
            stepsPerBeat: 2,
          ).cycleBeat(1),
        );

    testWidgets('"+ Add part" keeps the last part\'s rhythm and length, '
        'steady at the tempo it ends on', (tester) async {
      await pump(tester);
      metronome.setParts([
        part('Intro', 4, 100, 100),
        part('Verse', 8, 120, 140, 7),
      ]);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.addKey));
      final added = parts().last;
      expect(added.name, 'Pre-chorus');
      expect(added.bars, 8);
      expect(added.pattern, parts()[1].pattern);
      expect((added.tempoStart, added.tempoEnd), (140, 140));
      expect(
        find.byKey(PartsPage.duplicateKey),
        findsOneWidget,
        reason: 'open',
      );
    });

    testWidgets('Gradual starts From the tempo the previous part ends on', (
      tester,
    ) async {
      await pump(tester);
      metronome.setParts([
        part('Intro', 4, 100, 140),
        part('Verse', 8, 120, 120),
      ]);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.cardKey(1)));
      await tapIn(tester, chip(PartsPage.tempoKindKey, 'Gradual'));
      expect((parts()[1].tempoStart, parts()[1].tempoEnd), (140, 120));
    });
  });

  group('motion', () {
    List<SongPart> four() => [
      for (final name in ['Intro', 'Verse', 'Chorus', 'Outro'])
        SongPart.steady(
          id: name,
          name: name,
          bars: 4,
          bpm: 120,
          pattern: const MetronomePattern.standard(),
        ),
    ];

    testWidgets('opening a card while one above it closes keeps the tapped '
        'header still, every frame', (tester) async {
      await pump(tester);
      metronome.setParts([
        for (var n = 0; n < 16; n++)
          SongPart.steady(
            id: 'p$n',
            name: 'Part ${n + 1}',
            bars: 4,
            bpm: 120,
            pattern: const MetronomePattern.standard(),
          ),
      ]);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.cardKey(1)));
      // Scrolled down far enough to take the closing body back.
      await tester.drag(
        find.byType(ReorderableListView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      final header = find.byKey(PartsPage.cardKey(8));
      final y = tester.getTopLeft(header).dy;
      await tester.tap(header);
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(header).dy, closeTo(y, 1), reason: 'frame $i');
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(header).dy, closeTo(y, 1));
      expect(find.byKey(PartsPage.duplicateKey), findsOneWidget);
    });

    testWidgets('a tap mid-animation acts at once', (tester) async {
      await pump(tester);
      metronome.setParts(four());
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.cardKey(0)));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(PartsPage.cardKey(1)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      // Card 1 is the open one: its body sits right under its header.
      final body = find.byKey(PartsPage.duplicateKey);
      expect(body, findsOneWidget);
      expect(
        tester.getTopLeft(body).dy,
        greaterThan(tester.getTopLeft(find.byKey(PartsPage.cardKey(1))).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new part grows in', (tester) async {
      await pump(tester);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.addKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final card = find.byKey(PartsPage.cardKey(1));
      final early = tester
          .getSize(
            find.ancestor(of: card, matching: find.byType(ClipRect)).first,
          )
          .height;
      await tester.pumpAndSettle();
      final full = tester
          .getSize(
            find.ancestor(of: card, matching: find.byType(SwipeRow)).first,
          )
          .height;
      expect(early, lessThan(full));
    });

    testWidgets('Remove animations: a card opens at once', (tester) async {
      await pump(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      metronome.setParts(four());
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.cardKey(0)));
      await tester.pump();
      await tester.pump();
      final body = tester.getSize(find.byKey(PartsPage.duplicateKey));
      expect(body.height, greaterThan(0));
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.byKey(PartsPage.duplicateKey),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 1);
    });
  });
}
