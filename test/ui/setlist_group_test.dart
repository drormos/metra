import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/setlist_picker.dart';
import 'package:metra/src/ui/song_library.dart';

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

    Rect groupRect(WidgetTester tester) =>
        tester.getRect(find.byType(SetlistGroup));

    testWidgets('Free play with no setlists: Create a setlist and Songs', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Free play'), findsOneWidget);
      expect(find.text('Create a setlist'), findsOneWidget);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.byTooltip('New setlist'), findsNothing, reason: 'no +');
    });

    testWidgets('Free play with setlists: Setlists opens the picker', (
      tester,
    ) async {
      await pumpScreen(tester);
      library.addSetlist('Friday set');
      await tester.pump();
      expect(find.text('Create a setlist'), findsNothing);
      await tester.tap(find.byKey(SetlistGroup.setlistsKey));
      await tester.pumpAndSettle();
      expect(find.text('What to play'), findsOneWidget);
    });

    testWidgets('Single song: header and Go free', (tester) async {
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
      expect(find.text('Single song'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data,
        'Solo',
      );
      expect(find.byKey(SetlistGroup.songsKey), findsOneWidget);
      expect(groupRect(tester), rect, reason: 'no control moves');
      metronome.nudge(1); // unsaved change: Revert / Save to song showing
      await tester.pump();
      expect(find.byKey(MetronomeScreen.revertKey), findsOneWidget);
      await tester.tap(find.byKey(SetlistGroup.goFreeKey));
      await tester.pump();
      expect(find.text('Free play'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(MetronomeScreen.titleKey)).data,
        '',
      );
      expect(find.byKey(MetronomeScreen.revertKey), findsNothing);
      expect(metronome.isPlaying, isTrue);
      expect(metronome.bpm, 91, reason: 'the click is unchanged');
      expect(haptics.last, 'HapticFeedbackType.mediumImpact');
      metronome.stop();
      await tester.pump();
    });

    testWidgets('Songs opens the song library', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(SetlistGroup.songsKey));
      await tester.pumpAndSettle();
      expect(find.byType(SongLibrary), findsOneWidget);
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

    testWidgets('Create a setlist opens the editor; saving loads the set', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Create a setlist'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Saturday');
      await tester.pump();
      await tester.tap(find.byKey(EditorScaffold.actionKey));
      await tester.pumpAndSettle();
      expect(library.activeSetlist?.name, 'Saturday');
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
