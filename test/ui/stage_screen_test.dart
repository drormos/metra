import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/main.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/stage_screen.dart';

import '../audio/fake_click_output.dart';

/// Stage mode (ui-spec.md "Stage mode").
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;
  late List<String> systemCalls;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_stage'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save may still be writing; harmless.
    }
  });

  /// "Friday set" with four songs, loaded at the first; [stage] enters
  /// stage mode before the app starts; [tipSeen] skips the one-time tip.
  Future<void> pump(
    WidgetTester tester, {
    bool stage = true,
    bool tipSeen = true,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 860)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    systemCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        systemCalls.add('${call.method} ${call.arguments}');
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
      for (final (name, bpm) in [
        ('One', 100),
        ('Two', 110),
        ('Three', 120),
        ('Four', 130),
      ])
        library
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
              onStart: const OnStart(countInOn: true),
            )
            .id,
    ];
    final set = library.saveSetlist(name: 'Friday set', songIds: ids);
    library
      ..markSwipeHintSeen()
      ..loadSetlist(set.id, metronome);
    if (tipSeen) library.markTipSeen(LibraryController.stageTip);
    if (stage) library.enterStageMode();
    await tester.pumpWidget(MetraApp(controller: metronome, library: library));
  }

  String hint(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(StageScreen.hintKey)).data!;
  String title(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(StageScreen.titleKey)).data!;

  /// Counts the songs actually loaded (each restarts the click if playing).
  List<String> loads() {
    final loaded = <String>[];
    var last = library.currentSong?.name;
    library.addListener(() {
      final now = library.currentSong?.name;
      if (now != last) loaded.add(now!);
      last = now;
    });
    return loaded;
  }

  testWidgets('entered only from a set, from the set panel; the song and '
      'the click stay', (tester) async {
    await pump(tester, stage: false);
    library.nextSong(metronome); // Two
    await tester.pump();
    await tester.tap(find.byKey(SetlistGroup.headerKey));
    await tester.pumpAndSettle();
    expect(find.byKey(QuickPick.stageModeKey), findsOneWidget);
    await tester.tap(find.byKey(QuickPick.stageModeKey));
    await tester.pumpAndSettle();
    expect(find.byType(StageScreen), findsOneWidget);
    expect(title(tester), 'Two');
    expect(find.text('Friday set · 2 of 4'), findsOneWidget);
    expect(library.stageMode, isTrue);
    expect(
      systemCalls,
      contains(contains('SystemChrome.setEnabledSystemUIMode')),
    );

    // Not in Free play: stage mode can't start without a set.
    library
      ..exitStageMode()
      ..detachSong()
      ..enterStageMode();
    await tester.pumpAndSettle();
    expect(library.stageMode, isFalse);
    expect(find.byType(MetronomeScreen), findsOneWidget);
  });

  testWidgets('shows the song, position, BPM and Start-related line; '
      'Previous reads "Start of set" on the first song', (tester) async {
    await pump(tester);
    expect(title(tester), 'One');
    expect(find.text('Friday set · 1 of 4'), findsOneWidget);
    expect(find.text('4/4 · count-in 1 bar'), findsOneWidget);
    expect(find.text('Start of set'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget); // on Next
    await tester.tap(find.byKey(StageScreen.previousKey));
    await tester.pump(const Duration(seconds: 1));
    expect(title(tester), 'One', reason: 'inert');
  });

  testWidgets('stopped: each tap loads at once; a bounce (< 0.12 s) is '
      'ignored, rapid taps are not', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(StageScreen.nextKey));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(StageScreen.nextKey)); // bounce
    await tester.pump(const Duration(milliseconds: 200));
    expect(library.currentSong!.name, 'Two');
    await tester.tap(find.byKey(StageScreen.nextKey)); // 0.25 s later
    await tester.pump(const Duration(milliseconds: 200));
    expect(library.currentSong!.name, 'Three');
    expect(metronome.isPlaying, isFalse);
  });

  testWidgets('playing: the shown song moves with every tap; the click '
      'restarts once, 0.3 s after the last tap', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(StageScreen.playKey));
    await tester.pump();
    expect(metronome.isPlaying, isTrue);
    final loaded = loads();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(StageScreen.nextKey));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(title(tester), 'Four');
    expect(find.text('End of set'), findsOneWidget);
    expect(loaded, isEmpty, reason: 'still tapping');
    await tester.pump(const Duration(milliseconds: 200));
    expect(loaded, ['Four']);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 130);
    metronome.stop();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Stop during a run of taps loads the shown song, stopped', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(StageScreen.playKey));
    await tester.pump();
    await tester.tap(find.byKey(StageScreen.nextKey));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(StageScreen.playKey));
    await tester.pump();
    expect(metronome.isPlaying, isFalse);
    expect(library.currentSong!.name, 'Two');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the position opens the set read-only: tap jumps', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(StageScreen.positionKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stage-song-2')));
    await tester.pumpAndSettle();
    expect(library.currentSong!.name, 'Three');
    expect(title(tester), 'Three');
  });

  group('leaving', () {
    testWidgets('a 1 s hold exits to the main screen, same song, click '
        'unchanged', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(StageScreen.playKey));
      await tester.pump();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(StageScreen.exitKey)),
      );
      await tester.pump(); // the hold's first frame
      await tester.pump(const Duration(milliseconds: 500));
      expect(hint(tester), StageScreen.holdingHint);
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // still playing
      expect(find.byType(MetronomeScreen), findsOneWidget);
      expect(library.stageMode, isFalse);
      expect(library.currentSong!.name, 'One');
      expect(metronome.isPlaying, isTrue);
      metronome.stop();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('releasing early resets and shows the hint', (tester) async {
      await pump(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(StageScreen.exitKey)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();
      expect(hint(tester), StageScreen.holdHint);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(StageScreen), findsOneWidget, reason: 'reset');
      await tester.tap(find.byKey(StageScreen.exitKey)); // a plain tap
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StageScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Android Back never leaves; it shows the hint', (tester) async {
      await pump(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(StageScreen), findsOneWidget);
      expect(hint(tester), StageScreen.holdHint);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('the Do Not Disturb tip shows once, on first entry', (
    tester,
  ) async {
    await pump(tester, tipSeen: false);
    expect(hint(tester), StageScreen.tipText);
    expect(library.tipSeen(LibraryController.stageTip), isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(hint(tester), '');
  });

  test('remembered across a relaunch until exited, on the same song', () async {
    Future<LibraryController> load() =>
        LibraryController.load(LibraryStore(File('${dir.path}/library.json')));
    final first = await load();
    final player = MetronomeController(FakeClickOutput());
    addTearDown(player.dispose);
    final ids = [
      for (final (name, bpm) in [('One', 100), ('Two', 110)])
        first
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
            )
            .id,
    ];
    final set = first.saveSetlist(name: 'Friday set', songIds: ids);
    first
      ..loadSetlist(set.id, player)
      ..nextSong(player) // Two
      ..enterStageMode();
    await first.flush();

    final again = await load();
    expect(again.stageMode, isTrue);
    final fresh = MetronomeController(FakeClickOutput());
    addTearDown(fresh.dispose);
    again
      ..attach(fresh)
      ..resumeStageMode(fresh);
    expect(again.currentSong!.name, 'Two');
    expect(fresh.bpm, 110);
    again.exitStageMode();
    await again.flush();
    expect((await load()).stageMode, isFalse);
  });
}
