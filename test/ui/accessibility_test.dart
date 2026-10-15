import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/main.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/setlist_picker.dart';
import 'package:metra/src/ui/song_editor.dart';
import 'package:metra/src/ui/song_library.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

/// ui-spec.md "Android basics": every button has a screen-reader label,
/// and large system fonts don't break the main screen.
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;

  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'Metra',
      packageName: 'com.example.metra',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );
  setUp(() => dir = Directory.systemTemp.createTempSync('metra_a11y'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    double textScale = 1,
    bool loaded = true,
  }) async {
    tester.view
      ..physicalSize = size
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
      for (final (name, bpm) in [('Dead Weight', 120), ('Iron Lung', 98)])
        library
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
            )
            .id,
    ];
    final set = library.saveSetlist(name: 'Friday set', songIds: ids);
    if (loaded) {
      library.loadSetlist(set.id, metronome);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  Future<void> expectLabeled(WidgetTester tester) async {
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  }

  testWidgets('main screen, setlist mode', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await expectLabeled(tester);
    handle.dispose();
  });

  testWidgets('main screen, Free play, and its dropdowns', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, loaded: false);
    await expectLabeled(tester);
    await tester.tap(find.byKey(SetlistGroup.songsKey));
    await tester.pumpAndSettle();
    await expectLabeled(tester);
    handle.dispose();
  });

  testWidgets('Menu', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await expectLabeled(tester);
    handle.dispose();
  });

  testWidgets('set page, song library, song editor', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    final context = tester.element(find.byType(SetlistGroup));
    openSetlists(
      context,
      library: library,
      metronome: metronome,
      setId: library.activeSetlist!.id,
    );
    await tester.pumpAndSettle();
    await expectLabeled(tester);
    Navigator.pop(tester.element(find.byType(SetlistPicker)));
    await tester.pumpAndSettle();
    openSongLibrary(context, library, metronome);
    await tester.pumpAndSettle();
    await expectLabeled(tester);
    openSongEditor(context, library, metronome, song: library.songs.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SongEditor.patternKey));
    await tester.pumpAndSettle();
    await expectLabeled(tester);
    handle.dispose();
  });

  for (final size in [const Size(360, 640), const Size(400, 900)]) {
    testWidgets('the main screen survives 2x system text '
        '(${size.width.toInt()}x${size.height.toInt()})', (tester) async {
      await pump(tester, size: size, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(SetlistGroup.headerKey));
      await tester.pumpAndSettle();
      expect(find.byType(QuickPick), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('left to right, even on a Hebrew phone', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('he', 'IL');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final controller = MetronomeController(FakeClickOutput());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MetraApp(controller: controller));
    expect(
      Directionality.of(tester.element(find.byType(MetronomeScreen))),
      TextDirection.ltr,
    );
  });
}
