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
import 'package:metra/src/ui/menu_panel.dart';
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
      packageName: 'com.dror.metra',
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

  /// The main screen with two setlists and three songs, then the Menu.
  Future<void> openMenu(
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

  /// Then Menu → Settings.
  Future<void> openSettingsScreen(
    WidgetTester tester, {
    Size size = const Size(400, 900),
  }) async {
    await openMenu(tester, size: size);
    await tester.tap(find.byKey(MenuPanel.settingsKey));
    await tester.pumpAndSettle();
  }

  /// Back on the main screen: no panel, no page over it.
  void expectMain() {
    expect(find.byType(MenuPanel), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(SetlistPicker), findsNothing);
    expect(find.byType(SongLibrary), findsNothing);
    expect(find.byType(MetronomeScreen), findsOneWidget);
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
  });

  testWidgets('Settings: only sound, volume, theme and the offset', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    expect(find.text('Settings'), findsOneWidget);
    for (final gone in ['Your music', 'About', 'Send feedback']) {
      expect(find.text(gone), findsNothing);
    }
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expectMain();
  });

  testWidgets('the Menu panel: rows, counts; closes on outside tap, swipe, '
      'back; the click keeps playing', (tester) async {
    await openMenu(tester);
    await metronome.play();
    // Not pumpAndSettle: while playing, the beat blocks animate every frame.
    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    final panel = tester.getRect(find.byKey(MenuPanel.surfaceKey));
    expect(panel.width, MenuPanel.width);
    expect(panel.right, 400, reason: 'from the right');
    for (final text in [
      'Menu',
      'Your music',
      'Song library',
      'Setlists',
      'Settings',
      'Sound, volume, theme',
      'Send feedback',
      'About Metra',
    ]) {
      expect(
        find.descendant(of: find.byType(MenuPanel), matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(MenuPanel.songLibraryKey),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(MenuPanel.setlistsKey),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 450));
    await settle();
    expectMain();
    await tester.tap(find.byTooltip('Menu'));
    await settle();
    await tester.fling(
      find.byKey(MenuPanel.surfaceKey),
      const Offset(200, 0),
      1000,
    );
    await settle();
    expectMain();
    await tester.tap(find.byTooltip('Menu'));
    await settle();
    await tester.binding.handlePopRoute();
    await settle();
    expectMain();
    expect(metronome.isPlaying, isTrue);
    metronome.stop();
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
    await openMenu(tester);
    expect(find.text('Metra 1.2.3 (7)'), findsOneWidget);
    await tester.longPress(find.byKey(MenuPanel.versionKey));
    await tester.pump();
    expect(copied, [
      {'text': 'Metra 1.2.3 (7)'},
    ]);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('About Metra opens the note; back returns to main', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.byKey(MenuPanel.aboutKey));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.byType(MenuPanel), findsNothing, reason: 'the panel closed');
    expect(find.text(AboutScreen.promise), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsNothing);
    expectMain();
  });

  test(
    'the feedback email: address, subject, body starts with the version',
    () async {
      final uri = await feedbackUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'metra.application@gmail.com');
      expect(uri.query, isNot(contains('+')), reason: 'spaces as %20');
      final params = Uri.splitQueryString(uri.query);
      expect(params['subject'], 'Metra feedback (v1.2.3 build 7)');
      expect(params['body'], startsWith('Metra 1.2.3 (7)\n'));
      expect(params['body'], endsWith('\n\n'));
    },
  );

  testWidgets('Your music: Setlists and Song library; back to main', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.byKey(MenuPanel.setlistsKey));
    await tester.pumpAndSettle();
    expect(find.text('What to play'), findsOneWidget);
    expect(find.byType(SetlistPicker), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expectMain();
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(MenuPanel.songLibraryKey));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expectMain();
  });

  testWidgets('loading from Menu > Setlists lands on the main screen', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.byKey(MenuPanel.setlistsKey));
    await tester.pumpAndSettle();
    final friday = library.setlists.firstWhere((l) => l.name == 'Friday set');
    await tester.tap(find.byKey(ValueKey('picker-set-${friday.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(SetlistPicker), findsNothing);
    expectMain();
    expect(library.activeSetlist?.id, friday.id);
  });

  testWidgets('Free play from Menu > Setlists lands on the main screen', (
    tester,
  ) async {
    await openMenu(tester);
    await tester.tap(find.byKey(MenuPanel.setlistsKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SetlistPicker.freePlayKey));
    await tester.pumpAndSettle();
    expectMain();
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
    expect(find.byType(Slider), findsNWidgets(4));
    expect(find.text('Polyrhythm'), findsOneWidget);
    metronome.setVolumes(metronome.volumes.copyWith(polyrhythm: 0.2));
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
