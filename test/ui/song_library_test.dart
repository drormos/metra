import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/play_marker.dart';
import 'package:metra/src/ui/song_editor.dart';
import 'package:metra/src/ui/song_library.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late Directory dir;
  late LibraryController library;
  late MetronomeController metronome;

  setUp(() => dir = Directory.systemTemp.createTempSync('metra_library_test'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  /// Songs added in this order: Charlie, alpha, Bravo, Delta. Alpha is in
  /// three sets, Bravo in two, Charlie in one, Delta in none.
  Future<void> pumpLibrary(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    final songs = {
      for (final (name, bpm) in [
        ('Charlie', 90),
        ('alpha', 100),
        ('Bravo', 110),
        ('Delta', 120),
      ])
        name: library.addSong(
          name: name,
          bpm: bpm,
          pattern: const MetronomePattern.standard(),
        ),
    };
    String id(String name) => songs[name]!.id;
    library
      ..saveSetlist(name: 'Friday set', songIds: [id('alpha'), id('Bravo')])
      ..saveSetlist(name: 'Rehearsal', songIds: [id('alpha'), id('Bravo')])
      ..saveSetlist(name: 'Gig', songIds: [id('alpha'), id('Charlie')]);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => openSongLibrary(context, library, metronome),
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

  List<String> listed(WidgetTester tester) => [
    for (final row in tester.widgetList<InkWell>(
      find.byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('library-'),
      ),
    ))
      library.songById((row.key! as ValueKey<String>).value.substring(8))!.name,
  ];

  testWidgets('A–Z with the setlists that use each song', (tester) async {
    await pumpLibrary(tester);
    expect(find.text('4 songs'), findsOneWidget);
    expect(listed(tester), ['alpha', 'Bravo', 'Charlie', 'Delta']);
    expect(find.text('3 setlists'), findsOneWidget);
    expect(find.text('Friday set, Rehearsal'), findsOneWidget);
    expect(find.text('Gig'), findsOneWidget);
    expect(find.text('Not in a setlist'), findsOneWidget);
  });

  testWidgets('a play marker on every row, filled for the loaded song', (
    tester,
  ) async {
    await pumpLibrary(tester);
    final markers = find.byType(PlayMarker);
    expect(markers, findsNWidgets(4));
    expect(
      tester.widgetList<PlayMarker>(markers).where((m) => m.current),
      isEmpty,
    );
    library.playSong(library.songsAZ.last, metronome); // Delta
    await tester.pump();
    final current = find.byWidgetPredicate((w) => w is PlayMarker && w.current);
    expect(current, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('library-${library.songsAZ.last.id}')),
        matching: current,
      ),
      findsOneWidget,
    );
  });

  testWidgets('search filters by name, ignoring case', (tester) async {
    await pumpLibrary(tester);
    await tester.enterText(find.byType(TextField), 'A');
    await tester.pump();
    expect(listed(tester), ['alpha', 'Bravo', 'Charlie', 'Delta']);
    await tester.enterText(find.byType(TextField), 'ra');
    await tester.pump();
    expect(listed(tester), ['Bravo']);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No songs match.'), findsOneWidget);
  });

  testWidgets('sorts by recently edited', (tester) async {
    await pumpLibrary(tester);
    library.updateSong(library.songsAZ[2]); // Charlie, edited just now
    await tester.tap(find.byKey(SongLibrary.sortKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recently edited').last);
    await tester.pumpAndSettle();
    expect(listed(tester).first, 'Charlie');
  });

  testWidgets('tapping a row loads the song and closes the library', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('Delta'));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsNothing);
    expect(library.currentSong!.name, 'Delta');
    expect(metronome.bpm, 120);
  });

  testWidgets('the pencil opens the song editor; saving updates the list', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tester.tap(find.byTooltip('Edit Delta'));
    await tester.pumpAndSettle();
    expect(find.byType(SongEditor), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Echo');
    await tester.tap(find.byKey(EditorScaffold.actionKey));
    await tester.pumpAndSettle();
    expect(find.byType(SongLibrary), findsOneWidget);
    expect(listed(tester).last, 'Echo');
  });

  testWidgets('New song opens the editor on a new song', (tester) async {
    await pumpLibrary(tester);
    metronome.setBpm(87); // a new song starts at the main screen's tempo
    await tester.tap(find.byKey(SongLibrary.newSongKey));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Song 1'), findsOneWidget);
    await tester.tap(find.byKey(EditorScaffold.actionKey));
    await tester.pumpAndSettle();
    expect(find.text('5 songs'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
    expect(library.songs.firstWhere((s) => s.name == 'Song 1').bpm, 87);
  });

  test('usage line', () {
    Setlist set(String name) => Setlist(id: name, name: name, songIds: []);
    expect(SongLibrary.usage([]), 'Not in a setlist');
    expect(SongLibrary.usage([set('A')]), 'A');
    expect(SongLibrary.usage([set('A'), set('B')]), 'A, B');
    expect(SongLibrary.usage([set('A'), set('B'), set('C')]), '3 setlists');
  });
}
