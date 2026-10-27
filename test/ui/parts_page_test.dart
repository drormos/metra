import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/count_in.dart';
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
import 'button_text.dart';

import 'package:metra/src/ui/theme.dart';

import 'test_theme.dart';

/// The parts page (ui-spec.md "Song parts" → "The parts page").
void main() {
  late Directory dir;
  late FakeClickOutput output;
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
  Future<void> tapIn(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  // "When the song ends" → [end].
  Future<void> pick(SongEnd end, WidgetTester tester) async {
    await tapIn(tester, find.byKey(PartsPage.endKey));
    await tapIn(
      tester,
      find.byWidgetPredicate(
        (w) => w is CheckedPopupMenuItem<SongEnd> && w.value == end,
      ),
    );
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
      expect(summary(tester), '1 part · 1 bar · ≈ 0:02, then loops Part 1');
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
    // The first add on a plain song: both parts 8 bars.
    expect(parts().map((p) => p.bars), [8, 8]);
    expect(summary(tester), '2 parts · 16 bars · ≈ 0:32, then loops Part 2');
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

  testWidgets('top: the name shrinks to fit (down to 22px) before "…"; the '
      'summary has its own full-width line under the bar', (tester) async {
    await pump(tester);
    await openPage(tester);
    final summaryBox = tester.getRect(find.byKey(PartsPage.summaryKey));
    final name = tester.getRect(find.byKey(PartsPage.nameKey));
    expect(summaryBox.top, greaterThanOrEqualTo(name.bottom));
    // With Save / Discard showing, the summary still isn't cut.
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(
      tester.getSize(find.byKey(PartsPage.summaryKey)).width,
      greaterThan(300),
    );
    expect(summary(tester), endsWith('then loops Part 2'));
    double size() =>
        tester.widget<Text>(find.byKey(PartsPage.titleKey)).style!.fontSize!;
    library.renameSong(library.currentSong!.id, 'Go');
    await tester.pump();
    expect(size(), 28);
    library.renameSong(library.currentSong!.id, 'Dead Weight');
    await tester.pump();
    expect(size(), lessThan(28));
    expect(size(), greaterThanOrEqualTo(22));
  });

  testWidgets('opens while the song is playing (long-press the title)', (
    tester,
  ) async {
    await pump(tester);
    metronome.setParts([
      for (final id in ['a', 'b'])
        SongPart.steady(
          id: id,
          name: id,
          bars: 2,
          bpm: 120,
          pattern: const MetronomePattern.standard(),
        ),
    ]);
    await metronome.play();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(find.byKey(MetronomeScreen.titleBlockKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(PartsPage), findsOneWidget);
    metronome.stop();
    await tester.pumpAndSettle();
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

  testWidgets('"At the end": a dropdown on the label\'s line, '
      'the current choice ticked; adding or removing parts never changes '
      'it; Loop last part marks the last block', (tester) async {
    await pump(tester);
    await openPage(tester);
    // A plain song loops its bar: the choice is there with one part too.
    expect(metronome.songEnd, SongEnd.loopLastPart);
    expect(find.byKey(PartsPage.loopIconKey), findsOneWidget);
    final label = tester.getRect(find.text('At the end'));
    final menu = tester.getRect(find.byKey(PartsPage.endKey));
    expect(menu.center.dy, closeTo(label.center.dy, 2), reason: 'one row');
    expect(menu.left, greaterThanOrEqualTo(label.right));
    expect(
      find.descendant(
        of: find.byKey(PartsPage.endKey),
        matching: find.text('Loop last part'),
      ),
      findsOneWidget,
    );
    // The menu: all three, the current one ticked; picking closes it.
    await tapIn(tester, find.byKey(PartsPage.endKey));
    final items = tester.widgetList<CheckedPopupMenuItem<SongEnd>>(
      find.byType(CheckedPopupMenuItem<SongEnd>),
    );
    expect(
      [for (final i in items) (i.value, i.checked)],
      [
        (SongEnd.stop, false),
        (SongEnd.loopSong, false),
        (SongEnd.loopLastPart, true),
      ],
    );
    await tapIn(tester, find.text('Stop').last);
    expect(metronome.songEnd, SongEnd.stop);
    expect(find.byType(CheckedPopupMenuItem<SongEnd>), findsNothing);
    await pick(SongEnd.loopLastPart, tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    expect(metronome.songEnd, SongEnd.loopLastPart);
    await tester.dragUntilVisible(
      find.byKey(PartsPage.endKey),
      find.byType(ReorderableListView),
      const Offset(0, -100),
    );
    await pick(SongEnd.loopSong, tester);
    expect(metronome.songEnd, SongEnd.loopSong);
    expect(find.byKey(PartsPage.loopIconKey), findsNothing);
    expect(summary(tester), '2 parts · 16 bars · ≈ 0:32');
    await pick(SongEnd.stop, tester);
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

  testWidgets('"Gradual tempo change": Starts at keeps the tempo, Ends at '
      '+10; ✕ goes back to one tempo; the card never changes shape', (
    tester,
  ) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey)); // Part 2, at 120
    // From the card's header: the list may scroll, the card mustn't change.
    double top(Key key) =>
        tester.getTopLeft(find.byKey(key)).dy -
        tester.getTopLeft(find.byKey(PartsPage.cardKey(1))).dy;
    final steadyRows = (
      top(ValueStepper.plusKey('BPM')),
      top(PartsPage.gradualKey),
      top(PartsPage.rhythmKey),
    );
    expect(find.text('Gradual tempo change'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    await tapIn(tester, find.byKey(PartsPage.gradualKey));
    expect((parts()[1].tempoStart, parts()[1].tempoEnd), (120, 130));
    expect(find.text('Starts at'), findsOneWidget);
    expect(find.text('Ends at'), findsOneWidget);
    expect(find.text('BPM'), findsNothing);
    expect(top(ValueStepper.plusKey('Starts at')), steadyRows.$1);
    expect(top(PartsPage.rhythmKey), steadyRows.$3, reason: 'same height');
    // ✕: 40px wide, before −.
    final clear = tester.getRect(find.byKey(PartsPage.steadyKey));
    final minus = tester.getRect(find.byKey(ValueStepper.minusKey('Ends at')));
    final drawn = tester.getRect(
      find.descendant(
        of: find.byKey(PartsPage.steadyKey),
        matching: find.byType(Material),
      ),
    );
    expect(drawn.size, const Size(40, 40));
    expect(clear.size, const Size(48, 48), reason: 'touch target');
    expect(minus.width, 48);
    // Cells edge to edge: ✕ | − | value (92) | +, each button drawn 40px
    // in the sheet's button color.
    final plus = tester.getRect(find.byKey(ValueStepper.plusKey('Ends at')));
    expect(minus.left, clear.right);
    expect(plus.left - minus.right, 92);
    final minusDrawn = tester.getRect(
      find.descendant(
        of: find.byKey(ValueStepper.minusKey('Ends at')),
        matching: find.byType(Material),
      ),
    );
    expect(minusDrawn.size, const Size(40, 40));
    expect(
      tester
          .widget<Material>(
            find.descendant(
              of: find.byKey(ValueStepper.minusKey('Ends at')),
              matching: find.byType(Material),
            ),
          )
          .color,
      MetraColors.stageBlack.surfaceOnSheet,
    );
    expect(drawn.right, lessThan(minus.left));
    // Its label stays one line beside the ✕.
    expect(
      tester.getSize(find.text('Ends at')).height,
      tester.getSize(find.text('Starts at')).height,
    );
    // "120 → 130" on the card.
    expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    await tapIn(tester, find.byKey(ValueStepper.plusKey('Ends at')));
    expect(parts()[1].tempoEnd, 131);
    await tapIn(tester, find.byKey(ValueStepper.plusKey('Starts at')));
    expect((parts()[1].tempoStart, parts()[1].tempoEnd), (121, 131));
    await tapIn(tester, find.byKey(PartsPage.steadyKey));
    expect((parts()[1].tempoStart, parts()[1].tempoEnd), (121, 121));
    expect(find.text('BPM'), findsOneWidget);
    expect(top(PartsPage.gradualKey), steadyRows.$2);
    expect(top(PartsPage.rhythmKey), steadyRows.$3);
  });

  testWidgets('Ends at brought back to Starts at stays while the card is '
      'open; reopened, it\'s steady with the button again', (tester) async {
    await pump(tester);
    await openPage(tester);
    await tapIn(tester, find.byKey(PartsPage.addKey));
    await tapIn(tester, find.byKey(PartsPage.gradualKey));
    for (var i = 0; i < 10; i++) {
      await tapIn(tester, find.byKey(ValueStepper.minusKey('Ends at')));
    }
    expect(parts()[1].gradual, isFalse, reason: 'stored as steady');
    expect(find.text('Ends at'), findsOneWidget);
    await tapIn(tester, find.byKey(PartsPage.cardKey(1))); // close
    await tapIn(tester, find.byKey(PartsPage.cardKey(1))); // reopen
    expect(find.text('Ends at'), findsNothing);
    expect(find.byKey(PartsPage.gradualKey), findsOneWidget);
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
      final bpm = ValueStepper.plusKey('BPM');
      expect(y(PartsPage.partNameKey), lessThan(y(bpm)));
      expect(y(bpm), lessThan(y(PartsPage.gradualKey)));
      expect(y(PartsPage.gradualKey), lessThan(y(length)));
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

    testWidgets('only a 1-bar single part gets the 8-bar first add; a '
        'single part of another length is copied as it is', (tester) async {
      await pump(tester);
      metronome.setParts([part('Verse', 4, 120, 120)]);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.addKey));
      expect(parts().map((p) => p.bars), [4, 4]);
      await tapIn(tester, find.byKey(PartsPage.addKey));
      expect(parts().map((p) => p.bars), [4, 4, 4]);
    });

    testWidgets('a gradual change keeps the start the user set (it never '
        'moves to the previous part\'s end)', (tester) async {
      await pump(tester);
      metronome.setParts([
        part('Intro', 4, 100, 140),
        part('Verse', 8, 120, 120),
      ]);
      await openPage(tester);
      await tapIn(tester, find.byKey(PartsPage.cardKey(1)));
      await tapIn(tester, find.byKey(PartsPage.gradualKey));
      expect((parts()[1].tempoStart, parts()[1].tempoEnd), (120, 130));
    });
  });

  group('the playing card fills like a progress bar', () {
    // The engine clock and the frames together, to [ms].
    Future<void> runTo(WidgetTester tester, int ms) async {
      while (output.time < Duration(milliseconds: ms)) {
        output.time += const Duration(milliseconds: 20);
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    double fill(WidgetTester tester, int i) {
      final painter = tester
          .widget<CustomPaint>(find.byKey(PartsPage.fillKey(i)))
          .painter;
      return painter == null ? -1 : (painter as dynamic).progress.value;
    }

    bool stripWhite(WidgetTester tester, int i) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(PartsPage.stripKey(i)),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration! as BoxDecoration).color ==
          MetraColors.stageBlack.text;
    }

    // a: 1 bar, b: 2 bars, both 4/4 at 120 (a bar is 2 s); b loops.
    List<SongPart> two() => [
      for (final (id, bars) in [('a', 1), ('b', 2)])
        SongPart.steady(
          id: id,
          name: id,
          bars: bars,
          bpm: 120,
          pattern: const MetronomePattern.standard(),
        ),
    ];

    testWidgets('across each part from empty, again on every loop; only '
        'the header, and the card isn\'t rebuilt as it fills', (tester) async {
      await pump(tester);
      metronome.setParts(two(), end: SongEnd.loopLastPart);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.playKey)); // beat 1 at ~1120
      await tester.pump();
      await runTo(tester, 2120); // half of a
      expect(fill(tester, 0), closeTo(0.5, 0.05));
      expect(fill(tester, 1), -1, reason: 'not playing');
      final card = tester.widget(find.byKey(PartsPage.cardKey(0)));
      await runTo(tester, 2600);
      expect(fill(tester, 0), closeTo(0.74, 0.05));
      expect(
        identical(tester.widget(find.byKey(PartsPage.cardKey(0))), card),
        isTrue,
        reason: 'repaint only',
      );
      // Only the 60px header fills.
      expect(tester.getSize(find.byKey(PartsPage.fillKey(0))).height, 60);
      // b from 3120 (2 bars, 4 s): half its first bar, then half of all.
      await runTo(tester, 4120);
      expect(fill(tester, 0), -1);
      // The strip follows the music: b's block is the white one.
      expect([stripWhite(tester, 0), stripWhite(tester, 1)], [false, true]);
      expect(fill(tester, 1), closeTo(0.25, 0.05));
      await runTo(tester, 5120);
      expect(fill(tester, 1), closeTo(0.5, 0.05));
      await runTo(tester, 8120); // b again from 7120: half its first bar
      expect(fill(tester, 1), closeTo(0.25, 0.05));
      metronome.stop();
      await tester.pump();
      expect(fill(tester, 1), -1);
      // Stopped, no card open: no block is white.
      expect([stripWhite(tester, 0), stripWhite(tester, 1)], [false, false]);
    });

    // The count-in tag's fill (0–1), its text, its width.
    double tagFill(WidgetTester tester) =>
        (tester.widget<ClipRect>(find.byKey(CountInTag.fillKey)).clipper!
                as dynamic)
            .progress
            .value;
    String tagText(WidgetTester tester) => tester
        .widget<Text>(
          find
              .descendant(
                of: find.byKey(PartsPage.countInTagKey),
                matching: find.byType(Text),
              )
              .first,
        )
        .data!;
    double tagWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(PartsPage.countInTagKey)).width;

    testWidgets('a count-in: the summary line becomes a tag that fills across '
        'it, timed to the clicks, at a fixed width; the Stop button counts '
        'too; nothing moves; the cards and their fill wait for the song', (
      tester,
    ) async {
      await pump(tester);
      metronome
        ..setCountIn(1)
        ..setParts(two(), end: SongEnd.loopLastPart);
      await openPage(tester);
      final subtitle = partLine(two().first);
      final summary = tester.widget<Text>(find.byKey(PartsPage.summaryKey));
      final stripRect = tester.getRect(find.byKey(PartsPage.stripKey(0)));
      final cardRect = tester.getRect(find.byKey(PartsPage.cardKey(0)));
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      expect(find.byKey(PartsPage.summaryKey), findsNothing);
      expect(tagText(tester), 'Count-in · 1 of 4', reason: 'at once');
      expect(tagFill(tester), 0, reason: 'before the first click');
      expect(tester.getSize(find.byKey(PartsPage.countInTagKey)).height, 24);
      final width = tagWidth(tester);
      expect(tester.getRect(find.byKey(PartsPage.stripKey(0))), stripRect);
      expect(tester.getRect(find.byKey(PartsPage.cardKey(0))), cardRect);
      expect(
        buttonText(tester, PartsPage.playKey),
        contains('Count-in 1 of 4'),
      );
      expect(
        find.descendant(
          of: find.byKey(PartsPage.cardKey(0)),
          matching: find.text(subtitle),
        ),
        findsOneWidget,
        reason: 'the card stays as it is',
      );
      // Count-in beats every 500 ms from 1120; a from 3120. The count
      // changes in place: no frame dims it, the width holds, the fill
      // only grows.
      await runTo(tester, 1200); // past the brighten into the count-in
      var last = tagFill(tester);
      while (output.time < const Duration(milliseconds: 3100)) {
        output.time += const Duration(milliseconds: 20);
        await tester.pump(const Duration(milliseconds: 20));
        final at = output.time;
        expect(
          find.ancestor(
            of: find.byKey(PartsPage.countInTagKey),
            matching: find.byType(Opacity),
          ),
          findsNothing,
          reason: 'dimmed at $at',
        );
        expect(tagWidth(tester), width, reason: 'width at $at');
        expect(tagFill(tester), greaterThanOrEqualTo(last));
        expect(tagFill(tester) - last, lessThan(0.02), reason: 'smooth');
        last = tagFill(tester);
        if (at == const Duration(milliseconds: 1700)) {
          expect(tagText(tester), 'Count-in · 2 of 4');
          expect(fill(tester, 0), 0);
        }
        if (at == const Duration(milliseconds: 2120)) {
          expect(tagFill(tester), closeTo(0.5, 0.02));
        }
      }
      expect(last, closeTo(1, 0.02));
      await runTo(tester, 3200);
      expect(find.byKey(PartsPage.countInTagKey), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(PartsPage.summaryKey)).data,
        summary.data,
      );
      expect(tester.getRect(find.byKey(PartsPage.cardKey(0))), cardRect);
      expect(fill(tester, 0), greaterThan(0));
      expect(buttonText(tester, PartsPage.playKey), 'Stop');
      metronome.stop();
      await tester.pump();
    });

    testWidgets('a 2-bar count-in is one slower fill; the text counts the '
        'beats of the bar', (tester) async {
      await pump(tester);
      metronome
        ..setCountIn(2)
        ..setParts(two(), end: SongEnd.loopLastPart);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await runTo(tester, 2120); // halfway through bar 1
      expect(tagFill(tester), closeTo(0.25, 0.02));
      await runTo(tester, 3140); // bar 2, beat 1
      expect(tagText(tester), 'Count-in · 1 of 4');
      expect(tagFill(tester), closeTo(0.5, 0.02));
      metronome.stop();
      await tester.pump();
    });

    testWidgets('"Remove animations": the tag fills a beat at a time', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pump(tester);
      metronome
        ..setCountIn(1)
        ..setParts(two(), end: SongEnd.loopLastPart);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await runTo(tester, 1140);
      expect(tagFill(tester), 0.25);
      await runTo(tester, 1600);
      expect(tagFill(tester), 0.25, reason: 'holds through the beat');
      await runTo(tester, 1640);
      expect(tagFill(tester), 0.5);
      metronome.stop();
      await tester.pump();
    });

    // Every frame from Start until [ms]: the fill on [card] starts at 0
    // with the first audible beat and grows in small steps, never jumping.
    Future<void> growsFromZero(WidgetTester tester, int card, int ms) async {
      var last = 0.0;
      var moved = false;
      while (output.time < Duration(milliseconds: ms)) {
        output.time += const Duration(milliseconds: 20);
        await tester.pump(const Duration(milliseconds: 20));
        final f = fill(tester, card);
        if (f < 0) continue; // not this card's part yet (count-in)
        if (!moved && f > 0) {
          expect(f, lessThan(0.02), reason: 'first frames: from 0');
          moved = true;
        }
        expect(f - last, lessThan(0.02), reason: 'no jump at $output.time');
        expect(f, greaterThanOrEqualTo(last));
        last = f;
      }
      expect(moved, isTrue);
    }

    testWidgets('from the first audible beat, never jumping: Start, with a '
        'count-in, Play from here, Stop then Start', (tester) async {
      await pump(tester);
      metronome.setParts(two(), end: SongEnd.loopLastPart);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await growsFromZero(tester, 0, 2600);
      // Stop, then Start again.
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await growsFromZero(tester, 0, 4600);
      metronome.stop();
      await tester.pump();
      // With a count-in.
      metronome.setCountIn(1);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await growsFromZero(tester, 0, 9000);
      metronome.stop();
      metronome.setCountIn(0);
      await tester.pump();
      // Play from here (part b's card).
      await tester.tap(find.byKey(PartsPage.cardKey(1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PartsPage.playFromKey));
      await tester.pump();
      await growsFromZero(tester, 1, 12000);
      metronome.stop();
      await tester.pump();
    });

    testWidgets('Remove animations: whole bars only', (tester) async {
      await pump(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      metronome.setParts(two().reversed.toList(), end: SongEnd.stop);
      await openPage(tester);
      await tester.tap(find.byKey(PartsPage.playKey));
      await tester.pump();
      await runTo(tester, 2120); // half of b's first bar
      expect(fill(tester, 0), 0);
      await runTo(tester, 4120); // half of its second
      expect(fill(tester, 0), 0.5);
      metronome.stop();
      await tester.pump();
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
