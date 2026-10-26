import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/parts_page.dart';
import 'package:metra/src/ui/song_map.dart';
import 'package:metra/src/ui/top_panel.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/stage_screen.dart';
import 'package:metra/src/ui/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../audio/fake_click_output.dart';

/// Flutter's accessibility guidelines (Android tap targets, labeled tap
/// targets, text contrast) on the main screen, the panels, the sheets and
/// Settings, in both themes (ui-spec.md "Accessibility").
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'Metra',
      packageName: 'com.dror.metra',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  setUp(() => dir = Directory.systemTemp.createTempSync('metra_guidelines'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    required MetraColors colors,
    double textScale = 1,
    bool stage = false,
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    final ids = [
      for (final (name, bpm) in [
        ('Dead Weight', 120),
        ('Iron Lung', 98),
        ('Last Rites of the Northern Sea', 168),
      ])
        library
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
            )
            .id,
    ];
    final set = library.saveSetlist(name: 'Friday set', songIds: ids);
    library
      ..saveSetlist(name: 'Rehearsal', songIds: [ids.first])
      ..markSwipeHintSeen()
      ..markSongsHintSeen()
      ..loadSetlist(set.id, metronome)
      ..nextSong(metronome);
    await tester.pumpWidget(
      MaterialApp(
        theme: metraTheme(
          colors,
          colors == MetraColors.stageBlack ? Brightness.dark : Brightness.light,
        ),
        home: stage
            ? StageScreen(controller: metronome, library: library)
            : MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  final failures = <String>[];

  Future<void> checkAll(WidgetTester tester, String where) async {
    for (final (name, guideline) in [
      ('tap targets', androidTapTargetGuideline),
      ('labels', labeledTapTargetGuideline),
      ('contrast', textContrastGuideline),
    ]) {
      final result = await guideline.evaluate(tester);
      if (!result.passed) {
        // ignore: avoid_print
        print('A11Y FAIL [$where / $name]: ${result.reason}');
      }
      if (!result.passed) failures.add('$where / $name');
    }
  }

  for (final (theme, colors) in [
    ('dark', MetraColors.stageBlack),
    ('daylight', MetraColors.daylight),
  ]) {
    testWidgets('$theme: main screen, panels, sheets, Settings', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      failures.clear();
      await pump(tester, colors: colors);
      await checkAll(tester, '$theme main screen');

      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      await checkAll(tester, '$theme set panel');
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      await checkAll(tester, '$theme sets view');
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      await checkAll(tester, '$theme rhythm sheet');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      metronome.setOnStart(const OnStart(speedUp: true, stopOn: true));
      await tester.tap(find.byKey(MetronomeScreen.onStartKey));
      await tester.pumpAndSettle();
      await checkAll(tester, '$theme when I press Start');
      await tester.tapAt(const Offset(200, 700));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await checkAll(tester, '$theme settings');
      handle.dispose();
      expect(failures, isEmpty);
    });
  }

  // Large text: 100%, 130%, 200%; and the largest Display size (fewer
  // logical pixels: a 320dp-wide phone).
  for (final (scale, size) in [
    (1.0, const Size(412, 915)),
    (1.3, const Size(412, 915)),
    (2.0, const Size(412, 915)),
    (2.0, const Size(320, 690)),
  ]) {
    testWidgets('text at ${(scale * 100).round()}% on '
        '${size.width.toInt()}dp: nothing breaks anywhere', (tester) async {
      await pump(tester, colors: MetraColors.stageBlack, textScale: scale);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'main screen');
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'set panel');
      await tester.tap(find.byKey(QuickPick.changeSetKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'sets view');
      await tester.binding.handlePopRoute(); // back to the set's songs
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // the panel closes
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsNothing);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(find.byKey(TopPanel.surfaceKey), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'time signature sheet');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MetronomeScreen.onStartKey));
      await tester.pumpAndSettle();
      expect(find.byKey(TopPanel.surfaceKey), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'when I press Start');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MetronomeScreen.settingsKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'settings');
    });
  }

  // Stage mode: the guidelines in both themes, and large text.
  for (final (theme, colors) in [
    ('dark', MetraColors.stageBlack),
    ('daylight', MetraColors.daylight),
  ]) {
    testWidgets('$theme: stage mode', (tester) async {
      final handle = tester.ensureSemantics();
      failures.clear();
      await pump(tester, colors: colors, stage: true);
      await checkAll(tester, '$theme stage mode');
      handle.dispose();
      expect(failures, isEmpty);
      await tester.pump(const Duration(seconds: 6)); // the tip's timer
    });
  }
  for (final (scale, size) in [
    (2.0, const Size(412, 915)),
    (2.0, const Size(320, 690)),
  ]) {
    testWidgets('stage mode, text at ${(scale * 100).round()}% on '
        '${size.width.toInt()}dp: nothing breaks', (tester) async {
      await pump(
        tester,
        colors: MetraColors.stageBlack,
        textScale: scale,
        stage: true,
      );
      tester.view.physicalSize = size;
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 6));
    });
  }

  // The parts page, with two parts and the second one open.
  Future<void> openParts(WidgetTester tester) async {
    openPartsPage(
      tester.element(find.byType(SetlistGroup)),
      library,
      metronome,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PartsPage.addKey));
    await tester.pumpAndSettle();
  }

  for (final (theme, colors) in [
    ('dark', MetraColors.stageBlack),
    ('daylight', MetraColors.daylight),
  ]) {
    testWidgets('$theme: parts page', (tester) async {
      final handle = tester.ensureSemantics();
      failures.clear();
      await pump(tester, colors: colors);
      await openParts(tester);
      await checkAll(tester, '$theme parts page');
      handle.dispose();
      expect(failures, isEmpty);
    });
  }
  for (final (scale, size) in [
    (2.0, const Size(412, 915)),
    (2.0, const Size(320, 690)),
  ]) {
    testWidgets('parts page, text at ${(scale * 100).round()}% on '
        '${size.width.toInt()}dp: nothing breaks', (tester) async {
      await pump(tester, colors: MetraColors.stageBlack, textScale: scale);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      await openParts(tester);
      expect(tester.takeException(), isNull);
    });
  }

  // A song with parts: the song map in the ruler's slot.
  void withParts() => library.saveToSong(
    metronome..setParts([
      SongPart.steady(
        id: 'i',
        name: 'Intro',
        bars: 4,
        bpm: 100,
        pattern: const MetronomePattern.standard(),
      ),
      SongPart.steady(
        id: 'o',
        name: 'Outro',
        bars: 8,
        bpm: 120,
        pattern: const MetronomePattern.standard(),
      ),
    ]),
  );

  for (final (theme, colors) in [
    ('dark', MetraColors.stageBlack),
    ('daylight', MetraColors.daylight),
  ]) {
    testWidgets('$theme: main screen with parts', (tester) async {
      final handle = tester.ensureSemantics();
      failures.clear();
      await pump(tester, colors: colors);
      withParts();
      await tester.pumpAndSettle();
      expect(find.byType(SongMap), findsOneWidget);
      await checkAll(tester, '$theme main screen with parts');
      handle.dispose();
      expect(failures, isEmpty);
    });
  }
  testWidgets('main screen with parts, text at 200% on 320dp: nothing '
      'breaks', (tester) async {
    await pump(tester, colors: MetraColors.stageBlack, textScale: 2);
    tester.view.physicalSize = const Size(320, 690);
    withParts();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
