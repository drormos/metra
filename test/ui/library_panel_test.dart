import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';

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

  /// [panel]: also open the songs sheet (the stand-in for the picker).
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
      await tester.tap(find.text('Songs & setlists'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('the songs button opens the panel in a sheet', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Save current as song'), findsNothing);
    await tester.tap(find.text('Songs & setlists'));
    await tester.pumpAndSettle();
    expect(find.text('Save current as song'), findsOneWidget);
  });

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
    await tester.tap(find.text('New setlist'));
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
    await tester.tap(find.text('Friday'));
    await tester.pumpAndSettle();
    expect(library.setlists.single.songIds, hasLength(1));
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

  group('next / previous song', () {
    Future<void> withSongs(WidgetTester tester) async {
      await pumpScreen(tester);
      final gig = library.addSetlist('Gig');
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

    String shownSong(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(MetronomeScreen.songNameKey)).data!;

    bool enabled(WidgetTester tester, String tooltip) =>
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip(tooltip),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed !=
        null;

    testWidgets('hidden until there are songs', (tester) async {
      await pumpScreen(tester);
      expect(find.byTooltip('Next song'), findsNothing);
    });

    testWidgets('buttons step through songs and disable at the ends', (
      tester,
    ) async {
      await withSongs(tester);
      expect(shownSong(tester), 'No song loaded');
      expect(enabled(tester, 'Previous song'), isFalse);

      await tester.tap(find.byTooltip('Next song'));
      await tester.pump();
      expect(shownSong(tester), 'One');
      expect(metronome.bpm, 100);

      await tester.tap(find.byTooltip('Next song'));
      await tester.tap(find.byTooltip('Next song'));
      await tester.pump();
      expect(shownSong(tester), 'Three');
      expect(enabled(tester, 'Next song'), isFalse);

      await tester.tap(find.byTooltip('Previous song'));
      await tester.pump();
      expect(shownSong(tester), 'Two');
    });

    testWidgets('pedal keys: Page Down / Right next, Page Up / Left back', (
      tester,
    ) async {
      await withSongs(tester);
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
