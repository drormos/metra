import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/play_marker.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/save_as_new_dialog.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/setlist_picker.dart';
import 'package:metra/src/ui/song_editor.dart';
import 'package:metra/src/ui/song_library.dart';
import 'package:metra/src/ui/tabular_text.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_group_test');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save started on the widget test's fake clock may still be
      // writing; a leftover temp folder is harmless.
    }
  });

  Future<void> pumpScreen(WidgetTester tester) async {
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
  }

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

    Finder position(String text) =>
        find.byWidgetPredicate((w) => w is TabularText && w.text == text);

    Rect groupRect(WidgetTester tester) =>
        tester.getRect(find.byType(SetlistGroup));

    testWidgets('Free play with no setlists: Setlists and Songs', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(MetronomeScreen.newSongKey), findsOneWidget);
      expect(find.text('Setlists'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Create a setlist'), findsNothing);
    });

    testWidgets('Single song: the title only; Free play from a dropdown', (
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
      await pumpScreen(tester);
      final rect = groupRect(tester);
      final song = library.addSong(
        name: 'Solo',
        bpm: 90,
        pattern: const MetronomePattern.standard(),
      );
      library.playSong(song, metronome);
      await metronome.play();
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data,
        'Solo',
      );
      expect(
        tester.widget<Text>(find.byKey(MetronomeScreen.subtitleKey)).data,
        '',
        reason: 'no subtitle in Single song',
      );
      expect(find.byKey(SetlistGroup.songsKey), findsOneWidget);
      expect(groupRect(tester), rect, reason: 'no control moves');
      metronome.nudge(1); // unsaved change: Revert / Save to song showing
      await tester.pump();
      expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(QuickPick.freePlayKey));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(MetronomeScreen.newSongKey), findsOneWidget);
      expect(find.byKey(MetronomeScreen.titleKey), findsNothing);
      expect(find.byKey(MetronomeScreen.revertKey), findsNothing);
      expect(metronome.isPlaying, isTrue);
      expect(metronome.bpm, 91, reason: 'the click is unchanged');
      expect(haptics.last, 'HapticFeedbackType.mediumImpact');
      metronome.stop();
      await tester.pump();
    });

    testWidgets('Free play: "+ New song" saves the click as a song', (
      tester,
    ) async {
      await pumpScreen(tester);
      metronome.setBpm(87);
      await tester.tap(find.byKey(MetronomeScreen.newSongKey));
      await tester.pumpAndSettle();
      expect(find.text('New song'), findsWidgets);
      final field = tester.widget<TextField>(find.byKey(SaveAsNewKeys.name));
      expect(field.controller!.text, 'Song 1');
      expect(find.textContaining('Replace'), findsNothing, reason: 'no set');
      await tester.tap(find.byKey(SaveAsNewKeys.save));
      await tester.pumpAndSettle();
      expect(library.singleSong, isTrue);
      expect(library.currentSong?.bpm, 87);
      expect(find.byKey(MetronomeScreen.newSongKey), findsNothing);
    });

    testWidgets('Save as new from a set: Replace by default', (tester) async {
      await withSet(tester);
      await tester.tap(find.byKey(SetlistGroup.nextKey)); // One
      await tester.pump();
      await tester.tap(find.text('+1'));
      await tester.pump();
      await tester.tap(find.byKey(MetronomeScreen.saveAsNewKey));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(SaveAsNewKeys.name));
      expect(field.controller!.text, 'One 2');
      expect(find.text('In Friday set'), findsOneWidget);
      expect(find.text('Replace One'), findsOneWidget);
      await tester.tap(find.byKey(SaveAsNewKeys.save));
      await tester.pumpAndSettle();
      expect(library.currentSong?.name, 'One 2');
      expect(library.visibleSongs.first.name, 'One 2');
      expect(find.byKey(MetronomeScreen.revertKey), findsNothing);
      expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
    });

    testWidgets('title block and source bar keep their size in every mode', (
      tester,
    ) async {
      await withSet(tester);
      Rect title() => tester.getRect(find.byKey(MetronomeScreen.titleKey));
      Rect bar() => tester.getRect(find.byType(SetlistGroup));
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      final inSet = (title(), bar());
      expect(bar().height, SetlistGroup.height);
      library.playSingleSong(library.visibleSongs.first, metronome);
      await tester.pump();
      expect((title(), bar()), inSet, reason: 'Single song');
      library.detachSong();
      await tester.pump();
      expect(bar(), inSet.$2, reason: 'Free play');
      expect(find.byKey(MetronomeScreen.newSongKey), findsOneWidget);
    });

    testWidgets('long-press the set name opens the set page', (tester) async {
      await withSet(tester);
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(MetronomeScreen.subtitleKey)).data,
        'Friday set',
      );
      await tester.longPress(find.byKey(MetronomeScreen.subtitleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SetlistPicker.backToSetlistsKey), findsOneWidget);
    });

    testWidgets('the Setlists and Songs buttons are the same size', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(
        tester.getSize(find.byKey(SetlistGroup.setlistsKey)),
        tester.getSize(find.byKey(SetlistGroup.songsKey)),
      );
    });

    testWidgets('setlist mode: header, position, neighbours', (tester) async {
      await withSet(tester);
      expect(find.text('Friday set'), findsOneWidget);
      expect(position('–/3'), findsOneWidget, reason: 'no song yet');
      expect(enabled(tester, SetlistGroup.previousKey), isFalse);
      expect(find.text('One'), findsOneWidget, reason: 'next = first song');

      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(title(tester), 'One');
      expect(metronome.bpm, 100);
      expect(position('1/3'), findsOneWidget);
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

  group('quick-pick dropdowns', () {
    /// Songs added out of A–Z order; "Friday set" (One, Two, Three) and
    /// "Saturday set" (Three), Saturday played most recently.
    Future<void> withLibrary(WidgetTester tester, {bool loaded = false}) async {
      await pumpScreen(tester);
      final songs = {
        for (final (name, bpm) in [('Two', 110), ('One', 100), ('Three', 120)])
          name: library
              .addSong(
                name: name,
                bpm: bpm,
                pattern: const MetronomePattern.standard(),
              )
              .id,
      };
      final friday = library.saveSetlist(
        name: 'Friday set',
        songIds: [songs['One']!, songs['Two']!, songs['Three']!],
      );
      final saturday = library.saveSetlist(
        name: 'Saturday set',
        songIds: [songs['Three']!],
      );
      library
        ..setActiveSetlist(friday.id)
        ..setActiveSetlist(saturday.id)
        ..detachSong();
      if (loaded) {
        library.loadSetlist(friday.id, metronome);
        library.nextSong(metronome); // Two, 2 of 3
      }
      await tester.pump();
    }

    List<String> rows(WidgetTester tester, String prefix) => [
      for (final w in tester.widgetList<InkWell>(
        find.byWidgetPredicate(
          (w) =>
              w is InkWell &&
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith(prefix),
        ),
      ))
        (w.key! as ValueKey<String>).value,
    ];

    testWidgets('Songs ⌄: A–Z; a tap plays it as a single song and closes', (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(find.byType(SearchField), findsNothing, reason: 'only 3 songs');
      expect(
        rows(
          tester,
          'quick-song-',
        ).map((k) => library.songById(k.substring(11))!.name),
        ['One', 'Three', 'Two'],
      );
      await tester.tap(find.text('Three'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing);
      expect(library.singleSong, isTrue);
      expect(library.currentSong?.name, 'Three');
      expect(metronome.bpm, 120);
    });

    testWidgets('Songs ⌄: search above 8 songs; "Song library ›"', (
      tester,
    ) async {
      await withLibrary(tester);
      for (var i = 4; i <= 9; i++) {
        library.addSong(
          name: 'Song $i',
          bpm: 100,
          pattern: const MetronomePattern.standard(),
        );
      }
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byType(SearchField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'thr');
      await tester.pump();
      expect(rows(tester, 'quick-song-'), hasLength(1));
      await tester.tap(find.byKey(QuickPick.songLibraryKey));
      await tester.pumpAndSettle();
      expect(find.byType(SongLibrary), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'main screen');
    });

    testWidgets('Setlists ⌄: recently played first; a tap loads song 1', (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      expect(
        rows(
          tester,
          'quick-set-',
        ).map((k) => library.setlists.firstWhere((l) => k.endsWith(l.id)).name),
        ['Saturday set', 'Friday set'],
      );
      await tester.tap(find.text('Friday set'));
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Friday set');
      expect(library.currentSong?.name, 'One');
    });

    testWidgets('"Manage setlists ›" opens What to play; ‹ returns', (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.manageSetlistsKey));
      await tester.pumpAndSettle();
      expect(find.text('What to play'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(SetlistPicker), findsNothing);
      expect(find.byType(QuickPick), findsNothing);
    });

    testWidgets('tap outside closes; nothing changes', (tester) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing);
      expect(library.activeSetlist, isNull);
    });

    testWidgets('empty: "No setlists yet", "New setlist ›" opens a new set', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      expect(find.text('No setlists yet'), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.newSetlistKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SetlistPicker.titleFieldKey), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('What to play'), findsOneWidget);
      expect(library.setlists, isEmpty, reason: 'left empty');
    });

    testWidgets('empty: "No songs yet", "New song ›" opens the editor', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.text('No songs yet'), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.newSongKey));
      await tester.pumpAndSettle();
      expect(find.byType(SongEditor), findsOneWidget);
    });

    testWidgets('set ⌄: header, current song marked; a tap jumps to it', (
      tester,
    ) async {
      await withLibrary(tester, loaded: true);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      final panel = find.byType(QuickPick);
      expect(
        find.descendant(of: panel, matching: find.text('2 of 3')),
        findsOneWidget,
      );
      expect(rows(tester, 'quick-set-song-'), hasLength(3));
      expect(
        tester
            .widgetList<PlayMarker>(find.byType(PlayMarker))
            .where((m) => m.current),
        hasLength(1),
      );
      await tester.tap(
        find.descendant(of: panel, matching: find.text('Three')),
      );
      await tester.pumpAndSettle();
      expect(library.currentSong?.name, 'Three');
      expect(library.currentIndex, 2);
      expect(find.byType(QuickPick), findsNothing);
    });

    testWidgets('set ⌄: Free play detaches; "Other setlists ›" swaps', (
      tester,
    ) async {
      await withLibrary(tester, loaded: true);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.otherSetlistsKey));
      await tester.pumpAndSettle();
      expect(rows(tester, 'quick-set-song-'), isEmpty);
      expect(find.byKey(QuickPick.manageSetlistsKey), findsOneWidget);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.freePlayKey));
      await tester.pumpAndSettle();
      expect(library.activeSetlist, isNull);
      expect(library.currentSong, isNull);
      expect(metronome.bpm, 110, reason: 'the click keeps its tempo');
    });

    for (final inPanel in [false, true]) {
      testWidgets(
        'long-press the set (${inPanel ? 'panel header' : 'main '
                  'control'}) opens its page; one haptic; the click continues',
        (tester) async {
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
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(SystemChannels.platform, null),
          );
          await withLibrary(tester, loaded: true);
          await metronome.play();
          if (inPanel) {
            await tester.tap(find.byKey(SetlistGroup.headerKey));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 200));
            await tester.longPress(find.byKey(QuickPick.setHeaderKey));
          } else {
            await tester.longPress(find.byKey(SetlistGroup.headerKey));
          }
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(QuickPick), findsNothing);
          expect(find.byKey(SetlistPicker.backToSetlistsKey), findsOneWidget);
          expect(find.text('3 songs'), findsOneWidget);
          expect(haptics, ['HapticFeedbackType.mediumImpact']);
          expect(metronome.isPlaying, isTrue);
          expect(library.currentSong?.name, 'Two', reason: 'nothing reloads');
          await tester.binding.handlePopRoute();
          // Not pumpAndSettle: the click is playing.
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(
            find.byType(SetlistPicker),
            findsNothing,
            reason: 'main screen',
          );
          metronome.stop();
          await tester.pump();
        },
      );
    }

    testWidgets('"Free play" is the last pinned row, unless in Free play', (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byKey(QuickPick.freePlayKey), findsNothing);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      library.loadSetlist(library.setlists.first.id, metronome);
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      final freePlay = tester.getRect(find.byKey(QuickPick.freePlayKey));
      final firstSong = tester.getRect(
        find.byKey(const ValueKey('quick-set-song-0')),
      );
      final other = tester.getRect(find.byKey(QuickPick.otherSetlistsKey));
      expect(other.top, greaterThan(firstSong.bottom), reason: 'footer');
      expect(freePlay.top, greaterThanOrEqualTo(other.bottom), reason: 'last');
    });

    testWidgets('long-press a song edits it; back returns to main', (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Two'));
      await tester.pumpAndSettle();
      expect(find.byType(SongEditor), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Two'), findsOneWidget);
      expect(library.currentSong, isNull, reason: 'nothing loaded');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SongEditor), findsNothing);
      expect(find.byType(QuickPick), findsNothing);
    });

    testWidgets("long-press a set opens its page; back returns to main", (
      tester,
    ) async {
      await withLibrary(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Friday set'));
      await tester.pumpAndSettle();
      expect(find.byKey(SetlistPicker.backToSetlistsKey), findsOneWidget);
      expect(find.text('3 songs'), findsOneWidget);
      expect(library.activeSetlist, isNull, reason: 'not loaded');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SetlistPicker), findsNothing);
    });
  });
}
