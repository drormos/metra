import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/library_pick.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/play_marker.dart';
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
    await tester.pump(const Duration(milliseconds: 350)); // lifts at 300 ms
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

  testWidgets('the picker has no "Song library" button', (tester) async {
    await pumpWithSets(tester);
    await openFromHeader(tester);
    expect(find.text('Song library'), findsNothing, reason: 'set page');
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await tester.pumpAndSettle();
    expect(find.text('Song library'), findsNothing, reason: 'What to play');
  });

  /// Opens the library (in Free play via "Songs", else via Settings) and
  /// taps [name]'s row.
  Future<void> loadFromLibrary(
    WidgetTester tester,
    String name, {
    bool freePlay = false,
  }) async {
    if (freePlay) {
      await tester.tap(find.byKey(SetlistGroup.songsKey));
    } else {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song library'));
    }
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
    expect(find.text('Edit'), findsNothing, reason: 'no edit mode');

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

  testWidgets('What to play: a tap loads the set at song 1 and closes; the '
      'pencil opens its page without loading', (tester) async {
    await pumpWithSets(tester);
    library.playSong(library.visibleSongs[1], metronome, index: 1); // Two
    await openFromHeader(tester);
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.text('Recently played'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing, reason: 'no loaded mark');

    final saturday = library.setlists.firstWhere(
      (l) => l.name == 'Saturday set',
    );
    await tester.tap(find.byKey(ValueKey('picker-set-edit-${saturday.id}')));
    await tester.pumpAndSettle();
    expect(find.text('0 songs'), findsOneWidget, reason: "Saturday's page");
    expect(library.activeSetlist?.name, 'Friday set', reason: 'not loaded');

    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await tester.pumpAndSettle();
    final friday = library.activeSetlist!;
    await tester.tap(find.byKey(ValueKey('picker-set-${friday.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistPicker), findsNothing, reason: 'closed');
    expect(library.currentSong?.name, 'One', reason: 'song 1, even reloaded');
    expect(metronome.bpm, 100);
  });

  for (final size in const [Size(400, 900), Size(360, 640)]) {
    testWidgets('What to play fits with the keyboard up '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      await pumpWithSets(tester, loaded: false);
      tester.view.physicalSize = size;
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(SetlistPicker),
          matching: find.byType(TextField),
        ),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('What to play lists recently played first and searches', (
    tester,
  ) async {
    await pumpWithSets(tester);
    library.loadSetlist(
      library.setlists.firstWhere((l) => l.name == 'Saturday set').id,
      metronome,
    );
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await settle(tester);
    await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
    await tester.pumpAndSettle();
    Finder inPicker(String text) => find.descendant(
      of: find.byType(SetlistPicker),
      matching: find.text(text),
    );
    final top = tester.getTopLeft(inPicker('Saturday set')).dy;
    expect(top, lessThan(tester.getTopLeft(inPicker('Friday set')).dy));
    await tester.enterText(
      find.descendant(
        of: find.byType(SetlistPicker),
        matching: find.byType(TextField),
      ),
      'fri',
    );
    await tester.pump();
    expect(inPicker('Saturday set'), findsNothing);
    expect(inPicker('Friday set'), findsOneWidget);
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
    expect(find.byTooltip('Back'), findsNothing, reason: 'the top level');
    // The loaded set's pencil: its page, nothing reloads.
    await tester.tap(
      find.byKey(ValueKey('picker-set-edit-${library.activeSetlist!.id}')),
    );
    await settle(tester);
    expect(find.byKey(SetlistPicker.backToSetlistsKey), findsOneWidget);
    expect(library.currentSong?.name, 'Two', reason: 'not reset to song 1');
    expect(metronome.bpm, 110);
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

  group('set page editing', () {
    List<String> names() => [
      for (final id
          in library.setlists.firstWhere((l) => l.name == 'Friday set').songIds)
        library.songById(id)!.name,
    ];

    testWidgets('Remove songs: circles, taps check, Remove with Undo', (
      tester,
    ) async {
      await pumpWithSets(tester);
      final friday = library.activeSetlist!;
      library.addToSetlist(friday.id, friday.songIds.first); // One again
      await openFromHeader(tester);
      await tester.tap(find.byKey(SetlistPicker.removeSongsKey));
      await tester.pump();
      expect(find.byType(MarkCircle), findsNWidgets(4));
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        find.byTooltip('Edit One'),
        findsNothing,
        reason: 'pencils hidden',
      );
      await tester.tap(find.byKey(const ValueKey('picker-song-0')));
      await tester.tap(find.byKey(const ValueKey('picker-song-2')));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(library.currentSong, isNull, reason: 'a tap checks, not loads');
      await tester.tap(find.byKey(SetlistPicker.removeKey));
      await tester.pump();
      expect(names(), ['Two', 'One'], reason: 'only those occurrences');
      expect(library.songs, hasLength(3), reason: 'songs stay in the library');
      expect(find.byType(MarkCircle), findsNothing, reason: 'marking ended');
      await tester.pump(const Duration(milliseconds: 500)); // bar slides in
      expect(find.text('2 removed'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(names(), ['One', 'Two', 'Three', 'One']);
    });

    testWidgets('Cancel ends marking; long-press and swipe do nothing else', (
      tester,
    ) async {
      await pumpWithSets(tester);
      await openFromHeader(tester);
      await tester.tap(find.byKey(SetlistPicker.removeSongsKey));
      await tester.pump();
      await tester.tap(find.byKey(SetlistPicker.cancelMarksKey));
      await tester.pump();
      expect(find.byType(MarkCircle), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('picker-song-1')));
      await settle(tester);
      expect(
        find.byType(MarkCircle),
        findsNothing,
        reason: 'no long-press mark',
      );
      await tester.drag(
        find.byKey(const ValueKey('picker-song-1')),
        const Offset(-600, 0),
      );
      await settle(tester);
      expect(names(), ['One', 'Two', 'Three'], reason: 'no swipe action');
    });

    testWidgets('Add songs uses pick mode', (tester) async {
      await pumpWithSets(tester);
      await openFromHeader(tester);
      await tester.tap(find.byKey(SetlistPicker.addSongsKey));
      await tester.pumpAndSettle();
      expect(find.text('Add to Friday set'), findsOneWidget);
      expect(find.text('Already in this set'), findsNWidgets(3));
      await tester.tap(
        find.descendant(
          of: find.byType(LibraryPick),
          matching: find.text('Two'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Add 1 song'));
      await tester.pumpAndSettle();
      expect(names(), ['One', 'Two', 'Three', 'Two']);
    });

    testWidgets('Rename turns the title into a field; Done saves', (
      tester,
    ) async {
      await pumpWithSets(tester);
      await openFromHeader(tester);
      await tester.scrollUntilVisible(find.byKey(SetlistPicker.renameKey), 100);
      await tester.tap(find.byKey(SetlistPicker.renameKey));
      await tester.pump();
      await tester.enterText(
        find.byKey(SetlistPicker.titleFieldKey),
        'saturday SET',
      );
      await tester.pump();
      expect(
        find.text('Another setlist already has this name'),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(SetlistPicker.titleFieldKey), 'Gig');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(library.activeSetlist?.name, 'Gig');
      expect(find.byKey(SetlistPicker.titleFieldKey), findsNothing);
    });

    testWidgets('Delete confirms, keeps the songs, returns to What to play', (
      tester,
    ) async {
      await pumpWithSets(tester);
      await openFromHeader(tester);
      await tester.scrollUntilVisible(find.byKey(SetlistPicker.deleteKey), 100);
      await tester.tap(find.byKey(SetlistPicker.deleteKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(library.setlists.map((l) => l.name), ['Saturday set']);
      expect(library.songs, hasLength(3));
      expect(find.text('What to play'), findsOneWidget);
    });

    testWidgets('New setlist: default name selected, Start with all songs', (
      tester,
    ) async {
      await pumpWithSets(tester, loaded: false);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await settle(tester);
      await tester.tap(find.byKey(SetlistPicker.newSetlistKey));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(SetlistPicker.titleFieldKey),
      );
      expect(field.controller!.text, 'Setlist 1');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(SetlistPicker.removeSongsKey))
            .onPressed,
        isNull,
        reason: 'nothing to remove yet',
      );
      await tester.tap(find.byKey(SetlistPicker.allSongsKey));
      await tester.pump();
      expect(find.text('3 songs'), findsOneWidget);
      await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
      await tester.pumpAndSettle();
      expect(
        library.setlists.map((l) => l.name),
        containsAll(['Friday set', 'Saturday set', 'Setlist 1']),
        reason: 'kept: it has songs',
      );
    });

    testWidgets('a new set left empty is discarded', (tester) async {
      await pumpWithSets(tester, loaded: false);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await settle(tester);
      await tester.tap(find.byKey(SetlistPicker.newSetlistKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
      await tester.pumpAndSettle();
      expect(library.setlists, hasLength(2));
    });

    testWidgets("a row on another set's page loads that set and song", (
      tester,
    ) async {
      await pumpWithSets(tester, loaded: false);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await settle(tester);
      final friday = library.setlists.firstWhere((l) => l.name == 'Friday set');
      await tester.tap(find.byKey(ValueKey('picker-set-edit-${friday.id}')));
      await settle(tester);
      expect(library.activeSetlist, isNull, reason: 'the pencil loads nothing');
      await tester.tap(find.byKey(const ValueKey('picker-song-2')));
      await settle(tester);
      expect(library.activeSetlist?.name, 'Friday set');
      expect(library.currentSong?.name, 'Three');
      expect(find.byType(SetlistPicker), findsNothing);
    });
  });

  group('What to play: deleting sets', () {
    Future<void> openWhatToPlay(WidgetTester tester) async {
      await openFromHeader(tester);
      await tester.tap(find.byKey(SetlistPicker.backToSetlistsKey));
      await settle(tester); // not pumpAndSettle: the click may be playing
    }

    Finder dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(label),
    );

    String idOf(String name) =>
        library.setlists.firstWhere((l) => l.name == name).id;

    testWidgets('Delete setlists: taps check; Delete asks, then deletes; the '
        'loaded set going leaves Free play and the click as it was', (
      tester,
    ) async {
      await pumpWithSets(tester);
      library.playSong(library.visibleSongs[1], metronome, index: 1); // Two
      await metronome.play();
      await openWhatToPlay(tester);
      await tester.tap(find.byKey(SetlistPicker.deleteSetsKey));
      await tester.pump();
      expect(find.byType(MarkCircle), findsNWidgets(2));
      await tester.tap(
        find.byKey(ValueKey('picker-set-${idOf('Friday set')}')),
      );
      await tester.tap(
        find.byKey(ValueKey('picker-set-${idOf('Saturday set')}')),
      );
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(library.setlists, hasLength(2), reason: 'a tap checks, not loads');
      await tester.tap(find.byKey(SetlistPicker.deleteMarkedKey));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Delete 2 setlists? The songs stay in your library.'),
        findsOneWidget,
      );
      await tester.tap(dialogButton('Delete'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(library.setlists, isEmpty);
      expect(library.songs, hasLength(3));
      expect(library.activeSetlist, isNull);
      expect(library.singleSong, isFalse, reason: 'Free play');
      expect(metronome.isPlaying, isTrue);
      expect(metronome.bpm, 110);
      metronome.stop();
      await tester.pump();
    });

    testWidgets('long-press and swipe do nothing in What to play', (
      tester,
    ) async {
      await pumpWithSets(tester);
      await openWhatToPlay(tester);
      final row = find.byKey(ValueKey('picker-set-${idOf('Saturday set')}'));
      await tester.longPress(row);
      await tester.pump();
      expect(find.byType(MarkCircle), findsNothing);
      await tester.drag(row, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(library.setlists, hasLength(2));
    });
  });
}
