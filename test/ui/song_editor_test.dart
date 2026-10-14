import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/library.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/editor_scaffold.dart';
import 'package:metra/src/ui/song_editor.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late Directory dir;
  late LibraryController library;
  late MetronomeController metronome;
  late Song alpha;
  Song? result;
  var closed = false;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('metra_song_editor_test');
    result = null;
    closed = false;
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing; harmless.
    }
  });

  /// Library: Alpha (100 bpm, 4/4) and Bravo; Alpha is in "Friday set"
  /// and "Rehearsal". Opens the editor on Alpha, or on a new song.
  Future<void> pumpEditor(WidgetTester tester, {bool edit = true}) async {
    tester.view
      ..physicalSize = const Size(400, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    metronome = MetronomeController(FakeClickOutput());
    addTearDown(metronome.dispose);
    library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    alpha = library.addSong(
      name: 'Alpha',
      bpm: 100,
      pattern: const MetronomePattern.standard(),
    );
    library.addSong(
      name: 'Bravo',
      bpm: 90,
      pattern: const MetronomePattern.standard(),
    );
    library
      ..saveSetlist(name: 'Friday set', songIds: [alpha.id])
      ..saveSetlist(name: 'Rehearsal', songIds: [alpha.id]);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await openSongEditor(
                    context,
                    library,
                    metronome,
                    song: edit ? alpha : null,
                  );
                  closed = true;
                },
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

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(EditorScaffold.actionKey));
    await tester.pumpAndSettle();
  }

  String bpm(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(SongEditor.bpmKey)).data!;

  testWidgets('a new song opens with a unique default name, selected', (
    tester,
  ) async {
    await pumpEditor(tester, edit: false);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'Song 1');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
    expect(find.byKey(SongEditor.deleteKey), findsNothing);
    await save(tester);
    expect(result!.name, 'Song 1');
    expect(result!.bpm, 120);
    expect(result!.pattern, const MetronomePattern.standard());
    expect(library.songs, hasLength(3));
  });

  test('default names: the lowest free number, from current names', () async {
    final dir = Directory.systemTemp.createTempSync('metra_names_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final library = await LibraryController.load(
      LibraryStore(File('${dir.path}/library.json')),
    );
    expect(library.newSongName(), 'Song 1');
    library
      ..addSong(
        name: 'Song 2',
        bpm: 120,
        pattern: const MetronomePattern.standard(),
      )
      ..addSong(
        name: 'x',
        bpm: 120,
        pattern: const MetronomePattern.standard(),
      );
    expect(library.newSongName(), 'Song 1', reason: 'still free');
    final one = library.addSong(
      name: 'song 1 ', // case and spaces don't make it a different name
      bpm: 120,
      pattern: const MetronomePattern.standard(),
    );
    expect(library.newSongName(), 'Song 3');
    library.updateSong(one.copyWith(name: 'Ballad'));
    expect(library.newSongName(), 'Song 1', reason: 'renamed: free again');
    await library.flush();
  });

  testWidgets('tempo and time signature edit the draft; Save stores it', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(bpm(tester), '100');
    await tapText(tester, '+');
    await tapText(tester, '+');
    expect(bpm(tester), '102');
    // The beats + is the second "+".
    await tester.tap(find.text('+').last);
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(SongEditor.beatsKey)).data, '5');
    await tapText(tester, '8');
    expect(library.songById(alpha.id)!.bpm, 100, reason: 'not saved yet');
    await save(tester);
    final saved = library.songById(alpha.id)!;
    expect(saved.bpm, 102);
    expect(saved.pattern.timeSignature, '5/8');
    expect(saved.pattern.beatLevels.first, StepLevel.accent, reason: 'kept');
    expect(result!.bpm, 102);
  });

  testWidgets('saving the loaded song applies it to the click', (tester) async {
    await pumpEditor(tester);
    library.playSong(alpha, metronome);
    await tapText(tester, '+');
    expect(metronome.bpm, 100, reason: 'editing alone changes nothing');
    await save(tester);
    expect(metronome.bpm, 101);
  });

  testWidgets('saving another song leaves the click alone', (tester) async {
    await pumpEditor(tester);
    metronome.setBpm(80);
    await tapText(tester, '+');
    await save(tester);
    expect(metronome.bpm, 80);
  });

  testWidgets('Preview plays the draft live; leaving restores', (tester) async {
    await pumpEditor(tester);
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.byKey(SongEditor.previewKey));
    await tester.pump();
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 100);
    expect(find.text('Stop'), findsOneWidget);
    await tapText(tester, '+');
    expect(metronome.bpm, 101, reason: 'edits are heard at once');
    await tester.tap(find.byKey(EditorScaffold.cancelKey));
    await tester.pumpAndSettle();
    await tapText(tester, 'Discard');
    await tester.pumpAndSettle();
    expect(metronome.isPlaying, isFalse, reason: 'was stopped before');
    expect(metronome.bpm, 120);
  });

  testWidgets('Stop ends the preview; edits stay silent', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(SongEditor.previewKey));
    await tester.pump();
    await tester.tap(find.byKey(SongEditor.previewKey));
    await tester.pump();
    expect(metronome.isPlaying, isFalse);
    expect(find.text('Preview'), findsOneWidget);
    expect(metronome.bpm, 120, reason: 'main screen restored');
    await tapText(tester, '+');
    expect(metronome.bpm, 120, reason: 'not previewing');
  });

  testWidgets('saving the loaded song after a preview keeps it playing', (
    tester,
  ) async {
    await pumpEditor(tester);
    library.playSong(alpha, metronome);
    await metronome.play();
    await tester.tap(find.byKey(SongEditor.previewKey));
    await tester.pump();
    await tapText(tester, '+');
    await save(tester);
    expect(metronome.isPlaying, isTrue);
    expect(metronome.bpm, 101);
    expect(metronome.previewing, isFalse);
    metronome.stop();
  });

  testWidgets('pattern section: collapsed, summary, subdivision and cells', (
    tester,
  ) async {
    await pumpEditor(tester);
    expect(find.text('Quarter notes, accent on 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('pattern-beat-0')), findsNothing);
    await tester.tap(find.byKey(SongEditor.patternKey));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('subdivision-4')));
    await tester.pump();
    expect(find.text('Sixteenths, accent on 1'), findsOneWidget);
    // Three cells per beat after the beat itself.
    expect(find.byKey(const ValueKey('pattern-cell-3-3')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pattern-cell-0-2')));
    await tester.pump();
    expect(find.text('Sixteenths, custom pattern'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pattern-beat-1')));
    await tester.pump();
    await save(tester);
    final steps = library.songById(alpha.id)!.pattern.steps;
    expect(steps[2], StepLevel.silent, reason: 'beat 1, cell 3 off');
    expect(steps[4], StepLevel.accent, reason: 'beat 2 cycled to accent');
    expect(steps[5], StepLevel.soft);
  });

  testWidgets('edits tick; the pattern header does not', (tester) async {
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
    await pumpEditor(tester);
    await tester.tap(find.byKey(SongEditor.patternKey));
    await tester.pump();
    expect(haptics, isEmpty);
    await tapText(tester, '+');
    await tester.tap(find.byKey(const ValueKey('subdivision-2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pattern-cell-0-1')));
    await tester.tap(find.byKey(const ValueKey('pattern-beat-0')));
    await tester.pump(const Duration(seconds: 1));
    expect(haptics, List.filled(4, 'HapticFeedbackType.lightImpact'));
  });

  testWidgets('shows which setlists use the song', (tester) async {
    await pumpEditor(tester);
    expect(
      find.text('In 2 setlists: Friday set, Rehearsal. Changes apply to both.'),
      findsOneWidget,
    );
  });

  testWidgets('Cancel with changes asks to discard', (tester) async {
    await pumpEditor(tester);
    await tapText(tester, '+');
    await tester.tap(find.byKey(EditorScaffold.cancelKey));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tapText(tester, 'Discard');
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
    expect(library.songById(alpha.id)!.bpm, 100);
  });

  testWidgets('Delete names the setlists and removes the song', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(SongEditor.deleteKey));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Delete “Alpha”? It will be removed from Friday set, Rehearsal.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Delete');
    await tester.pumpAndSettle();
    expect(library.songById(alpha.id), isNull);
    expect(library.setlists.every((l) => l.songIds.isEmpty), isTrue);
    expect(result, isNull);
  });
}
