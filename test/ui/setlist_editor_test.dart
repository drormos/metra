import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/library_pick.dart';
import 'package:metra/src/ui/setlist_editor.dart';

import 'test_theme.dart';

void main() {
  late Directory dir;
  late LibraryController library;
  late Map<String, Song> songs;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_editor_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save started on the widget test's fake clock may still be
      // writing; a leftover temp folder is harmless.
    }
  });

  /// Library: Alpha, Bravo, Charlie, Delta; "Gig" = [Charlie, Alpha].
  /// Opens the editor for [editGig] or a new set, from a launcher page.
  Future<void> pumpEditor(
    WidgetTester tester, {
    bool editGig = true,
    Future<String?> Function(BuildContext)? newSong,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    songs = {
      for (final name in ['Charlie', 'Alpha', 'Delta', 'Bravo'])
        name: library.addSong(
          name: name,
          bpm: 100 + name.length,
          pattern: const MetronomePattern.standard(),
        ),
    };
    final gig = library.saveSetlist(
      name: 'Gig',
      songIds: [songs['Charlie']!.id, songs['Alpha']!.id],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openSetlistEditor(
                  context,
                  library,
                  setlist: editGig ? gig : null,
                  newSong: newSong ?? (_) async => null,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Setlist gig() => library.setlists.firstWhere((l) => l.name == 'Gig');
  List<String> names(Setlist set) => [
    for (final id in set.songIds) library.songById(id)!.name,
  ];

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(EditorScaffold.actionKey));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the set; nothing is saved until Save', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Setlist'), findsOneWidget);
    expect(find.text('2 songs'), findsOneWidget);
    expect(find.text('Charlie'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Charlie from setlist'));
    await tester.pump();
    expect(names(gig()), ['Charlie', 'Alpha'], reason: 'draft only');
    await save(tester);
    expect(names(gig()), ['Alpha']);
    expect(library.songs, hasLength(4), reason: 'removing keeps the song');
  });

  testWidgets('remove shows Removed with Undo', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byTooltip('Remove Charlie from setlist'));
    await tester.pumpAndSettle(); // snack bar slides in
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    await save(tester);
    expect(names(gig()), ['Charlie', 'Alpha']);
  });

  testWidgets('drag the handle to reorder', (tester) async {
    await pumpEditor(tester);
    final handle = find.byIcon(Icons.drag_handle).at(1); // Alpha's row
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump();
    for (var i = 0; i < 7; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    await save(tester);
    expect(names(gig()), ['Alpha', 'Charlie']);
  });

  testWidgets('rename and save', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField), 'Friday set');
    await tester.pump();
    await save(tester);
    expect(library.setlists.single.name, 'Friday set');
  });

  testWidgets('Cancel with changes asks to discard', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();
    await tester.tap(find.byKey(EditorScaffold.cancelKey));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.text('Setlist'), findsOneWidget, reason: 'still editing');
    await tester.tap(find.byKey(EditorScaffold.cancelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(gig().name, 'Gig');
  });

  testWidgets('Cancel without changes just closes', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(EditorScaffold.cancelKey));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('delete asks first and keeps the songs', (tester) async {
    await pumpEditor(tester);
    await tester.scrollUntilVisible(
      find.byKey(SetlistEditor.deleteKey),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(SetlistEditor.deleteKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('songs stay in your library'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(library.setlists, isEmpty);
    expect(library.songs, hasLength(4));
  });

  testWidgets('a new set: needs a name, can start with all songs, loads '
      'when saved', (tester) async {
    await pumpEditor(tester, editGig: false);
    expect(find.byKey(SetlistEditor.deleteKey), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(EditorScaffold.actionKey))
          .onPressed,
      isNull,
      reason: 'no name yet',
    );
    await tester.tap(find.text('Start with all songs'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'All');
    await tester.pump();
    await save(tester);
    final all = library.setlists.firstWhere((l) => l.name == 'All');
    expect(names(all), ['Alpha', 'Bravo', 'Charlie', 'Delta']);
    expect(library.activeSetlist?.name, 'All');
  });

  group('add songs (pick mode)', () {
    Future<void> openPick(WidgetTester tester) async {
      await tester.tap(find.byKey(SetlistEditor.addSongsKey));
      await tester.pumpAndSettle();
    }

    testWidgets('A-Z with "Already in this set"; adds checked songs', (
      tester,
    ) async {
      await pumpEditor(tester);
      await openPick(tester);
      expect(find.text('Add to Gig'), findsOneWidget);
      expect(find.text('Already in this set'), findsNWidgets(2));
      final add = find.byKey(LibraryPick.addKey);
      expect(tester.widget<FilledButton>(add).onPressed, isNull);

      await tester.tap(find.text('Delta'));
      await tester.tap(find.text('Alpha')); // again: allowed
      await tester.pump();
      expect(find.text('Add 2 songs'), findsOneWidget);
      await tester.tap(add);
      await tester.pumpAndSettle();
      await save(tester);
      expect(names(gig()), ['Charlie', 'Alpha', 'Alpha', 'Delta']);
    });

    testWidgets('search filters the list', (tester) async {
      await pumpEditor(tester);
      await openPick(tester);
      await tester.enterText(find.byType(TextField), 'ra');
      await tester.pump();
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Alpha'), findsNothing);
    });

    testWidgets('New song is created and checked', (tester) async {
      await pumpEditor(
        tester,
        newSong: (_) async => library
            .addSong(
              name: 'Echo',
              bpm: 90,
              pattern: const MetronomePattern.standard(),
            )
            .id,
      );
      await openPick(tester);
      await tester.tap(find.byKey(LibraryPick.newSongKey));
      await tester.pumpAndSettle();
      expect(find.text('Add 1 song'), findsOneWidget);
      await tester.tap(find.byKey(LibraryPick.addKey));
      await tester.pumpAndSettle();
      await save(tester);
      expect(names(gig()), ['Charlie', 'Alpha', 'Echo']);
    });

    testWidgets('Cancel adds nothing', (tester) async {
      await pumpEditor(tester);
      await openPick(tester);
      await tester.tap(find.text('Delta'));
      await tester.tap(find.byKey(EditorScaffold.cancelKey));
      await tester.pumpAndSettle();
      expect(find.text('2 songs'), findsOneWidget);
    });
  });
}
