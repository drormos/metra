import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/semantics.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/theme.dart';
import 'package:metra/src/ui/swipe_row.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

/// The "4/12 ⌄" panel (ui-spec.md "Set ⌄", "Sets view"): reorder, swipe
/// to remove with Undo, the one-time hint, and managing sets in place.
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;
  late List<String> haptics;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_set_panel'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  /// "Friday set" (One, Two, Three) loaded at Two, and "Saturday set"
  /// (Three); [hintSeen] skips the one-time hint.
  Future<void> pump(WidgetTester tester, {bool hintSeen = true}) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    haptics = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
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
    metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    final ids = [
      for (final (name, bpm) in [('One', 100), ('Two', 110), ('Three', 120)])
        library
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
            )
            .id,
    ];
    final friday = library.saveSetlist(name: 'Friday set', songIds: ids);
    library.saveSetlist(name: 'Saturday set', songIds: [ids[2]]);
    if (hintSeen) {
      library
        ..markSwipeHintSeen()
        ..markSongsHintSeen();
    }
    library
      ..loadSetlist(friday.id, metronome)
      ..nextSong(metronome); // Two, 2 of 3
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await tester.pumpAndSettle();
  }

  Finder inPanel(String text) =>
      find.descendant(of: find.byType(QuickPick), matching: find.text(text));
  Finder row(int i) => find.byKey(ValueKey('quick-set-song-$i'));
  List<String> friday() => [
    for (final id in library.setlists.first.songIds) library.songById(id)!.name,
  ];

  Future<void> swipe(WidgetTester tester, Finder finder, double dx) async {
    await tester.drag(finder, Offset(dx, 0));
    await tester.pumpAndSettle();
  }

  group('songs view', () {
    testWidgets('header: name, "Song 2 of 3", "Change set"; "+ Add songs ›"', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      expect(inPanel('Friday set'), findsOneWidget);
      expect(inPanel('Song 2 of 3'), findsOneWidget);
      expect(find.byKey(QuickPick.changeSetKey), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.addSongsKey));
      await tester.pumpAndSettle();
      expect(inPanel('Add to Friday set'), findsOneWidget);
      await tester.binding.handlePopRoute(); // Back: nothing added
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget, reason: 'back here');
      expect(find.byKey(QuickPick.changeSetKey), findsOneWidget);
    });

    testWidgets('long-press lifts and drags to reorder; saved, position '
        'follows, the panel stays', (tester) async {
      await pump(tester);
      await openPanel(tester);
      final gesture = await tester.startGesture(tester.getCenter(row(0)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      expect(haptics, ['HapticFeedbackType.mediumImpact']);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(friday(), ['Two', 'Three', 'One'], reason: 'One to the end');
      expect(library.currentSong?.name, 'Two', reason: 'the song is the same');
      expect(library.currentIndex, 0);
      expect(inPanel('Song 1 of 3'), findsOneWidget);
      expect(metronome.bpm, 110);
      expect(find.byType(QuickPick), findsOneWidget);
    });

    testWidgets('swipe removes from the set, with Undo; the position shifts', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      await swipe(tester, row(0), -60);
      expect(friday(), hasLength(3), reason: 'short of 40%: springs back');
      await swipe(tester, row(0), -250);
      expect(friday(), ['Two', 'Three']);
      expect(library.songs, hasLength(3), reason: 'never from the library');
      expect(library.currentSong?.name, 'Two');
      expect(inPanel('Song 1 of 2'), findsOneWidget);
      expect(inPanel('Removed from Friday set'), findsOneWidget);
      expect(haptics.last, 'HapticFeedbackType.lightImpact');
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect(friday(), ['One', 'Two', 'Three'], reason: 'back in place');
      expect(inPanel('Song 2 of 3'), findsOneWidget);
      expect(find.byKey(QuickPick.undoKey), findsNothing);
    });

    testWidgets('removing the playing song: the next takes its place; Undo '
        'makes it current again; Undo goes after ~6 s', (tester) async {
      await pump(tester);
      await openPanel(tester);
      // Stopped here (playing vs stopped is in the controller tests).
      await swipe(tester, row(1), 250);
      expect(friday(), ['One', 'Three'], reason: 'Two removed');
      expect(library.currentSong?.name, 'Three', reason: 'now in its place');
      expect(metronome.bpm, 120);
      expect(inPanel('Song 2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect(friday(), ['One', 'Two', 'Three']);
      expect(library.currentSong?.name, 'Two');
      expect(metronome.bpm, 110);
      await swipe(tester, row(2), 250);
      expect(friday(), ['One', 'Two']);
      expect(find.byKey(QuickPick.undoKey), findsOneWidget);
      await tester.pump(QuickPick.undoFor + const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(MetraMotion.leave * 2); // past the fade
      expect(find.byKey(QuickPick.undoKey), findsNothing);
    });

    testWidgets('an emptied set stays loaded: "No songs in this set" and '
        '"+ Add songs" in the context row', (tester) async {
      await pump(tester);
      for (var i = 0; i < 3; i++) {
        library.removeSongAt(
          library.activeSetlist!.id,
          library.currentIndex,
          metronome,
        );
      }
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Friday set');
      expect(find.text('No songs in this set'), findsOneWidget);
      await tester.tap(find.byKey(SetlistGroup.emptySetKey));
      await tester.pumpAndSettle();
      expect(inPanel('Add to Friday set'), findsOneWidget);
    });

    testWidgets('the one-time hint: a row slides to show "Remove", once', (
      tester,
    ) async {
      await pump(tester, hintSeen: false);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pump();
      await tester.pump(); // the hint starts
      await tester.pump(const Duration(milliseconds: 400)); // half way
      expect(inPanel('Remove'), findsOneWidget);
      expect(
        tester.getTopLeft(row(0)).dx,
        lessThan(tester.getTopLeft(row(2)).dx),
        reason: 'a row that is not playing slides',
      );
      await tester.pumpAndSettle();
      expect(inPanel('Remove'), findsNothing);
      expect(library.swipeHintSeen, isTrue);
      expect(haptics, isEmpty, reason: 'no haptic');
      // Then the line naming both gestures, for ~3 s.
      expect(
        inPanel('Hold a song to move it · Swipe to remove'),
        findsOneWidget,
      );
      await tester.pump(QuickPick.hintLineFor);
      await tester.pump();
      await tester.pump(MetraMotion.leave * 2); // past the fade
      expect(inPanel('Hold a song to move it · Swipe to remove'), findsNothing);
      // The sets view teaches its own, once.
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      expect(
        inPanel('Hold a set to rename it · Swipe to delete'),
        findsOneWidget,
      );
      expect(library.setsHintSeen, isTrue);
      await tester.pump(QuickPick.hintLineFor);
      await tester.pump();
      await tester.pump(MetraMotion.leave * 2); // past the fade
      await tester.tap(find.byKey(QuickPick.backKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(inPanel('Remove'), findsNothing, reason: 'never again');
    });
  });

  group('sets view', () {
    Future<void> openSets(WidgetTester tester) async {
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
    }

    Finder setRow(String name) => find.byKey(
      ValueKey(
        'quick-set-${library.setlists.firstWhere((l) => l.name == name).id}',
      ),
    );

    testWidgets('deleting the loaded set: the other loads at song 1, the '
        'sets view stays; Undo brings it back at the same song', (
      tester,
    ) async {
      await pump(tester);
      await openSets(tester);
      await swipe(tester, setRow('Friday set'), -250);
      expect(find.text('Delete Friday set?'), findsOneWidget);
      await tester.tap(find.byKey(deleteConfirmKey));
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Saturday set');
      expect(library.currentSong?.name, 'Three', reason: 'song 1');
      expect(
        find.byKey(QuickPick.newSetlistKey),
        findsOneWidget,
        reason: 'the sets view stays open',
      );
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Friday set');
      expect(library.currentSong?.name, 'Two');
    });

    testWidgets('another set: asks, Cancel or Delete, Undo in place', (
      tester,
    ) async {
      await pump(tester);
      await openSets(tester);
      final order = [for (final l in library.setlists) l.id];
      await swipe(tester, setRow('Saturday set'), -250);
      expect(find.text('Delete Saturday set?'), findsOneWidget);
      expect(find.text('Its 1 song stays in your library.'), findsOneWidget);
      await tester.tap(find.byKey(deleteCancelKey));
      await tester.pumpAndSettle();
      expect(library.setlists, hasLength(2), reason: 'Cancel: slides back');
      expect(setRow('Saturday set'), findsOneWidget);
      await swipe(tester, setRow('Saturday set'), -250);
      await tester.tap(find.byKey(deleteConfirmKey));
      await tester.pumpAndSettle();
      expect(library.setlists.map((l) => l.name), ['Friday set']);
      expect(library.songs, hasLength(3), reason: 'songs stay');
      expect(inPanel('Deleted set "Saturday set"'), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect([for (final l in library.setlists) l.id], order);
    });

    testWidgets('"+ New setlist ›": on top, being named; Done picks songs, '
        'then back here', (tester) async {
      await pump(tester);
      await openSets(tester);
      await tester.tap(find.byKey(QuickPick.newSetlistKey));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(QuickPick.renameFieldKey),
      );
      expect(field.controller!.text, 'Setlist 1');
      expect(field.controller!.selection.end, 'Setlist 1'.length);
      expect(
        tester.getTopLeft(find.byKey(QuickPick.renameFieldKey)).dy,
        lessThan(tester.getTopLeft(setRow('Friday set')).dy),
        reason: 'on top',
      );
      await tester.enterText(find.byKey(QuickPick.renameFieldKey), 'Gig');
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(inPanel('Add to Gig'), findsOneWidget, reason: 'the picker');
      await tester.tap(find.byKey(QuickPick.pickBackKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(QuickPick.newSetlistKey),
        findsOneWidget,
        reason: 'back to the sets view',
      );
      expect(inPanel('Gig'), findsOneWidget);
      expect(
        library.setlists.firstWhere((l) => l.name == 'Gig').songIds,
        isEmpty,
        reason: 'Back adds nothing',
      );
    });

    testWidgets('more than 8 sets: "Search setlists" filters; × clears', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 0; i < 8; i++) {
        library.addSetlist('Extra $i');
      }
      await openSets(tester);
      expect(find.byKey(QuickPick.setSearchKey), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'fri');
      await tester.pump();
      expect(inPanel('Friday set'), findsOneWidget);
      expect(inPanel('Saturday set'), findsNothing);
      await tester.tap(find.byKey(SearchField.clearKey));
      await tester.pump();
      expect(inPanel('Saturday set'), findsOneWidget);
    });
  });

  group('songs list', () {
    /// Single song on Two, then its "Songs ⌄".
    Future<void> openSongs(WidgetTester tester) async {
      library.playSingleSong(
        library.songs.firstWhere((s) => s.name == 'Two'),
        metronome,
      );
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
    }

    Finder songRow(String name) => find.byKey(
      ValueKey(
        'quick-song-${library.songs.firstWhere((s) => s.name == name).id}',
      ),
    );
    List<String> names(String set) => [
      for (final id
          in library.setlists.firstWhere((l) => l.name == set).songIds)
        library.songById(id)!.name,
    ];

    testWidgets('long-press renames in place; the row moves to its A–Z place', (
      tester,
    ) async {
      await pump(tester);
      await openSongs(tester);
      await tester.longPress(songRow('One'));
      await tester.pumpAndSettle();
      expect(haptics.last, 'HapticFeedbackType.mediumImpact');
      await tester.enterText(find.byKey(QuickPick.renameFieldKey), 'Zed');
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(library.songs.map((s) => s.name), contains('Zed'));
      final ys = [
        for (final n in ['Three', 'Two', 'Zed'])
          tester.getTopLeft(songRow(n)).dy,
      ];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'A–Z');
      await tester.longPress(songRow('Zed'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(QuickPick.renameFieldKey), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(songRow('Zed'), findsOneWidget, reason: 'empty keeps the name');
    });

    testWidgets('swipe asks before deleting (Cancel / Delete); Undo restores '
        'the song and its place in each set', (tester) async {
      await pump(tester);
      await openSongs(tester);
      await swipe(tester, songRow('Three'), -250);
      expect(find.text('Delete Three?'), findsOneWidget);
      expect(
        find.text('It will also be removed from Friday set and Saturday set.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(deleteCancelKey));
      await tester.pumpAndSettle();
      expect(library.songs, hasLength(3), reason: 'Cancel');
      expect(songRow('Three'), findsOneWidget, reason: 'slid back');
      await swipe(tester, songRow('Three'), 250);
      await tester.tap(find.byKey(deleteConfirmKey));
      await tester.pumpAndSettle();
      expect(library.songs.map((s) => s.name), isNot(contains('Three')));
      expect(names('Friday set'), ['One', 'Two']);
      expect(names('Saturday set'), isEmpty);
      expect(inPanel('Deleted "Three"'), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect(names('Friday set'), ['One', 'Two', 'Three']);
      expect(names('Saturday set'), ['Three']);
      expect(songRow('Three'), findsOneWidget);
    });

    testWidgets('deleting the loaded song: the previous A–Z loads (it was '
        'last); Undo makes it current again', (tester) async {
      await pump(tester);
      await openSongs(tester); // A–Z: One, Three, Two (loaded)
      await swipe(tester, songRow('Two'), -250);
      expect(find.text('Delete Two?'), findsOneWidget);
      await tester.tap(find.byKey(deleteConfirmKey));
      await tester.pumpAndSettle();
      expect(library.currentSong?.name, 'Three');
      expect(library.singleSong, isTrue, reason: 'never Free play');
      expect(metronome.bpm, 120);
      await tester.tap(find.byKey(QuickPick.undoKey));
      await tester.pumpAndSettle();
      expect(library.currentSong?.name, 'Two');
      expect(library.singleSong, isTrue);
    });

    testWidgets('a song in no set: the dialog has no second line', (
      tester,
    ) async {
      await pump(tester);
      library.addSong(
        name: 'Loose',
        bpm: 90,
        pattern: const MetronomePattern.standard(),
      );
      await openSongs(tester);
      await swipe(tester, songRow('Loose'), -250);
      expect(find.text('Delete Loose?'), findsOneWidget);
      expect(find.textContaining('removed from'), findsNothing);
      await tester.tap(find.byKey(deleteCancelKey));
      await tester.pumpAndSettle();
    });

    testWidgets('"+ New song ›": from the click as it is; Done loads it; '
        'cancel makes nothing', (tester) async {
      await pump(tester);
      await openSongs(tester);
      metronome
        ..setBpm(137)
        ..setPolyrhythm(3);
      await tester.tap(find.byKey(QuickPick.newSongKey));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(QuickPick.renameFieldKey))
            .controller!
            .text,
        'Song 1',
      );
      await tester.binding.handlePopRoute(); // cancel
      await tester.pumpAndSettle();
      expect(library.songs, hasLength(3), reason: 'nothing made');
      await tester.tap(find.byKey(QuickPick.newSongKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(QuickPick.renameFieldKey), 'Fresh');
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'closes');
      final song = library.currentSong!;
      expect(song.name, 'Fresh');
      expect(song.bpm, 137);
      expect(song.pattern.polyrhythm, 3);
      expect(library.singleSong, isTrue);
    });

    testWidgets('more than 8 songs: "Search songs" filters', (tester) async {
      await pump(tester);
      for (var i = 0; i < 7; i++) {
        library.addSong(
          name: 'Extra $i',
          bpm: 100,
          pattern: const MetronomePattern.standard(),
        );
      }
      await openSongs(tester);
      await tester.enterText(find.byType(TextField), 'thr');
      await tester.pump();
      expect(songRow('Three'), findsOneWidget);
      expect(songRow('One'), findsNothing);
    });

    testWidgets('its own one-time hint', (tester) async {
      await pump(tester, hintSeen: false);
      library.playSingleSong(
        library.songs.firstWhere((s) => s.name == 'Two'),
        metronome,
      );
      await tester.pump();
      Future<void> open() async {
        await tester.tap(find.byKey(SetlistGroup.songsKey));
        await tester.pump();
        await tester.pump(); // the hint starts
        await tester.pump(const Duration(milliseconds: 400));
      }

      await open();
      expect(inPanel('Delete song'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(library.songsHintSeen, isTrue);
      expect(library.swipeHintSeen, isFalse, reason: 'its own flag');
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      await open();
      expect(inPanel('Delete song'), findsNothing, reason: 'never again');
    });
  });

  group('long-press vs swipe', () {
    Future<void> openSets(WidgetTester tester) async {
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
    }

    Finder setRow(String name) => find.byKey(
      ValueKey(
        'quick-set-${library.setlists.firstWhere((l) => l.name == name).id}',
      ),
    );

    const hold = Duration(milliseconds: 450);

    testWidgets('under 32dp the row stays put and the long-press still fires', (
      tester,
    ) async {
      await pump(tester);
      await openSets(tester);
      final start = tester.getTopLeft(setRow('Saturday set'));
      final gesture = await tester.startGesture(
        tester.getCenter(setRow('Saturday set')),
      );
      await gesture.moveBy(const Offset(28, 0));
      await tester.pump();
      expect(tester.getTopLeft(setRow('Saturday set')), start);
      await tester.pump(hold);
      expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
      // Swiping is off for this touch now.
      await gesture.moveBy(const Offset(-250, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(deleteConfirmKey), findsNothing);
      expect(library.setlists, hasLength(2));
    });

    testWidgets('once a swipe starts, long-press is off', (tester) async {
      await pump(tester);
      await openSets(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(setRow('Saturday set')),
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(
        tester.getTopLeft(setRow('Saturday set')).dx,
        lessThan(tester.getTopLeft(setRow('Friday set')).dx),
        reason: 'swiping',
      );
      await tester.pump(hold);
      expect(find.byKey(QuickPick.renameFieldKey), findsNothing);
      await gesture.moveBy(const Offset(40, 0));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('mostly-vertical movement never swipes', (tester) async {
      await pump(tester);
      await openSets(tester);
      final start = tester.getTopLeft(setRow('Saturday set'));
      final gesture = await tester.startGesture(
        tester.getCenter(setRow('Saturday set')),
      );
      await gesture.moveBy(const Offset(-40, 25)); // |dx| < 2 × |dy|
      await tester.pump();
      expect(tester.getTopLeft(setRow('Saturday set')).dx, start.dx);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('vertical movement past the scroll slop scrolls and cancels '
        'both', (tester) async {
      await pump(tester);
      for (var i = 0; i < 12; i++) {
        library.addSetlist('Extra $i');
      }
      await openSets(tester);
      final row = setRow('Saturday set');
      final gesture = await tester.startGesture(tester.getCenter(row));
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump(hold);
      expect(find.byKey(QuickPick.renameFieldKey), findsNothing);
      await gesture.moveBy(const Offset(-200, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(deleteConfirmKey), findsNothing);
      expect(library.setlists, hasLength(14));
    });

    testWidgets('a set\'s songs: a slightly moving long-press still lifts the '
        'row', (tester) async {
      await pump(tester);
      await openPanel(tester);
      final gesture = await tester.startGesture(tester.getCenter(row(2)));
      await gesture.moveBy(const Offset(20, 4));
      await tester.pump(hold);
      expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: 'lifted');
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(friday(), ['Three', 'One', 'Two'], reason: 'moved, not removed');
    });
  });

  group('timings and never waiting', () {
    testWidgets('a set\'s song lifts after 200ms; rename waits 400ms', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      var gesture = await tester.startGesture(tester.getCenter(row(0)));
      await tester.pump(const Duration(milliseconds: 180));
      expect(haptics, isEmpty, reason: 'not yet');
      await tester.pump(const Duration(milliseconds: 30));
      expect(haptics, ['HapticFeedbackType.mediumImpact'], reason: 'lifted');
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      final set = find.byKey(ValueKey('quick-set-${library.setlists.last.id}'));
      gesture = await tester.startGesture(tester.getCenter(set));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(QuickPick.renameFieldKey), findsNothing);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('vertical movement before the lift scrolls instead', (
      tester,
    ) async {
      await pump(tester);
      final set = library.activeSetlist!;
      library.updateSetlist(
        set.copyWith(songIds: [for (var i = 0; i < 4; i++) ...set.songIds]),
      );
      await openPanel(tester);
      final before = tester.getTopLeft(row(0)).dy;
      final gesture = await tester.startGesture(tester.getCenter(row(3)));
      await gesture.moveBy(const Offset(0, -12)); // past the 8dp slop
      await tester.pump(const Duration(milliseconds: 300));
      expect(haptics, isEmpty, reason: 'no lift');
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      final first = row(0);
      expect(
        first.evaluate().isEmpty || tester.getTopLeft(first).dy < before,
        isTrue,
        reason: 'scrolled',
      );
    });

    testWidgets('a drop applies at once; the next swipe needs no wait', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      final gesture = await tester.startGesture(tester.getCenter(row(0)));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(); // one frame
      expect(friday(), ['Two', 'Three', 'One'], reason: 'saved at release');
      // Right away, mid-settle: a swipe on another row works.
      await tester.drag(row(1), const Offset(-250, 0));
      await tester.pump();
      expect(friday(), ['Two', 'One']);
    });

    testWidgets('a new touch finishes a spring-back in ~80ms', (tester) async {
      await pump(tester);
      await openPanel(tester);
      final x = tester.getTopLeft(row(0)).dx;
      await tester.drag(row(0), const Offset(-80, 0)); // short: springs back
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getTopLeft(row(0)).dx, lessThan(x), reason: 'moving');
      final touch = await tester.startGesture(tester.getCenter(row(2)));
      await tester.pump(); // the catch-up starts on this frame
      await tester.pump(const Duration(milliseconds: 85));
      expect(tester.getTopLeft(row(0)).dx, x, reason: 'caught up');
      await touch.up();
      await tester.pumpAndSettle();
    });
  });

  group('swipe feel', () {
    // The revealed background, while a row is moved sideways.
    Color? behindColor(WidgetTester tester) {
      final box = find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.alignment != null,
      );
      if (box.evaluate().isEmpty) return null;
      final container = tester.widget<AnimatedContainer>(box.first);
      return (container.decoration as BoxDecoration?)?.color;
    }

    testWidgets('follows 1:1 after 32dp; crossing 40% ticks, deepens the '
        'red and grows the label; going back reverses it', (tester) async {
      await pump(tester);
      await openPanel(tester);
      final x = tester.getTopLeft(row(0)).dx;
      final width = tester.getSize(row(0)).width;
      final gesture = await tester.startGesture(tester.getCenter(row(0)));
      await gesture.moveBy(const Offset(-40, 0)); // starts the swipe
      await gesture.moveBy(const Offset(-42, 0));
      await tester.pump();
      expect(tester.getTopLeft(row(0)).dx, closeTo(x - 50, 0.5), reason: '1:1');
      expect(haptics, isEmpty);
      expect(behindColor(tester), MetraColors.stageBlack.accentResting);
      expect(
        tester.getTopLeft(find.byIcon(Icons.delete_outline)).dx,
        greaterThan(x + width / 2),
        reason: 'swiping left: on the right',
      );
      await gesture.moveBy(Offset(-width * 0.4, 0));
      await tester.pump(RowGestures.armTransition);
      expect(haptics, ['HapticFeedbackType.lightImpact'], reason: 'one tick');
      expect(behindColor(tester), MetraColors.stageBlack.accent);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale,
        RowGestures.armedScale,
      );
      await gesture.moveBy(Offset(width * 0.4, 0));
      await tester.pump(RowGestures.armTransition);
      expect(haptics, hasLength(2), reason: 'a second tick going back');
      expect(behindColor(tester), MetraColors.stageBlack.accentResting);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(friday(), hasLength(3), reason: 'released short: springs back');
      expect(haptics, hasLength(2), reason: 'nothing on release');
    });

    testWidgets('a quick flick commits even short; a flick back cancels', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      await tester.fling(row(0), const Offset(-70, 0), 1500);
      await tester.pumpAndSettle();
      expect(friday(), ['Two', 'Three'], reason: 'flicked off');
      final width = tester.getSize(row(1)).width;
      final gesture = await tester.startGesture(tester.getCenter(row(1)));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(Offset(-width * 0.08, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(30, 0)); // fast, back
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(friday(), ['Two', 'Three'], reason: 'the flick back cancelled');
    });

    testWidgets('commit: the change is immediate, the row slides off, then '
        'the rows below close the gap', (tester) async {
      await pump(tester);
      await openPanel(tester);
      final second = tester.getTopLeft(row(1)).dy;
      await tester.drag(row(0), const Offset(-260, 0));
      await tester.pump();
      expect(friday(), ['Two', 'Three'], reason: 'immediate');
      // The old second row is now row 0 (in the list, not the sliding
      // copy), still drawn in its old place.
      final listed = find.descendant(
        of: find.byType(ExitShift),
        matching: row(0),
      );
      expect(tester.getTopLeft(listed).dy, closeTo(second, 1));
      await tester.pump(RowGestures.slideOff + RowGestures.collapse);
      await tester.pump();
      expect(tester.getTopLeft(listed).dy, lessThan(second), reason: 'closed');
    });

    testWidgets('a delete holds the row open at 40% while it asks', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      final saturday = find.byKey(
        ValueKey('quick-set-${library.setlists.last.id}'),
      );
      final x = tester.getTopLeft(saturday).dx;
      final width = tester.getSize(saturday).width;
      await tester.drag(saturday, Offset(-width * 0.9, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(deleteConfirmKey), findsOneWidget);
      expect(
        tester.getTopLeft(saturday).dx,
        closeTo(x - width * RowGestures.swipeCommit, 1),
      );
      await tester.tap(find.byKey(deleteCancelKey));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(saturday).dx, x, reason: 'sprang back');
    });

    testWidgets('no swiping while a row is in rename', (tester) async {
      await pump(tester);
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      Finder set(int i) =>
          find.byKey(ValueKey('quick-set-${library.setlists[i].id}'));
      await tester.longPress(set(1));
      await tester.pumpAndSettle();
      expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
      await tester.drag(set(0), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(deleteConfirmKey), findsNothing);
      expect(library.setlists, hasLength(2));
    });

    testWidgets('each row offers its action to TalkBack', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await openPanel(tester);
      List<String> actions(Finder f) => [
        for (final id
            in tester
                    .getSemantics(f)
                    .getSemanticsData()
                    .customSemanticsActionIds ??
                <int>[])
          CustomSemanticsAction.getAction(id)!.label!,
      ];
      expect(
        actions(find.byType(SwipeRow).first),
        unorderedEquals(['Remove from set', 'Move down']),
      );
      expect(
        actions(find.byType(SwipeRow).at(1)),
        unorderedEquals(['Remove from set', 'Move up', 'Move down']),
      );
      final node = tester.getSemantics(find.byType(SwipeRow).first);
      final id = node.getSemanticsData().customSemanticsActionIds!.firstWhere(
        (id) => CustomSemanticsAction.getAction(id)!.label == 'Remove from set',
      );
      // A screen reader's custom action, as TalkBack sends it.
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
      await tester.pumpAndSettle();
      expect(friday(), ['Two', 'Three'], reason: 'removed, as by a swipe');
      handle.dispose();
    });
  });

  group('song picker', () {
    Finder pick(String name) => find.byKey(
      ValueKey('pick-${library.songs.firstWhere((s) => s.name == name).id}'),
    );

    Future<void> openPicker(WidgetTester tester) async {
      for (final (name, bpm) in [('Alpha', 90), ('Zulu', 95), ('Echo', 130)]) {
        library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        );
      }
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.addSongsKey));
      await tester.pumpAndSettle();
    }

    String addLabel(WidgetTester tester) =>
        (tester.widget<FilledButton>(find.byKey(QuickPick.pickAddKey)).child!
                as Text)
            .data!;

    testWidgets('tick and untick; songs in the set are greyed and not '
        'tappable; the button follows', (tester) async {
      await pump(tester);
      await openPicker(tester);
      expect(addLabel(tester), 'Choose songs to add');
      expect(
        tester.widget<FilledButton>(find.byKey(QuickPick.pickAddKey)).onPressed,
        isNull,
      );
      expect(inPanel('In this set'), findsNWidgets(3));
      await tester.tap(pick('One'));
      await tester.pump();
      expect(addLabel(tester), 'Choose songs to add', reason: 'in the set');
      await tester.tap(pick('Zulu'));
      await tester.pump();
      expect(haptics.last, 'HapticFeedbackType.lightImpact');
      expect(addLabel(tester), 'Add 1 song to Friday set');
      await tester.tap(pick('Alpha'));
      await tester.pump();
      expect(addLabel(tester), 'Add 2 songs to Friday set');
      await tester.tap(pick('Zulu'));
      await tester.pump();
      expect(addLabel(tester), 'Add 1 song to Friday set', reason: 'untick');
    });

    testWidgets('adding: to the end in tick order, position kept, back to '
        'the songs marked "Added"', (tester) async {
      await pump(tester);
      await openPicker(tester);
      await tester.tap(pick('Zulu'));
      await tester.tap(pick('Alpha'));
      await tester.pump();
      await tester.tap(find.byKey(QuickPick.pickAddKey));
      await tester.pumpAndSettle();
      expect(friday(), ['One', 'Two', 'Three', 'Zulu', 'Alpha']);
      expect(library.currentSong?.name, 'Two');
      expect(library.currentIndex, 1, reason: 'position unchanged');
      expect(inPanel('Song 2 of 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('added-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('added-4')), findsOneWidget);
      expect(find.byKey(QuickPick.undoKey), findsNothing, reason: 'no Undo');
      await tester.pump(QuickPick.addedFor + const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('added-3')), findsNothing);
    });

    testWidgets('search filters the picker', (tester) async {
      await pump(tester);
      for (var i = 0; i < 6; i++) {
        library.addSong(
          name: 'Extra $i',
          bpm: 100,
          pattern: const MetronomePattern.standard(),
        );
      }
      await openPicker(tester);
      expect(find.byKey(QuickPick.pickSearchKey), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'zul');
      await tester.pump();
      expect(pick('Zulu'), findsOneWidget);
      expect(pick('Alpha'), findsNothing);
    });

    for (final playing in [false, true]) {
      testWidgets(
        'a new set: Done opens the picker; Add then '
        '${playing ? 'keeps playing: back to the sets view, new set on top' : 'loads it at song 1 and shows its songs'}',
        (tester) async {
          await pump(tester);
          // Not pumpAndSettle while the click plays.
          Future<void> settle() async {
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }

          await openPanel(tester);
          if (playing) await metronome.play();
          await tester.tap(find.byKey(QuickPick.changeSetKey));
          await settle();
          await tester.tap(find.byKey(QuickPick.newSetlistKey));
          await settle();
          await tester.enterText(find.byKey(QuickPick.renameFieldKey), 'Gig');
          await tester.tap(find.byKey(QuickPick.renameDoneKey));
          await settle();
          expect(inPanel('Add to Gig'), findsOneWidget);
          expect(inPanel('In this set'), findsNothing, reason: 'a new set');
          await tester.tap(pick('One'));
          await tester.tap(pick('Three'));
          await tester.pump();
          await tester.tap(find.byKey(QuickPick.pickAddKey));
          await settle();
          expect(
            [
              for (final id
                  in library.setlists
                      .firstWhere((l) => l.name == 'Gig')
                      .songIds)
                library.songById(id)!.name,
            ],
            ['One', 'Three'],
          );
          expect(find.byType(QuickPick), findsOneWidget, reason: 'stays open');
          if (playing) {
            expect(find.byKey(QuickPick.newSetlistKey), findsOneWidget);
            expect(library.activeSetlist?.name, 'Friday set', reason: 'kept');
            expect(
              library.setlistsRecentlyPlayed.first.name,
              'Gig',
              reason: 'on top',
            );
            metronome.stop();
            await tester.pump();
          } else {
            expect(library.activeSetlist?.name, 'Gig');
            expect(library.currentSong?.name, 'One', reason: 'song 1');
            expect(find.byKey(QuickPick.changeSetKey), findsOneWidget);
            expect(inPanel('Song 1 of 2'), findsOneWidget);
          }
        },
      );
    }
  });

  group('Back, one level at a time', () {
    testWidgets('rename → dialog → sets view → panel → main; only the bare '
        'main screen leaves the app', (tester) async {
      await pump(tester);
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      Finder set(String name) => find.byKey(
        ValueKey(
          'quick-set-${library.setlists.firstWhere((l) => l.name == name).id}',
        ),
      );
      Future<bool> back() async {
        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        return handled;
      }

      await tester.longPress(set('Saturday set'));
      await tester.pumpAndSettle();
      expect(await back(), isTrue);
      expect(find.byKey(QuickPick.renameFieldKey), findsNothing, reason: '1');
      expect(find.byKey(QuickPick.newSetlistKey), findsOneWidget);

      await tester.drag(set('Saturday set'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(deleteConfirmKey), findsOneWidget);
      expect(await back(), isTrue);
      expect(find.byKey(deleteConfirmKey), findsNothing, reason: '2: Cancel');
      expect(library.setlists, hasLength(2));
      expect(find.byKey(QuickPick.newSetlistKey), findsOneWidget);

      expect(await back(), isTrue);
      expect(find.byKey(QuickPick.changeSetKey), findsOneWidget, reason: '3');

      expect(await back(), isTrue);
      expect(find.byType(QuickPick), findsNothing, reason: '4: closed');

      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(await back(), isTrue);
      expect(find.byType(BottomSheet), findsNothing, reason: '5: sheet');

      expect(await back(), isFalse, reason: 'the bare main screen: leave');
    });

    testWidgets('Back never stops the click', (tester) async {
      await pump(tester);
      await metronome.play();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QuickPick), findsNothing);
      expect(await tester.binding.handlePopRoute(), isFalse);
      expect(metronome.isPlaying, isTrue);
      metronome.stop();
      await tester.pump();
    });
  });

  group('polish', () {
    testWidgets('the Undo bar: swipe it away and the removal stays; screen '
        'readers hear it', (tester) async {
      await pump(tester);
      await openPanel(tester);
      await tester.drag(row(0), const Offset(-260, 0));
      await tester.pumpAndSettle();
      final bar = find.byKey(QuickPick.undoKey);
      expect(bar, findsOneWidget);
      expect(
        find.ancestor(
          of: bar,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false),
          ),
        ),
        findsOneWidget,
        reason: 'announced',
      );
      await tester.drag(
        inPanel('Removed from Friday set'),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(QuickPick.undoKey), findsNothing);
      expect(friday(), ['Two', 'Three'], reason: 'the removal stays done');
    });

    testWidgets('TalkBack "Move up" moves the row and saves', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      await openPanel(tester);
      final node = tester.getSemantics(find.byType(SwipeRow).at(1));
      final id = node.getSemanticsData().customSemanticsActionIds!.firstWhere(
        (id) => CustomSemanticsAction.getAction(id)!.label == 'Move up',
      );
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        id,
      );
      await tester.pumpAndSettle();
      expect(friday(), ['Two', 'One', 'Three']);
      expect(library.currentSong?.name, 'Two', reason: 'still playing Two');
      handle.dispose();
    });

    testWidgets('search in the sets view: anywhere, accents ignored; no '
        'match says so', (tester) async {
      await pump(tester);
      for (var i = 0; i < 8; i++) {
        library.addSetlist('Extra $i');
      }
      library.addSetlist('Café gig');
      await openPanel(tester);
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cafe');
      await tester.pump();
      expect(inPanel('Friday set'), findsNothing);
      expect(find.byKey(const ValueKey('no-matches')), findsNothing);
      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump();
      expect(inPanel('No sets match "xyz"'), findsOneWidget);
    });
  });

  testWidgets('"Remove animations": no hint (still counted as shown), and a '
      'short swipe snaps back at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester, hintSeen: false);
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(inPanel('Remove'), findsNothing, reason: 'no hint');
    expect(library.swipeHintSeen, isTrue, reason: 'flag still set');
    final x = tester.getTopLeft(row(0)).dx;
    await tester.drag(row(0), const Offset(-80, 0));
    await tester.pump();
    expect(tester.getTopLeft(row(0)).dx, x, reason: 'instant');
  });
}
