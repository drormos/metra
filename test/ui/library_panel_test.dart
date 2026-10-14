import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/setlist_picker.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_panel_test');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// [panel]: also open the songs sheet (the stand-in for the picker),
  /// through "Choose a setlist", so one setlist ("Setup") exists.
  Future<void> pumpScreen(WidgetTester tester, {bool panel = false}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
    if (panel) {
      library.addSetlist('Setup');
      await tester.pump();
      await tester.tap(find.text('Choose a setlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song library'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('save the current tempo as a song, then load it', (tester) async {
    await pumpScreen(tester, panel: true);
    metronome.setBpm(87);
    await tester.tap(find.text('Save current as song'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Ballad');

    expect(find.widgetWithText(ListTile, 'Ballad'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data,
      'Ballad',
    );
    expect(find.text('87 BPM · 4/4'), findsOneWidget);

    metronome.setBpm(140);
    await tester.tap(find.widgetWithText(ListTile, 'Ballad'));
    await tester.pump();
    expect(metronome.bpm, 87);
  });

  testWidgets('empty name is not saved', (tester) async {
    await pumpScreen(tester, panel: true);
    await tester.tap(find.text('Save current as song'));
    await tester.pumpAndSettle();
    await enterName(tester, '   ');
    expect(library.songs, isEmpty);
  });

  testWidgets('create a setlist and add a song to it', (tester) async {
    await pumpScreen(tester, panel: true);
    library.addSong(
      name: 'Opener',
      bpm: 150,
      pattern: const MetronomePattern.standard(),
    );
    await tester.tap(find.byTooltip('Setlist actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New setlist').last); // the panel's menu
    await tester.pumpAndSettle();
    await enterName(tester, 'Friday');

    // The new setlist is selected and empty.
    expect(library.activeSetlist?.name, 'Friday');
    expect(find.textContaining('This setlist is empty'), findsOneWidget);

    library.setActiveSetlist(null);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Song actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to setlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friday').last); // the dialog's option
    await tester.pumpAndSettle();
    expect(
      library.setlists.firstWhere((l) => l.name == 'Friday').songIds,
      hasLength(1),
    );
  });

  testWidgets('delete a song after confirming', (tester) async {
    await pumpScreen(tester, panel: true);
    library.addSong(
      name: 'Gone',
      bpm: 100,
      pattern: const MetronomePattern.standard(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Song actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.songs, hasLength(1));

    await tester.tap(find.byTooltip('Song actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete song'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(library.songs, isEmpty);
    expect(find.text('Gone'), findsNothing);
  });

  group('setlist group', () {
    Future<void> withSet(WidgetTester tester) async {
      await pumpScreen(tester);
      final gig = library.addSetlist('Friday set');
      for (final (name, bpm) in [('One', 100), ('Two', 110), ('Three', 120)]) {
        final song = library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        );
        library.addToSetlist(gig.id, song.id);
      }
      library.setActiveSetlist(gig.id);
      await tester.pump();
    }

    String title(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data!;

    bool enabled(WidgetTester tester, Key key) =>
        tester.widget<FilledButton>(find.byKey(key)).onPressed != null;

    Rect groupRect(WidgetTester tester) =>
        tester.getRect(find.byType(SetlistGroup));

    testWidgets('Free play with no setlists: create your first', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Free play'), findsOneWidget);
      expect(find.text('Create your first setlist'), findsOneWidget);
      expect(find.byTooltip('New setlist'), findsNothing);
    });

    testWidgets('Free play with setlists: choose one, or + for new', (
      tester,
    ) async {
      await pumpScreen(tester);
      library.addSetlist('Friday set');
      await tester.pump();
      expect(find.text('Choose a setlist'), findsOneWidget);
      expect(find.byTooltip('New setlist'), findsOneWidget);
      await tester.tap(find.text('Choose a setlist'));
      await tester.pumpAndSettle();
      expect(find.text('What to play'), findsOneWidget);
    });

    testWidgets('+ names and loads a new setlist', (tester) async {
      await pumpScreen(tester);
      library.addSetlist('Old');
      await tester.pump();
      await tester.tap(find.byTooltip('New setlist'));
      await tester.pumpAndSettle();
      await enterName(tester, 'Saturday');
      expect(library.activeSetlist?.name, 'Saturday');
      expect(find.text('0 of 0'), findsNothing);
      expect(find.text('– of 0'), findsOneWidget);
    });

    testWidgets('setlist mode: header, position, neighbours', (tester) async {
      await withSet(tester);
      expect(find.text('Friday set'), findsOneWidget);
      expect(find.text('– of 3'), findsOneWidget);
      expect(enabled(tester, SetlistGroup.previousKey), isFalse);
      expect(find.text('One'), findsOneWidget, reason: 'next = first song');

      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(title(tester), 'One');
      expect(metronome.bpm, 100);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      expect(find.text('110 bpm'), findsOneWidget);

      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(title(tester), 'Three');
      expect(enabled(tester, SetlistGroup.nextKey), isFalse);

      await tester.tap(find.byKey(SetlistGroup.previousKey));
      await tester.pump();
      expect(title(tester), 'Two');
      expect(find.bySemanticsLabel('Previous song: One'), findsOneWidget);
    });

    testWidgets('the header opens the picker', (tester) async {
      await withSet(tester);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SetlistPicker.setNameKey), findsOneWidget);
      expect(find.text('3 songs'), findsOneWidget);
    });

    testWidgets('same size and position in both modes', (tester) async {
      await withSet(tester);
      final inSet = groupRect(tester);
      library.setActiveSetlist(null);
      await tester.pump();
      expect(groupRect(tester), inSet);
    });

    testWidgets('pedal keys: Page Down / Right next, Page Up / Left back', (
      tester,
    ) async {
      await withSet(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(library.currentSong?.name, 'Two');
      await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
      await tester.pump();
      expect(library.currentSong?.name, 'One');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(library.currentSong?.name, 'One');
    });
  });

  for (final size in [const Size(360, 640), const Size(320, 568)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} phone '
        'with songs', (tester) async {
      await pumpScreen(tester);
      tester.view.physicalSize = size;
      library.addSong(
        name: 'A rather long song title that has to ellipsize',
        bpm: 100,
        pattern: const MetronomePattern.standard(),
      );
      library.nextSong(metronome);
      await tester.pumpAndSettle();
      // Layout overflow would have thrown during pump.
      expect(tester.takeException(), isNull);
      expect(find.byKey(MetronomeScreen.bpmKey), findsOneWidget);
    });
  }
}
