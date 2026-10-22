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
import 'package:metra/src/ui/song_editor.dart';
import 'package:metra/src/ui/tabular_text.dart';
import 'package:metra/src/ui/tempo_ruler.dart';

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

    testWidgets('Free play: "+ New song from this" and the three tabs', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.byKey(SetlistGroup.newSongKey), findsOneWidget);
      expect(find.text('New song from this'), findsOneWidget);
      expect(find.text('Setlists'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Free play'), findsOneWidget);
      final tabs = [
        for (final key in [
          SetlistGroup.songsTabKey,
          SetlistGroup.freePlayTabKey,
          SetlistGroup.setlistsTabKey,
        ])
          tester.getRect(find.byKey(key)),
      ];
      expect(tabs[0].right, lessThanOrEqualTo(tabs[1].left), reason: 'order');
      expect(tabs[1].right, lessThanOrEqualTo(tabs[2].left));
      expect(tabs[0].size, tabs[2].size, reason: 'equal tabs');
      expect(
        tester.getSemantics(find.byKey(SetlistGroup.freePlayTabKey)),
        matchesSemantics(
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          label: 'Free play',
        ),
      );
      expect(find.text('Create a setlist'), findsNothing);
    });

    testWidgets('Single song: the title only; the Free play tab detaches', (
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
      expect(find.byKey(SetlistGroup.songsTabKey), findsOneWidget);
      expect(groupRect(tester), rect, reason: 'no control moves');
      metronome.nudge(1); // unsaved change: Revert / Save to song showing
      await tester.pump();
      expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
      await tester.tap(find.byKey(SetlistGroup.freePlayTabKey));
      await tester.pump();
      expect(find.byKey(SetlistGroup.newSongKey), findsOneWidget);
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
      await tester.tap(find.byKey(SetlistGroup.newSongKey));
      await tester.pumpAndSettle();
      expect(find.text('New song'), findsWidgets);
      final field = tester.widget<TextField>(find.byKey(SaveAsNewKeys.name));
      expect(field.controller!.text, 'Song 1');
      expect(find.textContaining('Replace'), findsNothing, reason: 'no set');
      await tester.tap(find.byKey(SaveAsNewKeys.save));
      await tester.pumpAndSettle();
      expect(library.singleSong, isTrue);
      expect(library.currentSong?.bpm, 87);
      expect(find.byKey(SetlistGroup.newSongKey), findsNothing);
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
      expect(find.text('Saved as a new song'), findsOneWidget, reason: 'C');
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
    });

    group('teaching "edit right here"', () {
      const firstLoad = 'Change anything here, then Save';
      const firstChange = 'Playing your changes. Save keeps them in this song.';

      testWidgets('A: the first load ever, once; a change switches to the '
          'actions at once', (tester) async {
        await withSet(tester);
        expect(find.text(firstLoad), findsNothing, reason: 'no song yet');
        await tester.tap(find.byKey(SetlistGroup.nextKey)); // One
        await tester.pump();
        expect(find.text(firstLoad), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        expect(find.text(firstLoad), findsNothing);
        expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
        await tester.tap(find.byKey(SetlistGroup.nextKey)); // Two
        await tester.pump();
        expect(find.text(firstLoad), findsNothing, reason: 'once');
        library.revertSong(metronome);
        await tester.pump();
      });

      testWidgets('A during a change: the actions show', (tester) async {
        await withSet(tester);
        await tester.tap(find.byKey(SetlistGroup.nextKey));
        await tester.pump();
        await tester.tap(find.text('+1'));
        await tester.pump();
        expect(find.text(firstLoad), findsNothing);
        expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
      });

      testWidgets('A again at the first load of a "+ New song" song, once', (
        tester,
      ) async {
        await withSet(tester);
        library.markTipSeen('edit-first-load');
        library.saveAsNewSong('Fresh', metronome, fresh: true);
        await tester.pump();
        expect(find.text(firstLoad), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        library.saveAsNewSong('Fresher', metronome, fresh: true);
        await tester.pump();
        expect(find.text(firstLoad), findsNothing, reason: 'once');
        library.saveAsNewSong('Copy', metronome);
        await tester.pump();
        expect(find.text(firstLoad), findsNothing, reason: 'not a new song');
      });

      testWidgets('B: the first change, once, without moving anything; '
          'C after Save', (tester) async {
        await withSet(tester);
        await tester.tap(find.byKey(SetlistGroup.nextKey));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        Rect at(Finder f) => tester.getRect(f);
        final ruler = at(find.byType(TempoRuler));
        final bpm = at(find.byKey(MetronomeScreen.bpmKey));
        await tester.tap(find.text('+1'));
        await tester.pump();
        expect(find.text(firstChange), findsOneWidget);
        final save = tester.widget<Text>(
          find.descendant(
            of: find.byKey(MetronomeScreen.saveToSongKey),
            matching: find.text('Save'),
          ),
        );
        expect(save.style?.fontWeight, FontWeight.w600, reason: 'Save lit');
        expect(at(find.byType(TempoRuler)), ruler, reason: 'nothing moves');
        expect(at(find.byKey(MetronomeScreen.bpmKey)).top, bpm.top);
        await tester.tap(find.byKey(MetronomeScreen.saveToSongKey));
        await tester.pump();
        expect(find.text(firstChange), findsNothing);
        expect(find.text('Saved to the song'), findsOneWidget, reason: 'C');
        await tester.pump(const Duration(milliseconds: 1500));
        expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
        await tester.tap(find.text('+1'));
        await tester.pump();
        expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
        expect(find.text(firstChange), findsNothing, reason: 'once');
        // Revert: no message.
        await tester.tap(find.byKey(MetronomeScreen.revertKey));
        await tester.pump();
        expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
      });

      testWidgets('B goes after ~8 s', (tester) async {
        await withSet(tester);
        await tester.tap(find.byKey(SetlistGroup.nextKey));
        await tester.pump();
        await tester.tap(find.text('+1'));
        await tester.pump();
        expect(find.text(firstChange), findsOneWidget);
        await tester.pump(const Duration(seconds: 8));
        expect(find.text(firstChange), findsNothing);
        expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
      });
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
      expect(
        bar().height,
        SetlistGroup.rowHeight + 16 + SetlistGroup.tabsHeight + 12,
      );
      library.playSingleSong(library.visibleSongs.first, metronome);
      await tester.pump();
      expect((title(), bar()), inSet, reason: 'Single song');
      library.detachSong();
      await tester.pump();
      expect(bar(), inSet.$2, reason: 'Free play');
      expect(find.byKey(SetlistGroup.newSongKey), findsOneWidget);
    });

    testWidgets(
      'fixed lines: shrinking names never move the lines under them',
      (tester) async {
        await withSet(tester);
        await tester.tap(find.byKey(SetlistGroup.nextKey)); // One, next: Two
        await tester.pump();
        final subtitle = tester.getRect(
          find.byKey(MetronomeScreen.subtitleKey),
        );
        final bpmLine = tester.getRect(find.text('110 BPM'));
        final long = 'A very long song name that has to shrink to fit';
        for (final s in library.songs) {
          library.updateSong(s.copyWith(name: '$long ${s.name}'));
        }
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(MetronomeScreen.titleKey))
              .style!
              .fontSize,
          lessThan(34),
          reason: 'the title shrank',
        );
        expect(
          tester.getRect(find.byKey(MetronomeScreen.subtitleKey)),
          subtitle,
        );
        expect(tester.getRect(find.text('110 BPM')), bpmLine);
      },
    );

    testWidgets('the title block is one long-press target: the song '
        'editor; with no song, nothing', (tester) async {
      await withSet(tester); // a set, no song yet
      await tester.longPress(find.byKey(MetronomeScreen.titleBlockKey));
      await tester.pumpAndSettle();
      expect(find.byType(SongEditor), findsNothing);
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(MetronomeScreen.titleBlockKey)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.longPress(find.byKey(MetronomeScreen.subtitleKey));
      await tester.pumpAndSettle();
      expect(find.byType(SongEditor), findsOneWidget);
    });

    testWidgets('Single song: previous | next through the library A–Z', (
      tester,
    ) async {
      await pumpScreen(tester);
      for (final (name, bpm) in [
        ('Bravo', 100),
        ('alpha', 90),
        ('Charlie', 120),
      ]) {
        library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        );
      }
      library.playSingleSong(
        library.songById(library.songs.first.id)!,
        metronome,
      );
      await tester.pump();
      expect(
        find.byKey(SetlistGroup.headerKey),
        findsNothing,
        reason: 'no center',
      );
      expect(find.text('alpha'), findsOneWidget, reason: 'previous, A–Z');
      expect(find.text('Charlie'), findsOneWidget, reason: 'next');
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(library.currentSong?.name, 'Charlie');
      expect(library.singleSong, isTrue, reason: 'stays Single song');
      expect(metronome.bpm, 120);
      expect(enabled(tester, SetlistGroup.nextKey), isFalse, reason: 'last');
      await tester.tap(find.byKey(SetlistGroup.previousKey));
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.previousKey));
      await tester.pump();
      expect(library.currentSong?.name, 'alpha');
      expect(
        enabled(tester, SetlistGroup.previousKey),
        isFalse,
        reason: 'first',
      );
    });

    testWidgets('tabs switch at once; the active tab does nothing', (
      tester,
    ) async {
      await pumpScreen(tester);
      final song = library.addSong(
        name: 'Solo',
        bpm: 90,
        pattern: const MetronomePattern.standard(),
      );
      await tester.tap(find.byKey(SetlistGroup.songsTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'never a popup');
      expect(library.currentSong?.id, song.id, reason: 'first A–Z');
      metronome.nudge(3); // an unsaved change survives a tap on Songs
      await tester.tap(find.byKey(SetlistGroup.songsTabKey));
      await tester.pumpAndSettle();
      expect(metronome.bpm, 93);
      expect(find.byType(QuickPick), findsNothing);
    });

    testWidgets('"Songs ⌄" opens the list above the context row; '
        'long-press opens the library', (tester) async {
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
      final song = library.addSong(
        name: 'Solo',
        bpm: 90,
        pattern: const MetronomePattern.standard(),
      );
      library.playSingleSong(song, metronome);
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(
        tester.getRect(find.byType(QuickPick)).bottom,
        lessThan(tester.getRect(find.byType(SetlistGroup)).top),
        reason: 'opens above the context row',
      );
      expect(
        tester.getRect(find.byType(QuickPick)).left,
        tester.getRect(find.byKey(MetronomeScreen.playKey)).left,
        reason: 'content width',
      );
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      // No long-press of its own: a hold is just a tap (the list opens).
      await tester.longPress(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(haptics, isEmpty);
    });

    testWidgets('the tabs stay above the system gesture area', (tester) async {
      await pumpScreen(tester);
      tester.view.padding = const FakeViewPadding(bottom: 20);
      tester.view.viewPadding = const FakeViewPadding(bottom: 20);
      tester.view.systemGestureInsets = const FakeViewPadding(bottom: 48);
      await tester.pump();
      final tabs = tester.getRect(find.byKey(SetlistGroup.freePlayTabKey));
      expect(tabs.bottom, lessThanOrEqualTo(900 - 48));
      expect(tester.takeException(), isNull);
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
      expect(find.text('110 BPM'), findsOneWidget);

      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.tap(find.byKey(SetlistGroup.nextKey));
      await tester.pump();
      expect(title(tester), 'Three');
      expect(enabled(tester, SetlistGroup.nextKey), isFalse);

      await tester.tap(find.byKey(SetlistGroup.previousKey));
      await tester.pump();
      expect(title(tester), 'Two');
      expect(
        find.bySemanticsLabel('Previous song: One, 100 BPM'),
        findsOneWidget,
      );
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

    /// Single song on the first song A–Z ("One"), then its "Songs ⌄".
    Future<void> openSongsList(WidgetTester tester) async {
      library.playSingleSong(library.songsAZ.first, metronome);
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
    }

    /// "Saturday set" loaded, then "4/12 ⌄" > "Other setlists ›".
    Future<void> openSetlistsList(WidgetTester tester) async {
      library.loadSetlist(
        library.setlists.firstWhere((l) => l.name == 'Saturday set').id,
        metronome,
      );
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
    }

    Finder inPanel(String text) =>
        find.descendant(of: find.byType(QuickPick), matching: find.text(text));

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
      await openSongsList(tester);
      expect(find.byType(QuickPick), findsOneWidget);
      expect(find.byType(SearchField), findsNothing, reason: 'only 3 songs');
      expect(
        rows(
          tester,
          'quick-song-',
        ).map((k) => library.songById(k.substring(11))!.name),
        ['One', 'Three', 'Two'],
      );
      await tester.tap(inPanel('Three'));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing);
      expect(library.singleSong, isTrue);
      expect(library.currentSong?.name, 'Three');
      expect(metronome.bpm, 120);
    });

    testWidgets('Songs ⌄: search above 8 songs; "+ New song ›" pinned', (
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
      await openSongsList(tester);
      expect(find.byType(SearchField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'thr');
      await tester.pump();
      expect(rows(tester, 'quick-song-'), hasLength(1));
      expect(find.byKey(QuickPick.songLibraryKey), findsNothing);
      expect(find.byKey(QuickPick.newSongKey), findsOneWidget, reason: '+ New');
    });

    testWidgets('Setlists ⌄: recently played first; a tap loads song 1', (
      tester,
    ) async {
      await withLibrary(tester);
      await openSetlistsList(tester);
      expect(
        rows(
          tester,
          'quick-set-',
        ).map((k) => library.setlists.firstWhere((l) => k.endsWith(l.id)).name),
        ['Saturday set', 'Friday set'],
      );
      await tester.tap(inPanel('Friday set'));
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Friday set');
      expect(library.currentSong?.name, 'One');
    });

    testWidgets('"Change set" swaps in place; ‹ Back and Android Back return', (
      tester,
    ) async {
      await withLibrary(tester);
      await openSetlistsList(tester);
      expect(find.byType(QuickPick), findsOneWidget);
      expect(find.byKey(QuickPick.newSetlistKey), findsOneWidget);
      expect(find.byKey(QuickPick.changeSetKey), findsNothing, reason: 'sets');
      await tester.tap(find.byKey(QuickPick.backKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(QuickPick.changeSetKey),
        findsOneWidget,
        reason: 'songs',
      );
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget, reason: 'still open');
      expect(find.byKey(QuickPick.changeSetKey), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'then it closes');
    });

    testWidgets('tap outside closes; nothing changes', (tester) async {
      await withLibrary(tester);
      await openSetlistsList(tester);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing);
      expect(library.activeSetlist?.name, 'Saturday set');
    });

    testWidgets('no sets: the tab shows "No setlists yet"; "+ New setlist"', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(SetlistGroup.setlistsTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'never a popup');
      expect(find.text('No setlists yet'), findsOneWidget);
      expect(library.tab, ModeTab.setlists);
      await tester.tap(find.byKey(SetlistGroup.firstSetlistKey));
      await tester.pumpAndSettle();
      // The sets view with the new set being named; Done opens the picker.
      expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
      expect(library.setlists, hasLength(1));
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('Add to'), findsOneWidget, reason: 'picker');
    });

    testWidgets('no songs: the tab shows "No songs yet"; "+ New song"', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(SetlistGroup.songsTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing, reason: 'never a popup');
      expect(find.text('No songs yet'), findsOneWidget);
      expect(library.tab, ModeTab.songs);
      await tester.tap(find.byKey(SetlistGroup.firstSongKey));
      await tester.pumpAndSettle();
      // The Songs list with a new row being named; Done saves and loads it.
      expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(library.songs, hasLength(1));
      expect(library.currentSong?.name, library.songs.single.name);
    });

    testWidgets('set ⌄: header, current song marked; a tap jumps to it', (
      tester,
    ) async {
      await withLibrary(tester, loaded: true);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      final panel = find.byType(QuickPick);
      expect(
        find.descendant(of: panel, matching: find.text('Song 2 of 3')),
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

    testWidgets('Free play tab detaches a set; "Change set" swaps', (
      tester,
    ) async {
      await withLibrary(tester, loaded: true);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      expect(rows(tester, 'quick-set-song-'), isEmpty);
      expect(find.byKey(QuickPick.newSetlistKey), findsOneWidget);
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(SetlistGroup.freePlayTabKey));
      await tester.pumpAndSettle();
      expect(library.activeSetlist, isNull);
      expect(library.currentSong, isNull);
      expect(metronome.bpm, 110, reason: 'the click keeps its tempo');
    });

    testWidgets('long-pressing the set (main control or panel header) '
        'opens no page', (tester) async {
      await withLibrary(tester, loaded: true);
      // A hold on "4/12" is just a tap: the set's list.
      await tester.longPress(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      await tester.longPress(find.byKey(QuickPick.setHeaderKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget, reason: 'still here');
      expect(find.byKey(QuickPick.changeSetKey), findsOneWidget);
    });

    group('New song dialog: "Add to a setlist"', () {
      Future<void> openDialog(WidgetTester tester) async {
        await tester.tap(find.byKey(SetlistGroup.freePlayTabKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(SetlistGroup.newSongKey));
        await tester.pumpAndSettle();
      }

      Finder option(String setName) => find.byKey(
        ValueKey(
          'add-to-set-${library.setlists.firstWhere((l) => l.name == setName).id}',
        ),
      );

      Future<void> save(WidgetTester tester) async {
        await tester.tap(find.byKey(SaveAsNewKeys.save));
        await tester.pumpAndSettle();
      }

      List<String> names(String setName) => [
        for (final id
            in library.setlists.firstWhere((l) => l.name == setName).songIds)
          library.songById(id)!.name,
      ];

      testWidgets('None by default: just a name and Save', (tester) async {
        await withLibrary(tester);
        await openDialog(tester);
        expect(
          find.descendant(
            of: find.byKey(SaveAsNewKeys.addToSet),
            matching: find.text('None'),
          ),
          findsOneWidget,
        );
        await save(tester);
        expect(library.songs, hasLength(4));
        expect(library.setlists, hasLength(2));
        expect(names('Friday set'), ['One', 'Two', 'Three']);
        expect(names('Saturday set'), ['Three']);
      });

      testWidgets('a recent set: added at its end; nothing switches', (
        tester,
      ) async {
        await withLibrary(tester);
        await openDialog(tester);
        await tester.tap(find.byKey(SaveAsNewKeys.addToSet));
        await tester.pumpAndSettle();
        expect(find.text('Just save the song'), findsOneWidget);
        await tester.tap(option('Friday set'));
        await tester.pumpAndSettle();
        expect(find.text('Added at the end · 3 songs'), findsOneWidget);
        await save(tester);
        expect(names('Friday set'), ['One', 'Two', 'Three', 'Song 1']);
        expect(library.activeSetlist, isNull, reason: 'no switch');
        expect(library.currentSong?.name, 'Song 1');
      });

      testWidgets('3 recent sets, "More setlists ⌄" for the rest', (
        tester,
      ) async {
        await withLibrary(tester);
        for (final name in ['Gig A', 'Gig B']) {
          library.saveSetlist(name: name, songIds: const []);
        }
        await tester.pump();
        await openDialog(tester);
        await tester.tap(find.byKey(SaveAsNewKeys.addToSet));
        await tester.pumpAndSettle();
        final hidden = library.setlistsRecentlyPlayed.last.name;
        expect(option(hidden), findsNothing);
        await tester.tap(find.byKey(SaveAsNewKeys.moreSets));
        await tester.pumpAndSettle();
        await tester.ensureVisible(option(hidden));
        await tester.tap(option(hidden));
        await tester.pumpAndSettle();
        await save(tester);
        expect(names(hidden).last, 'Song 1');
      });

      testWidgets('"+ New setlist": made on Save as "Setlist N", with the '
          'song', (tester) async {
        await withLibrary(tester);
        await openDialog(tester);
        await tester.tap(find.byKey(SaveAsNewKeys.addToSet));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(SaveAsNewKeys.newSet));
        await tester.tap(find.byKey(SaveAsNewKeys.newSet));
        await tester.pumpAndSettle();
        expect(library.setlists, hasLength(2), reason: 'not before Save');
        await save(tester);
        expect(names('Setlist 1'), ['Song 1']);
        expect(library.activeSetlist, isNull, reason: 'no switch');
      });

      testWidgets('no sets yet: only None and "+ New setlist"', (tester) async {
        await pumpScreen(tester);
        await openDialog(tester);
        await tester.tap(find.byKey(SaveAsNewKeys.addToSet));
        await tester.pumpAndSettle();
        expect(find.byKey(SaveAsNewKeys.noSet), findsOneWidget);
        expect(find.byKey(SaveAsNewKeys.newSet), findsOneWidget);
        expect(find.byType(RadioListTile<String>), findsNWidgets(2));
        expect(find.byKey(SaveAsNewKeys.moreSets), findsNothing);
        await tester.tap(find.byKey(SaveAsNewKeys.newSet));
        await tester.pumpAndSettle();
        await save(tester);
        expect(library.setlists.single.name, 'Setlist 1');
        expect(names('Setlist 1'), ['Song 1']);
      });

      testWidgets('Single song "Save as new" has it; setlist mode keeps '
          'Replace / Add after', (tester) async {
        await withLibrary(tester, loaded: true);
        await tester.tap(find.text('+1'));
        await tester.pump();
        await tester.tap(find.byKey(MetronomeScreen.saveAsNewKey));
        await tester.pumpAndSettle();
        expect(find.byKey(SaveAsNewKeys.addToSet), findsNothing);
        expect(find.text('Replace Two'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        library.playSingleSong(library.songs.first, metronome);
        await tester.pump();
        await tester.tap(find.text('+1'));
        await tester.pump();
        await tester.tap(find.byKey(MetronomeScreen.saveAsNewKey));
        await tester.pumpAndSettle();
        expect(find.byKey(SaveAsNewKeys.addToSet), findsOneWidget);
      });
    });

    testWidgets('no "Free play" rows in the dropdowns', (tester) async {
      await withLibrary(tester);
      library.playSingleSong(library.songs.first, metronome);
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.songsTabKey));
      await tester.pumpAndSettle();
      expect(find.text('Free play'), findsOneWidget, reason: 'the tab only');
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      library.loadSetlist(library.setlists.first.id, metronome);
      await tester.pump();
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      expect(find.text('Free play'), findsOneWidget, reason: 'the tab only');
      final firstSong = tester.getRect(
        find.byKey(const ValueKey('quick-set-song-0')),
      );
      final add = tester.getRect(find.byKey(QuickPick.addSongsKey));
      expect(add.top, greaterThan(firstSong.bottom), reason: 'footer');
    });

    testWidgets('long-press a set renames it in place: Done, cancel, empty', (
      tester,
    ) async {
      await withLibrary(tester);
      await openSetlistsList(tester);
      Future<void> rename(String to) async {
        await tester.longPress(inPanel('Friday set'));
        await tester.pumpAndSettle();
        expect(find.byKey(QuickPick.renameFieldKey), findsOneWidget);
        await tester.enterText(find.byKey(QuickPick.renameFieldKey), to);
      }

      await rename('');
      await tester.tap(find.byKey(QuickPick.renameDoneKey));
      await tester.pumpAndSettle();
      expect(
        library.setlists.any((l) => l.name == 'Friday set'),
        isTrue,
        reason: 'empty keeps the old name',
      );
      await rename('Gig');
      await tester.binding.handlePopRoute(); // Back cancels, panel stays
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(library.setlists.any((l) => l.name == 'Friday set'), isTrue);
      await rename('Saturday set');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        library.setlists.where((l) => l.name == 'Saturday set'),
        hasLength(2),
        reason: 'duplicates allowed',
      );
      expect(library.activeSetlist?.name, 'Saturday set', reason: 'not loaded');
    });
  });
}
