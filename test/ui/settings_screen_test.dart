import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/click_volumes.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/about.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/setlist_picker.dart';
import 'package:metra/src/ui/settings_screen.dart';
import 'package:metra/src/ui/song_library.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late Directory dir;
  late FakeClickOutput output;
  late MetronomeController metronome;
  late LibraryController library;

  setUpAll(
    () => PackageInfo.setMockInitialValues(
      appName: 'Metra',
      packageName: 'com.example.metra',
      version: '1.2.3',
      buildNumber: '7',
      buildSignature: '',
    ),
  );
  setUp(() => dir = Directory.systemTemp.createTempSync('metra_settings'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  /// The main screen with two setlists and three songs, then Settings.
  Future<void> openSettingsScreen(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    output = FakeClickOutput();
    metronome = MetronomeController(output);
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    library.attach(metronome);
    for (final name in ['One', 'Two', 'Three']) {
      library.addSong(
        name: name,
        bpm: 100,
        pattern: const MetronomePattern.standard(),
      );
    }
    library
      ..addSetlist('Friday set')
      ..addSetlist('Rehearsal');
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
  }

  /// Scrolls settings until [finder] is built and on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ),
    );
    // Not pumpAndSettle: while playing, the flash animates every frame.
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('fits a small phone; every section is reachable', (tester) async {
    await openSettingsScreen(tester, size: const Size(320, 568));
    await tapVisible(tester, find.byKey(SettingsScreen.vibrateKey));
    expect(library.vibrate, isFalse);
    await reveal(tester, find.byKey(SettingsScreen.testKey));
    await reveal(tester, find.byKey(SettingsScreen.versionKey));
  });

  testWidgets('About: the version line, copied on long-press', (tester) async {
    final copied = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openSettingsScreen(tester);
    await reveal(tester, find.byKey(SettingsScreen.versionKey));
    expect(find.text('Metra 1.2.3 (7)'), findsOneWidget);
    await tester.longPress(find.byKey(SettingsScreen.versionKey));
    await tester.pump();
    expect(copied, [
      {'text': 'Metra 1.2.3 (7)'},
    ]);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('About Metra opens the note', (tester) async {
    await openSettingsScreen(tester);
    await tapVisible(tester, find.byKey(SettingsScreen.aboutKey));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(AboutScreen.promise), findsOneWidget);
  });

  test(
    'the feedback email: address, subject, body starts with the version',
    () async {
      final uri = await feedbackUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'dror945@gmail.com');
      expect(uri.query, isNot(contains('+')), reason: 'spaces as %20');
      final params = Uri.splitQueryString(uri.query);
      expect(params['subject'], 'Metra feedback (v1.2.3 build 7)');
      expect(params['body'], startsWith('Metra 1.2.3 (7)\n'));
      expect(params['body'], endsWith('\n\n'));
    },
  );

  testWidgets('Your music: counts, Setlists and Song library', (tester) async {
    await openSettingsScreen(tester);
    expect(find.text('2 setlists'), findsOneWidget);
    expect(find.text('3 songs'), findsOneWidget);
    await tester.tap(find.text('Setlists'));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.byType(SetlistPicker), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.text('Song library'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsOneWidget);
  });

  testWidgets('loading from Settings > Setlists lands on the main screen', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await tester.tap(find.text('Setlists'));
    await tester.pumpAndSettle();
    final friday = library.setlists.firstWhere((l) => l.name == 'Friday set');
    await tester.tap(find.byKey(ValueKey('picker-set-${friday.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistPicker), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing, reason: 'Settings too');
    expect(library.activeSetlist?.id, friday.id);
  });

  testWidgets('Free play from Settings > Setlists lands on the main screen', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await tester.tap(find.text('Setlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SetlistPicker.freePlayKey));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsNothing);
  });

  testWidgets('theme and click sound apply at once', (tester) async {
    await openSettingsScreen(tester);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(library.themeMode, ThemeMode.dark);
    await tester.tap(find.byKey(const ValueKey('sound-cowbell')));
    await tester.pump();
    expect(metronome.clickSound, ClickSound.cowbell);
    expect(output.previewCount, 1, reason: 'a sample while stopped');
  });

  testWidgets('volume sliders; Reset restores only the volumes', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    final accent = find.byType(Slider).first;
    await reveal(tester, accent);
    await tester.drag(accent, const Offset(-120, 0));
    await tester.pump();
    expect(metronome.volumes.accent, lessThan(1));
    expect(output.currentVolumes, metronome.volumes);
    library.setThemeMode(ThemeMode.dark);
    await tapVisible(tester, find.byKey(SettingsScreen.resetKey));
    expect(metronome.volumes, ClickVolumes.defaults);
    expect(library.themeMode, ThemeMode.dark, reason: 'not reset');
  });

  testWidgets('visual offset −/+ in 10 ms steps', (tester) async {
    await openSettingsScreen(tester);
    await tapVisible(tester, find.byTooltip('Flash later'));
    await tester.tap(find.byTooltip('Flash later'));
    await tester.pump();
    expect(metronome.visualOffset, const Duration(milliseconds: 20));
    expect(
      tester.widget<Text>(find.byKey(SettingsScreen.offsetKey)).data,
      '+20 ms',
    );
    await tester.tap(find.byTooltip('Flash earlier'));
    await tester.pump();
    expect(metronome.visualOffset, const Duration(milliseconds: 10));
  });

  testWidgets('the test starts the click; leaving stops what it started', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await tapVisible(tester, find.byKey(SettingsScreen.testKey));
    expect(metronome.isPlaying, isTrue);
    expect(find.text('Stop test'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200)); // flashing
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(metronome.isPlaying, isFalse);
  });

  testWidgets('with the click already playing, leaving keeps it', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await metronome.play();
    await reveal(tester, find.byKey(SettingsScreen.testKey));
    expect(find.text('Stop test'), findsOneWidget, reason: 'uses the click');
    await tester.tap(find.byTooltip('Back').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(metronome.isPlaying, isTrue);
    metronome.stop();
    await tester.pump();
  });
}
