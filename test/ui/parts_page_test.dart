import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
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
      'change: Revert takes it back, Save stores it', (tester) async {
    await pump(tester);
    await openPage(tester);
    expect(find.byKey(PartsPage.revertKey), findsNothing);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(names(), ['Part 1', 'Part 2']);
    expect(parts()[0].bars, PartsPage.defaultBars);
    expect(parts()[1].open, isTrue);
    expect(summary(tester), '2 parts · 8 bars, then until you stop');
    expect(find.byKey(PartsPage.lengthKindKey), findsOneWidget, reason: 'open');
    expect(library.songChanged(metronome), isTrue);
    await tapIn(tester, find.byKey(PartsPage.revertKey));
    expect(names(), ['Part 1']);
    expect(metronome.parts, isNull, reason: 'a plain song again');
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.saveKey));
    expect(library.currentSong!.parts, hasLength(2));
    expect(library.songChanged(metronome), isFalse);
    expect(find.byKey(PartsPage.saveKey), findsNothing);
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
      'card reads "120 → 130"', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, chip(PartsPage.lengthKindKey, 'Bars'));
    await tapIn(tester, chip(PartsPage.tempoKindKey, 'Gradual'));
    expect((parts()[1].tempoStart, parts()[1].tempoEnd), (120, 130));
    expect(find.text('120 → 130'), findsOneWidget);
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
}
