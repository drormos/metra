import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/library_pick.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';

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
      expect(find.byType(LibraryPick), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget, reason: 'back here');
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

    testWidgets('the playing song springs back; Undo goes after ~6 s', (
      tester,
    ) async {
      await pump(tester);
      await openPanel(tester);
      await swipe(tester, row(1), 250);
      expect(friday(), ['One', 'Two', 'Three'], reason: 'Two is playing');
      await swipe(tester, row(2), 250);
      expect(friday(), ['One', 'Two']);
      expect(find.byKey(QuickPick.undoKey), findsOneWidget);
      await tester.pump(QuickPick.undoFor + const Duration(seconds: 1));
      expect(find.byKey(QuickPick.undoKey), findsNothing);
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

    testWidgets('the loaded set is marked and can\'t be deleted; another '
        'can, with Undo in place', (tester) async {
      await pump(tester);
      await openSets(tester);
      await swipe(tester, setRow('Friday set'), -250);
      expect(library.setlists, hasLength(2), reason: 'loaded: springs back');
      expect(find.byKey(deleteConfirmKey), findsNothing, reason: 'no dialog');
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
      expect(find.byType(LibraryPick), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(inPanel('Gig'), findsOneWidget);
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
      await swipe(tester, songRow('Two'), -250);
      expect(find.byKey(deleteConfirmKey), findsNothing, reason: 'loaded');
      expect(library.songs, hasLength(3));
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
}
