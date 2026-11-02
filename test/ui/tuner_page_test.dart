import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/mic_input.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/controller/tuner_controller.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/theme.dart';
import 'package:metra/src/ui/tuner_page.dart';
import 'package:metra/src/ui/value_stepper.dart';

import '../audio/fake_click_output.dart';
import '../audio/fake_mic_input.dart';
import '../audio/pitch_detector_test.dart' show tone;
import 'test_theme.dart';

void main() {
  late MetronomeController metronome;
  late FakeMicInput mic;

  setUp(() {
    metronome = MetronomeController(FakeClickOutput());
    mic = FakeMicInput(state: MicPermission.granted);
  });
  tearDown(() => metronome.dispose());

  Future<void> pumpPage(
    WidgetTester tester, {
    LibraryController? library,
    double textScale = 1,
    Size size = const Size(412, 915),
    MetraColors colors = MetraColors.stageBlack,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp(
          theme: metraTheme(
            colors,
            colors == MetraColors.daylight ? Brightness.light : Brightness.dark,
          ),
          home: TunerPage(library: library, mic: mic),
        ),
      ),
    );
    await tester.pump();
  }

  var played = 0;
  Future<void> play(WidgetTester tester, double? hz, double seconds) async {
    final length = (48000 * seconds).round();
    final samples = hz == null
        ? Float32List(length)
        : tone(hz, 48000, length, start: played);
    played += length;
    for (var i = 0; i < samples.length; i += 1024) {
      final end = (i + 1024).clamp(0, samples.length);
      mic.push(Float32List.sublistView(samples, i, end));
      await tester.pump(Duration(microseconds: (end - i) * 1000000 ~/ 48000));
    }
  }

  testWidgets('the tuning fork opens the Tuner; the click stops and stays '
      'stopped after Back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: metronome),
      ),
    );
    await metronome.play();
    await tester.pump();
    expect(find.bySemanticsLabel('Tuner'), findsOneWidget);
    await tester.tap(find.byKey(MetronomeScreen.tunerKey));
    await tester.pumpAndSettle();
    expect(find.byType(TunerPage), findsOneWidget);
    expect(metronome.isPlaying, isFalse);
    expect(find.text(TunerPage.pauseLine), findsOneWidget);
    expect(TunerController.isOpen.value, isTrue, reason: 'screen stays on');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(TunerPage), findsNothing);
    expect(metronome.isPlaying, isFalse, reason: 'no restart by itself');
    expect(TunerController.isOpen.value, isFalse);
  });

  testWidgets('a note: big name, muted octave, cents line; "In tune" '
      'within 3 cents; "–" and "Play a string" a second after it stops', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Play a string'), findsOneWidget);
    await play(tester, 110 * 1.00695555, 0.4); // A2 +12 cents
    expect(find.textContaining('A'), findsWidgets);
    final note = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(TunerPage.noteKey),
        matching: find.byType(RichText),
      ),
    );
    expect(note.text.toPlainText(), 'A2');
    expect(find.text('+12 cents · 110.8 Hz'), findsOneWidget);
    await play(tester, 110, 0.4);
    expect(find.text('In tune'), findsOneWidget);
    await play(tester, null, 1.2);
    expect(find.text('Play a string'), findsOneWidget);
    expect(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.byKey(TunerPage.noteKey),
              matching: find.byType(RichText),
            ),
          )
          .text
          .toPlainText(),
      '–',
    );
    await tester.pumpWidget(const SizedBox());
    expect(mic.running, isFalse, reason: 'leaving stops the microphone');
  });

  testWidgets('first open shows the privacy line, then asks; refused: '
      '"Allow microphone" asks again', (tester) async {
    mic
      ..state = MicPermission.unknown
      ..answer = MicPermission.denied;
    await pumpPage(tester);
    expect(mic.requests, 1);
    expect(find.text(TunerPage.privacyLine), findsOneWidget);
    expect(find.byKey(TunerPage.allowKey), findsOneWidget);
    expect(mic.running, isFalse);
    mic.answer = MicPermission.granted;
    await tester.tap(find.byKey(TunerPage.allowKey));
    await tester.pump();
    expect(mic.requests, 2);
    expect(mic.running, isTrue);
    expect(find.text('Play a string'), findsOneWidget);
    expect(find.text(TunerPage.privacyLine), findsNothing);
  });

  testWidgets('blocked: "Allow microphone" opens the app settings', (
    tester,
  ) async {
    mic.state = MicPermission.blocked;
    await pumpPage(tester);
    expect(mic.requests, 0);
    await tester.tap(find.byKey(TunerPage.allowKey));
    await tester.pump();
    expect(mic.settingsOpened, 1);
  });

  testWidgets('Reference A4 steps 430–450 and is saved app-wide', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('metra_tuner');
    final library = (await tester.runAsync(
      () => LibraryController.load(
        LibraryStore(File('${dir.path}/library.json')),
      ),
    ))!;
    await pumpPage(tester, library: library);
    expect(find.text('440 Hz'), findsOneWidget);
    await tester.tap(
      find.byKey(ValueStepper.plusKey(TunerPage.referenceLabel)),
    );
    await tester.pump();
    expect(library.referenceA4, 441);
    library.setReferenceA4(450);
    await tester.pump();
    await tester.tap(
      find.byKey(ValueStepper.plusKey(TunerPage.referenceLabel)),
    );
    await tester.pump();
    expect(library.referenceA4, 450, reason: 'the top of the range');
    expect(find.text('450 Hz'), findsOneWidget);
    library.setReferenceA4(500);
    expect(library.referenceA4, 450);
  });

  for (final (colors, name) in [
    (MetraColors.stageBlack, 'dark'),
    (MetraColors.daylight, 'daylight'),
  ]) {
    testWidgets('$name, text at 115% and 200% on 360dp: nothing overflows', (
      tester,
    ) async {
      for (final scale in [1.15, 2.0]) {
        await pumpPage(
          tester,
          textScale: scale,
          size: const Size(360, 740),
          colors: colors,
        );
        await play(tester, 116.54, 0.3); // A♯2: the widest note
        expect(tester.takeException(), isNull);
      }
    });
  }

  for (final (colors, name) in [
    (MetraColors.stageBlack, 'dark'),
    (MetraColors.daylight, 'daylight'),
  ]) {
    testWidgets('$name: tap targets, labels and contrast, listening and '
        'refused', (tester) async {
      final handle = tester.ensureSemantics();
      for (final state in [MicPermission.granted, MicPermission.denied]) {
        mic.state = state;
        await pumpPage(tester, colors: colors);
        if (state == MicPermission.granted) await play(tester, 110, 0.3);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      handle.dispose();
    });
  }
}
