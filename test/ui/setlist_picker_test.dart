import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/setlist_picker.dart';
import 'package:metra/src/ui/song_editor.dart';
import 'package:metra/src/ui/song_library.dart';

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

  Future<void> openFromHeader(WidgetTester tester) async {
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await settle(tester);
  }

  testWidgets('the title is not a control', (tester) async {
    await pumpWithSets(tester);
    library.playSong(library.visibleSongs[1], metronome, index: 1);
    await tester.pump();
    await tester.tap(find.byKey(MetronomeScreen.titleKey));
    await tester.pumpAndSettle();
    expect(find.byType(SongEditor), findsNothing);
  });

  for (final stopFirst in [false, true]) {
    testWidgets('leaving a preview resumes the main click (stop: $stopFirst)', (
      tester,
    ) async {
      await pumpWithSets(tester);
      library.playSong(library.visibleSongs[0], metronome, index: 0);
      await metronome.play();
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('picker-edit-0')));
      await settle(tester);
      await tester.tap(find.byKey(SongEditor.previewKey));
      await tester.pump();
      if (stopFirst) {
        await tester.tap(find.byKey(SongEditor.previewKey));
        await tester.pump();
        expect(metronome.isPlaying, isTrue, reason: 'Stop brings it back');
        expect(metronome.bpm, 100);
        expect(find.text('Preview'), findsOneWidget);
      }
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.byType(SongEditor), findsNothing);
      expect(metronome.isPlaying, isTrue);
      metronome.stop();
      await tester.pump();
    });
  }

  testWidgets('main-screen changes show Revert and Save to song', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.playSong(library.visibleSongs[0], metronome, index: 0);
    await tester.pump();
    expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
    await tester.tap(find.text('+1'));
    await tester.pump();
    expect(find.byKey(MetronomeScreen.tempoNameKey), findsNothing);
    await tester.tap(find.byKey(MetronomeScreen.saveToSongKey));
    await tester.pump();
    expect(library.currentSong!.bpm, 101);
    expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
    await tester.tap(find.text('+5'));
    await tester.pump();
    await tester.tap(find.byKey(MetronomeScreen.revertKey));
    await tester.pump();
    expect(metronome.bpm, 101);
    expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
  });

  testWidgets('long-press and drag reorders the set; a tap still loads', (
    tester,
  ) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpWithSets(tester);
    await openFromHeader(tester);
    final ids = [...library.activeSetlist!.songIds];
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('picker-song-0'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: 'lifted');
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, 25)); // one 60px row down
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await settle(tester);
    expect(library.activeSetlist!.songIds, [ids[1], ids[0], ids[2]]);
    expect(library.currentSong, isNull, reason: 'a drag loads nothing');
    expect(find.byType(SetlistPicker), findsOneWidget, reason: 'still open');
    await tester.tap(find.byKey(const ValueKey('picker-song-0')));
    await settle(tester);
    expect(library.currentSong!.id, ids[1]);
  });

  testWidgets('"Song library" opens the song library', (tester) async {
    await pumpWithSets(tester);
    await openFromHeader(tester);
    await tester.tap(find.text('Song library'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsOneWidget);
  });

  /// Opens the library through the picker (in Free play via Setlists)
  /// and taps [name]'s row.
  Future<void> loadFromLibrary(
    WidgetTester tester,
    String name, {
    bool freePlay = false,
  }) async {
    await tester.tap(
      freePlay
          ? find.byKey(SetlistGroup.setlistsKey)
          : find.byKey(SetlistGroup.headerKey),
    );
    await settle(tester);
    await tester.tap(find.text('Song library'));
    await tester.pumpAndSettle();
    final song = library.songs.firstWhere((s) => s.name == name);
    await tester.tap(find.byKey(ValueKey('library-${song.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsNothing);
    expect(find.byType(SetlistPicker), findsNothing, reason: 'back to main');
  }

  testWidgets('from the library in Free play: Single song, titled', (
    tester,
  ) async {
    await pumpWithSets(tester, loaded: false);
    await loadFromLibrary(tester, 'Two', freePlay: true);
    expect(library.activeSetlist, isNull);
    expect(library.singleSong, isTrue);
    expect(find.text('Single song'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data,
      'Two',
    );
    expect(metronome.bpm, 110);
  });

  testWidgets('from the library with a set: Single song, the set unloaded', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.playSong(library.visibleSongs[0], metronome, index: 0);
    await tester.pump();
    await loadFromLibrary(tester, 'Two'); // a song that is in the set
    expect(library.activeSetlist, isNull);
    expect(library.singleSong, isTrue);
    expect(find.text('Single song'), findsOneWidget);
    expect(metronome.bpm, 110);
  });

  testWidgets('the pencil on a picker row edits that song', (tester) async {
    await pumpWithSets(tester);
    await openFromHeader(tester);
    await tester.tap(find.byKey(const ValueKey('picker-edit-2')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Three'), findsOneWidget);
    expect(library.currentSong, isNull, reason: 'opening loads nothing');
  });

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
      find.byKey(SetlistPicker.backToSetlistsKey),
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
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.text('Setlists'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget, reason: 'current set');

    await tester.tap(find.text('Saturday set'));
    await tester.pumpAndSettle();
    expect(library.activeSetlist?.name, 'Saturday set');
    expect(find.text('0 songs'), findsOneWidget, reason: 'back on songs view');

    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
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
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await settle(tester);
    await tester.tap(find.byKey(SetlistPicker.freePlayKey));
    await settle(tester);
    expect(library.activeSetlist, isNull);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 100);
    expect(find.byKey(SetlistGroup.setlistsKey), findsOneWidget);
    metronome.stop();
  });

  testWidgets('in Free play the picker opens on What to play, no back', (
    tester,
  ) async {
    await pumpWithSets(tester, loaded: false);
    await tester.tap(find.byKey(SetlistGroup.setlistsKey));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('New setlist'), findsOneWidget);
  });

  testWidgets('the songs view: "‹ Setlists" goes up, Free play detaches', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.playSong(library.visibleSongs[1], metronome, index: 1);
    await metronome.play();
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await settle(tester);
    expect(find.text('What to play'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    await tester.tap(find.byKey(FreePlayButton.buttonKey));
    await settle(tester);
    expect(find.byType(SetlistPicker), findsNothing, reason: 'closed');
    expect(library.activeSetlist, isNull);
    expect(library.currentSong, isNull);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 110, reason: 'the click carries on');
    metronome.stop();
    await tester.pump();
  });

  testWidgets('opening the picker never touches the click', (tester) async {
    await pumpWithSets(tester);
    await metronome.play();
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await settle(tester);
    await tester.tapAt(const Offset(200, 20)); // outside: closes
    await settle(tester);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 120);
    metronome.stop();
  });
}
