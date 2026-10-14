import 'dart:io';

import 'package:flutter/material.dart';
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

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_picker_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save started on the widget test's fake clock may still be
      // writing; a leftover temp folder is harmless.
    }
  });

  /// Main screen with "Friday set" (One 100, Two 110, Three 120 in 6/8)
  /// and an empty "Saturday set".
  Future<void> pumpWithSets(WidgetTester tester, {bool loaded = true}) async {
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
    final friday = library.addSetlist('Friday set');
    library.addSetlist('Saturday set');
    for (final (name, bpm) in [('One', 100), ('Two', 110), ('Three', 120)]) {
      final song = library.addSong(
        name: name,
        bpm: bpm,
        pattern: name == 'Three'
            ? MetronomePattern.simple(
                beatsPerBar: 6,
                stepsPerBeat: 1,
                beatUnit: 8,
              )
            : const MetronomePattern.standard(),
      );
      library.addToSetlist(friday.id, song.id);
    }
    if (loaded) library.setActiveSetlist(friday.id);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  /// Waits out sheet animations. Not pumpAndSettle: while playing, the
  /// beat blocks repaint every frame, so nothing ever "settles".
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the settings sheet fits a small phone; vibrate toggles', (
    tester,
  ) async {
    await pumpWithSets(tester);
    tester.view.physicalSize = const Size(360, 640);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await settle(tester);
    await tester.ensureVisible(find.byKey(MetronomeScreen.vibrateKey));
    await tester.tap(find.byKey(MetronomeScreen.vibrateKey));
    await tester.pump();
    expect(library.vibrate, isFalse);
  });

  Future<void> openFromHeader(WidgetTester tester) async {
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await settle(tester);
  }

  testWidgets('songs view lists the set; tapping a row loads it and closes', (
    tester,
  ) async {
    await pumpWithSets(tester);
    await openFromHeader(tester);
    expect(find.text('3 songs'), findsOneWidget);
    expect(find.text('6/8'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-song-1')));
    await tester.pumpAndSettle();
    expect(library.currentSong?.name, 'Two');
    expect(metronome.bpm, 110);
    expect(find.text('What to play'), findsNothing);
    expect(
      find.byKey(SetlistPicker.setNameKey),
      findsNothing,
      reason: 'closed',
    );
  });

  testWidgets('the current song shows a play marker instead of its number', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.nextSong(metronome); // One
    await openFromHeader(tester);
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('picker-song-0')),
        matching: find.text('1'),
      ),
      findsNothing,
    );
  });

  testWidgets('set name opens What to play; another set loads at its first '
      'song and returns to songs', (tester) async {
    await pumpWithSets(tester);
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.setNameKey));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.text('Setlists'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'current set');

    await tester.tap(find.text('Saturday set'));
    await tester.pumpAndSettle();
    expect(library.activeSetlist?.name, 'Saturday set');
    expect(find.text('0 songs'), findsOneWidget, reason: 'back on songs view');

    await tester.tap(find.byKey(SetlistPicker.setNameKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Friday set'));
    await tester.pumpAndSettle();
    expect(library.currentSong?.name, 'One', reason: 'first song');
    expect(metronome.bpm, 100);
  });

  testWidgets('Free play changes only the mode and closes the sheet', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.nextSong(metronome);
    await metronome.play();
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.setNameKey));
    await settle(tester);
    await tester.tap(find.byKey(SetlistPicker.freePlayKey));
    await settle(tester);
    expect(library.activeSetlist, isNull);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 100);
    expect(find.text('Choose a setlist'), findsOneWidget);
    metronome.stop();
  });

  testWidgets('in Free play the picker opens on What to play, no back', (
    tester,
  ) async {
    await pumpWithSets(tester, loaded: false);
    await tester.tap(find.text('Choose a setlist'));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('New setlist'), findsOneWidget);
  });

  testWidgets('opening the picker never touches the click', (tester) async {
    await pumpWithSets(tester);
    await metronome.play();
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.setNameKey));
    await settle(tester);
    await tester.tapAt(const Offset(200, 20)); // outside: closes
    await settle(tester);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 120);
    metronome.stop();
  });
}
