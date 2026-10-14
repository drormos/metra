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

void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_panel_test');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pumpScreen(WidgetTester tester, {required bool wide}) async {
    tester.view.physicalSize = wide
        ? const Size(1200, 900)
        : const Size(400, 900);
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
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField), name);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
  }

  testWidgets('wide screens show the panel beside the metronome', (
    tester,
  ) async {
    await pumpScreen(tester, wide: true);
    expect(find.text('Save current as song'), findsOneWidget);
    expect(find.byTooltip('Songs'), findsNothing);
  });

  testWidgets('narrow screens open the panel in a sheet', (tester) async {
    await pumpScreen(tester, wide: false);
    expect(find.text('Save current as song'), findsNothing);
    await tester.tap(find.byTooltip('Songs'));
    await tester.pumpAndSettle();
    expect(find.text('Save current as song'), findsOneWidget);
  });

  testWidgets('save the current tempo as a song, then load it', (tester) async {
    await pumpScreen(tester, wide: true);
    metronome.setBpm(87);
    await tester.tap(find.text('Save current as song'));
    await tester.pumpAndSettle();
    await enterName(tester, 'Ballad');

    expect(find.text('Ballad'), findsNWidgets(2)); // list + main screen
    expect(find.text('87 BPM · 4 beats'), findsOneWidget);

    metronome.setBpm(140);
    await tester.tap(find.widgetWithText(ListTile, 'Ballad'));
    await tester.pump();
    expect(metronome.bpm, 87);
  });

  testWidgets('empty name is not saved', (tester) async {
    await pumpScreen(tester, wide: true);
    await tester.tap(find.text('Save current as song'));
    await tester.pumpAndSettle();
    await enterName(tester, '   ');
    expect(library.songs, isEmpty);
  });

  testWidgets('create a setlist and add a song to it', (tester) async {
    await pumpScreen(tester, wide: true);
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
    expect(library.selectedSetlist?.name, 'Friday');
    expect(find.textContaining('This setlist is empty'), findsOneWidget);

    library.selectSetlist(null);
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
    await pumpScreen(tester, wide: true);
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
      await pumpScreen(tester, wide: false);
      for (final (name, bpm) in [('One', 100), ('Two', 110), ('Three', 120)]) {
        library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        );
      }
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
      await pumpScreen(tester, wide: false);
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
}
