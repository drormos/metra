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
import 'package:metra/src/model/whats_new.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/about.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/settings_screen.dart';

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

  /// The main screen with two setlists and three songs, then Settings
  /// from the gear.
  Future<void> openSettingsScreen(
    WidgetTester tester, {
    Size size = const Size(400, 900),
    bool open = true,
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
    if (!open) return;
    await tester.tap(find.byKey(MetronomeScreen.settingsKey));
    await tester.pumpAndSettle();
  }

  /// Back on the main screen: no page over it.
  void expectMain() {
    expect(find.byType(SettingsScreen), findsNothing);
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

  testWidgets('the gear opens Settings directly; About is its last section; '
      'Back returns to the main screen; the click keeps playing', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await metronome.play();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Your music'), findsNothing);
    await reveal(tester, find.byKey(SettingsScreen.versionKey));
    for (final text in [
      'About',
      'Send feedback',
      "Tell Dror what works and what doesn't",
      'All updates',
      'About Metra',
      'Why this app exists',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    double top(Key key) => tester.getTopLeft(find.byKey(key)).dy;
    expect(
      top(SettingsScreen.feedbackKey),
      lessThan(top(SettingsScreen.allUpdatesRowKey)),
    );
    expect(
      top(SettingsScreen.allUpdatesRowKey),
      lessThan(top(SettingsScreen.aboutKey)),
    );
    expect(
      top(SettingsScreen.aboutKey),
      lessThan(top(SettingsScreen.versionKey)),
    );
    expect(
      tester.getSize(find.byKey(SettingsScreen.aboutKey)).height,
      greaterThanOrEqualTo(56),
    );
    await tester.binding.handlePopRoute();
    // Not pumpAndSettle: while playing, the beat blocks animate every frame.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
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

  testWidgets('About Metra opens the note; Back to Settings, then main', (
    tester,
  ) async {
    await openSettingsScreen(tester);
    await tapVisible(tester, find.byKey(SettingsScreen.aboutKey));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(AboutScreen.promise), findsOneWidget);
    expect(find.text('All updates'), findsNothing, reason: 'in Settings');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
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

  testWidgets('theme and click sound apply at once', (tester) async {
    await openSettingsScreen(tester);
    // Woodblock · Beep / Cowbell · Bell, Woodblock selected by default.
    final grid = [
      for (final name in ['woodblock', 'beep', 'cowbell', 'bell'])
        tester.getRect(find.byKey(ValueKey('sound-$name'))),
    ];
    expect(grid[0].top, grid[1].top);
    expect(grid[2].top, grid[3].top);
    expect(grid[2].top, greaterThan(grid[0].top));
    expect(grid[0].left, lessThan(grid[1].left));
    expect(find.text('Classic'), findsNothing);
    expect(metronome.clickSound, ClickSound.woodblock);
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

  group("What's new", () {
    setUp(
      () => WhatsNew.releases = WhatsNew.parse('''
## 1.4.0 · Oct 2026
- One
- Two
- Three
- Four

## 1.0–1.3 · Sep–Oct 2026
- Test builds
'''),
    );
    tearDown(() => WhatsNew.releases = const []);

    testWidgets('after an update: a dot on the gear; Settings shows the '
        'block on top (3 lines); opening clears the dot; "Got it" hides it', (
      tester,
    ) async {
      await openSettingsScreen(tester, open: false);
      expect(find.byKey(MetronomeScreen.updateDotKey), findsOneWidget);
      expect(find.byTooltip('Settings, new update'), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.settingsKey));
      await tester.pumpAndSettle();
      expect(find.text('New in 1.4.0'), findsOneWidget);
      expect(find.text('Three'), findsOneWidget);
      expect(find.text('Four'), findsNothing, reason: 'up to 3 lines');
      expect(
        tester.getTopLeft(find.byKey(SettingsScreen.whatsNewKey)).dy,
        lessThan(tester.getTopLeft(find.text('Theme')).dy),
        reason: 'at the top',
      );
      await tester.tap(find.byKey(SettingsScreen.gotItKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SettingsScreen.whatsNewKey), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(MetronomeScreen.updateDotKey), findsNothing);
      await tester.tap(find.byKey(MetronomeScreen.settingsKey));
      await tester.pumpAndSettle();
      expect(
        find.byKey(SettingsScreen.whatsNewKey),
        findsNothing,
        reason: 'gone',
      );
    });

    testWidgets('opening Settings clears the dot, the block stays until '
        '"Got it"', (tester) async {
      await openSettingsScreen(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(MetronomeScreen.updateDotKey), findsNothing);
      await tester.tap(find.byKey(MetronomeScreen.settingsKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SettingsScreen.whatsNewKey), findsOneWidget);
    });

    testWidgets('"All updates ›": every version, newest first; also the '
        'About row', (tester) async {
      await openSettingsScreen(tester);
      await tester.tap(find.byKey(SettingsScreen.allUpdatesKey));
      await tester.pumpAndSettle();
      expect(find.byType(AllUpdatesScreen), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('1.4.0 · Oct 2026')).dy,
        lessThan(tester.getTopLeft(find.text('1.0–1.3 · Sep–Oct 2026')).dy),
      );
      expect(find.text('·  Four'), findsOneWidget, reason: 'all lines');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget, reason: 'back');
      await tapVisible(tester, find.byKey(SettingsScreen.allUpdatesRowKey));
      await tester.pumpAndSettle();
      expect(find.byType(AllUpdatesScreen), findsOneWidget);
    });

    testWidgets('a fresh install: no dot, no block', (tester) async {
      await openSettingsScreen(tester, open: false);
      WhatsNew.markSeen(library);
      await tester.pump();
      expect(find.byKey(MetronomeScreen.updateDotKey), findsNothing);
      await tester.tap(find.byKey(MetronomeScreen.settingsKey));
      await tester.pumpAndSettle();
      expect(find.byKey(SettingsScreen.whatsNewKey), findsNothing);
    });
  });
}
