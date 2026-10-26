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
      expect(summary(tester), '1 part · until you stop');
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
    bool shown(Key key) => tester
        .widget<Visibility>(
          find.ancestor(of: find.byKey(key), matching: find.byType(Visibility)),
        )
        .visible;
    expect(shown(PartsPage.saveKey), isFalse, reason: 'nothing unsaved');
    final title = tester.getTopLeft(find.byKey(PartsPage.nameKey));
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(names(), ['Part 1', 'Part 2']);
    expect(parts()[0].bars, PartsPage.defaultBars);
    expect(parts()[1].open, isTrue);
    expect(summary(tester), '2 parts · 8 bars, then until you stop');
    expect(find.byKey(PartsPage.lengthKindKey), findsOneWidget, reason: 'open');
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

  testWidgets('the last part only: Bars / Until you stop; open, no Gradual '
      'and no "When the song ends"', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey)); // Part 2, open
    expect(find.byKey(PartsPage.tempoKindKey), findsNothing);
    expect(find.byKey(PartsPage.endKey), findsNothing);
    await tapIn(tester, chip(PartsPage.lengthKindKey, 'Bars'));
    expect(parts()[1].bars, PartsPage.defaultBars);
    expect(find.byKey(PartsPage.tempoKindKey), findsOneWidget);
    await tester.dragUntilVisible(
      find.byKey(PartsPage.endKey),
      find.byType(ReorderableListView),
      const Offset(0, -100),
    );
    expect(find.byKey(PartsPage.endKey), findsOneWidget);
    await tapIn(tester, chip(PartsPage.endKey, 'Loop'));
    expect(metronome.songEnd, SongEnd.loop);
    expect(summary(tester), '2 parts · 16 bars · ≈ 0:32');
    // Part 1 isn't the last: no length chips on its card.
    await tester.dragUntilVisible(
      find.byKey(PartsPage.cardKey(0)),
      find.byType(ReorderableListView),
      const Offset(0, 100),
    );
    await tapIn(tester, find.byKey(PartsPage.cardKey(0)));
    expect(find.byKey(PartsPage.lengthKindKey), findsNothing);
  });

  testWidgets('Gradual: From the previous part\'s tempo, To this one\'s; the '
      'card reads 120 to 130', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, chip(PartsPage.lengthKindKey, 'Bars'));
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
    // The open part, no longer last, gets a length.
    expect(parts()[1].bars, PartsPage.defaultBars);
    expect(parts().any((p) => p.open), isFalse);
  });

  testWidgets('the strip opens the tapped part\'s card', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.stripKey(0)));
    expect(find.byKey(PartsPage.duplicateKey), findsOneWidget);
    expect(find.byKey(PartsPage.lengthKindKey), findsNothing, reason: 'part 1');
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
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
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
      await drag(tester, find.byKey(PartsPage.accentKey(0)), -80);
      expect(names(), ['Part 1', 'Part 2']);
      expect(find.byKey(PartsPage.duplicateKey), findsOneWidget);
      // Held on its header: closes, lifts, moves up one.
      await drag(tester, find.byKey(PartsPage.cardKey(1)), -68);
      expect(names(), ['Part 2', 'Part 1']);
      expect(find.byKey(PartsPage.duplicateKey), findsNothing);
    });

    testWidgets('open card: Name, then Tempo, then Length', (tester) async {
      await pump(tester);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.addKey));
      await tapIn(tester, chip(PartsPage.lengthKindKey, 'Bars'));
      double y(Key key) => tester.getTopLeft(find.byKey(key)).dy;
      expect(y(PartsPage.partNameKey), lessThan(y(PartsPage.tempoKindKey)));
      expect(y(PartsPage.tempoKindKey), lessThan(y(PartsPage.lengthKindKey)));
      expect(y(PartsPage.lengthKindKey), lessThan(y(PartsPage.rhythmKey)));
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
    SongPart part(String id, int? bars, int from, int to, [int beats = 4]) =>
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
}
