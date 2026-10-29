import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/share_export.dart';
import 'package:metra/src/platform/android_bridge.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/parts_page.dart';
import 'package:metra/src/ui/quick_pick.dart';
import 'package:metra/src/ui/setlist_group.dart';
import 'package:metra/src/ui/share_menu.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

/// Sharing sets and songs on screen (ui-spec.md "Sharing sets and songs").
void main() {
  late Directory dir;
  late MetronomeController metronome;
  late LibraryController library;
  late List<String> shared;
  String clipboard = '';

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_share'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing.
    }
  });

  /// "Fri" (One 100, Two 110) loaded at One; shares and the clipboard are
  /// caught.
  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    shared = [];
    final before = QuickPick.share;
    QuickPick.share = (text) async => shared.add(text);
    addTearDown(() => QuickPick.share = before);
    clipboard = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.getData'
          ? <String, Object?>{'text': clipboard}
          : null,
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
      for (final (name, bpm) in [('One', 100), ('Two', 110)])
        library
            .addSong(
              name: name,
              bpm: bpm,
              pattern: const MetronomePattern.standard(),
            )
            .id,
    ];
    final set = library.saveSetlist(name: 'Fri', songIds: ids);
    library.loadSetlist(set.id, metronome);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome, library: library),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> openSetPanel(WidgetTester tester) =>
      tap(tester, find.byKey(SetlistGroup.headerKey));

  /// The Songs list, in Single song on "One".
  Future<void> openSongs(WidgetTester tester) async {
    library.playSingleSong(library.songsAZ.first, metronome);
    await tester.pump();
    await tap(tester, find.byKey(SetlistGroup.songsKey));
  }

  String setExport(String name, List<Song> songs) =>
      exportSetText(Setlist(id: 'x', name: name, songIds: const []), songs);

  Song song(String name, int bpm) => Song(
    id: name,
    name: name,
    bpm: bpm,
    pattern: const MetronomePattern.standard(),
  );

  testWidgets('both share menus open upward from Share, centred on it '
      '(within 16px of the screen edges), 8px above it', (tester) async {
    await pump(tester);
    void check(Key button) {
      final at = tester.getRect(find.byKey(button));
      final menu = tester.getRect(find.byKey(shareMenuKey));
      expect(menu.bottom, moreOrLessEquals(at.top - 8), reason: '8px above');
      expect(menu.left, greaterThanOrEqualTo(16));
      expect(menu.right, lessThanOrEqualTo(400 - 16));
      final clamped = menu.left == 16 || menu.right == 400 - 16;
      if (!clamped) {
        expect(menu.center.dx, moreOrLessEquals(at.center.dx));
      }
    }

    await openSetPanel(tester);
    await tap(tester, find.byKey(QuickPick.shareKey));
    check(QuickPick.shareKey);
    await tester.tapAt(const Offset(200, 60)); // outside: closes
    await tester.pumpAndSettle();
    expect(find.byKey(shareMenuKey), findsNothing);
    expect(find.byType(QuickPick), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await openSongs(tester);
    await tap(tester, find.byKey(QuickPick.songsShareKey));
    check(QuickPick.songsShareKey);
  });

  testWidgets('Set ⌄ › Share › Export set: the whole set as a Metra export', (
    tester,
  ) async {
    await pump(tester);
    await openSetPanel(tester);
    await tap(tester, find.byKey(QuickPick.shareKey));
    expect(find.text(ShareMenus.forImport), findsOneWidget);
    await tap(tester, find.text('Export set'));
    final read = parseShared(shared.single)!;
    expect(read.setName, 'Fri');
    expect([for (final s in read.songs) s.name], ['One', 'Two']);
  });

  testWidgets('Songs list: "New song" · "Share" in the bottom row; Export a '
      'song… picks one (bar + Cancel, no search or Share meanwhile), a tap '
      'exports it and leaves; Cancel and Back leave too', (tester) async {
    await pump(tester);
    await openSongs(tester);
    final newSong = tester.getRect(find.byKey(QuickPick.newSongKey));
    final share = tester.getRect(find.byKey(QuickPick.songsShareKey));
    expect(newSong.size, share.size);
    expect(newSong.right, lessThan(share.left));

    Future<void> pick() async {
      await tap(tester, find.byKey(QuickPick.songsShareKey));
      await tap(tester, find.text('Export a song…'));
      expect(find.text(QuickPick.exportPickText), findsOneWidget);
      expect(find.byKey(QuickPick.songsShareKey), findsNothing);
    }

    await pick();
    await tap(tester, find.byKey(QuickPick.exportPickCancelKey));
    expect(find.text(QuickPick.exportPickText), findsNothing);
    expect(shared, isEmpty);

    await pick();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(QuickPick.exportPickText), findsNothing);
    expect(find.byType(QuickPick), findsOneWidget, reason: 'Back leaves it');

    await pick();
    await tap(
      tester,
      find.descendant(of: find.byType(QuickPick), matching: find.text('Two')),
    );
    expect(parseShared(shared.single)!.songs.single.name, 'Two');
    expect(find.text(QuickPick.exportPickText), findsNothing);
    expect(library.currentSong!.name, 'One', reason: 'nothing loaded');
  });

  testWidgets('Paste shared: the check ("1 song you already have, 1 new"), '
      'then Add set loads it at song 1 and closes the panel', (tester) async {
    await pump(tester);
    clipboard =
        'From the band:\n${setExport('Sat', [song('One', 100), song('Three', 120)])}';
    await openSetPanel(tester);
    await tap(tester, find.byKey(QuickPick.changeSetKey));
    await tap(tester, find.byKey(QuickPick.pasteSharedKey));
    expect(find.text('Add "Sat"?'), findsOneWidget);
    expect(find.text('2 songs.'), findsOneWidget);
    expect(find.text('1 song you already have, 1 new.'), findsOneWidget);
    await tap(tester, find.byKey(ShareDialogKeys.add));
    expect(library.activeSetlist!.name, 'Sat');
    expect(library.currentIndex, 0);
    expect(library.songs.map((s) => s.name), ['One', 'Two', 'Three']);
    expect(find.byType(QuickPick), findsNothing);
  });

  testWidgets('nothing Metra-shaped: "Nothing to add"; the same set again: '
      '"You already have this set", and it opens', (tester) async {
    await pump(tester);
    clipboard = 'see you at 8';
    await openSetPanel(tester);
    await tap(tester, find.byKey(QuickPick.shareKey));
    await tap(tester, find.text('Import a set'));
    expect(find.text(ShareMenus.nothing), findsOneWidget);
    expect(find.text(ShareMenus.nothingLine), findsOneWidget);
    await tap(tester, find.byKey(ShareDialogKeys.ok));
    expect(library.setlists, hasLength(1));
    expect(find.byType(QuickPick), findsOneWidget, reason: 'stays open');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    clipboard = setExport('Fri', library.visibleSongs);
    library.playSingleSong(library.songsAZ.last, metronome);
    await tester.pump();
    await tap(tester, find.byKey(SetlistGroup.songsKey));
    await tap(tester, find.byKey(QuickPick.songsShareKey));
    await tap(tester, find.text('Import a song'));
    expect(find.text('You already have this set'), findsOneWidget);
    await tap(tester, find.byKey(ShareDialogKeys.ok));
    expect(library.activeSetlist!.name, 'Fri');
    expect(library.setlists, hasLength(1));
    expect(library.songs, hasLength(2));
  });

  testWidgets('a song with the same name and different music arrives as '
      '"(shared)" and loads in Single song', (tester) async {
    await pump(tester);
    clipboard = exportSongText(song('One', 150));
    await openSongs(tester);
    await tap(tester, find.byKey(QuickPick.songsShareKey));
    await tap(tester, find.text('Import a song'));
    expect(
      find.text('"One" is different from yours: added as "One (shared)".'),
      findsOneWidget,
    );
    await tap(tester, find.byKey(ShareDialogKeys.add));
    expect(library.currentSong!.name, 'One (shared)');
    expect(library.singleSong, isTrue);
    expect(metronome.bpm, 150);
    expect(library.songById(library.songsAZ.first.id)!.bpm, 100);
  });

  testWidgets('shared to Metra from another app: the check opens on the '
      'main screen', (tester) async {
    await pump(tester);
    AndroidBridge.sharedText.value = setExport('Sun', [song('Four', 90)]);
    await tester.pumpAndSettle();
    expect(find.text('Add "Sun"?'), findsOneWidget);
    expect(AndroidBridge.sharedText.value, isNull, reason: 'taken once');
    await tap(tester, find.byKey(ShareDialogKeys.cancel));
    expect(library.setlists, hasLength(1), reason: 'Cancel adds nothing');
  });

  testWidgets('parts page: "Share this song" exports the song as it is '
      'there; not in unsaved Free play', (tester) async {
    await pump(tester);
    final context = tester.element(find.byType(SetlistGroup));
    openPartsPage(context, library, metronome);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(PartsPage.shareSongKey),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tap(tester, find.byKey(PartsPage.shareSongKey));
    expect(parseShared(shared.single)!.songs.single.name, 'One');
    await tester.pageBack();
    await tester.pumpAndSettle();

    library.detachSong();
    await tester.pump();
    openPartsPage(context, library, metronome);
    await tester.pumpAndSettle();
    expect(find.byKey(PartsPage.shareSongKey), findsNothing);
  });
}
