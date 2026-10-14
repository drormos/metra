import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/click_sound.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/ui/metronome_screen.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

void main() {
  late FakeClickOutput output;
  late MetronomeController controller;

  setUp(() {
    output = FakeClickOutput();
    controller = MetronomeController(output);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(controller: controller),
      ),
    );
    // Stop the scheduler timer before the test ends.
    addTearDown(controller.dispose);
  }

  Text bpmText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(MetronomeScreen.bpmKey));

  testWidgets('shows the current bpm', (tester) async {
    await pumpScreen(tester);
    expect(bpmText(tester).data, '120');
    expect(find.text('bpm'), findsOneWidget);
  });

  testWidgets('step buttons change the tempo', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(bpmText(tester).data, '130');
    await tester.tap(find.text('−1'));
    await tester.pump();
    expect(bpmText(tester).data, '129');
    await tester.tap(find.text('+1'));
    await tester.tap(find.text('−10'));
    await tester.pump();
    expect(controller.bpm, 120);
  });

  testWidgets('step buttons disable at the tempo limits', (tester) async {
    controller.setBpm(MetronomeController.maxBpm);
    await pumpScreen(tester);
    bool enabled(String label) => tester
        .widget<FilledButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
        )
        .enabled;
    expect(enabled('+1'), isFalse);
    expect(enabled('+10'), isFalse);
    expect(enabled('−1'), isTrue);

    controller.setBpm(MetronomeController.minBpm);
    await tester.pump();
    expect(enabled('−1'), isFalse);
    expect(enabled('+1'), isTrue);
  });

  testWidgets('play button toggles playback', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    expect(controller.isPlaying, isTrue);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    expect(controller.isPlaying, isFalse);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('keyboard: space toggles, arrows nudge', (tester) async {
    await pumpScreen(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(controller.bpm, 121);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    expect(controller.bpm, 120);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.bpm, 130);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.isPlaying, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.isPlaying, isFalse);
  });

  testWidgets('shows an audio error', (tester) async {
    output.deviceError = 'device unplugged';
    await pumpScreen(tester);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    expect(find.textContaining('device unplugged'), findsOneWidget);
  });

  testWidgets('beat indicator lights the step the engine has reached', (
    tester,
  ) async {
    controller.setVisualOffset(const Duration(milliseconds: 50));
    await pumpScreen(tester);
    expect(find.byKey(const ValueKey('beat-0-off')), findsOneWidget);

    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    // First step at 120 ms engine time; flash due at 170 ms.
    output.time = const Duration(milliseconds: 150);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('beat-0-off')), findsOneWidget);

    output.time = const Duration(milliseconds: 180);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('beat-0-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('beat-1-off')), findsOneWidget);

    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    expect(find.byKey(const ValueKey('beat-0-off')), findsOneWidget);
  });

  testWidgets('flash offset buttons adjust the offset', (tester) async {
    await pumpScreen(tester);
    expect(find.byTooltip('Flash later'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final start = controller.visualOffset;
    await tester.tap(find.byTooltip('Flash later'));
    await tester.pump();
    expect(controller.visualOffset, start + const Duration(milliseconds: 10));
    await tester.tap(find.byTooltip('Flash earlier'));
    await tester.tap(find.byTooltip('Flash earlier'));
    await tester.tap(find.byTooltip('Flash earlier'));
    await tester.pump();
    final expected = start - const Duration(milliseconds: 20);
    expect(controller.visualOffset, expected);
    expect(
      tester.widget<Text>(find.byKey(MetronomeScreen.offsetKey)).data,
      '${expected.inMilliseconds} ms',
    );
  });

  testWidgets('tap button and T key set the tempo', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(MetronomeScreen.tapKey));
    expect(controller.bpm, 120); // one tap: no tempo yet
    // Two taps microseconds apart: far above the range, so clamped.
    await tester.tap(find.byKey(MetronomeScreen.tapKey));
    expect(controller.bpm, MetronomeController.maxBpm);

    controller.setBpm(120);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    expect(controller.bpm, MetronomeController.maxBpm);
  });

  group('rhythm', () {
    Future<void> pick(WidgetTester tester, Key dropdown, String item) async {
      await tester.tap(find.byKey(dropdown));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    testWidgets('time signature picker sets the meter', (tester) async {
      await pumpScreen(tester);
      await pick(tester, MetronomeScreen.meterKey, '7/8');
      expect(controller.pattern.timeSignature, '7/8');
      expect(find.byKey(const ValueKey('beat-6-off')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat-7-off')), findsNothing);
    });

    testWidgets('subdivision button cycles 1-4, one dot per beat', (
      tester,
    ) async {
      await pumpScreen(tester);
      for (final expected in [2, 3]) {
        await tester.tap(find.byKey(MetronomeScreen.subdivisionKey));
        await tester.pump();
        expect(controller.pattern.stepsPerBeat, expected);
      }
      expect(controller.pattern.timeSignature, '4/4');
      expect(find.byKey(const ValueKey('beat-3-off')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat-4-off')), findsNothing);
    });

    testWidgets('tapping a beat dot cycles its accent', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('beat-2-off')));
      await tester.pump();
      expect(controller.pattern.beatLevels[2], StepLevel.accent);
      await tester.tap(find.byKey(const ValueKey('beat-2-off')));
      await tester.pump();
      expect(controller.pattern.beatLevels[2], StepLevel.silent);
    });

    testWidgets('with subdivisions the beat dot stays lit', (tester) async {
      controller.setPattern(
        MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2),
      );
      controller.setVisualOffset(Duration.zero);
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      // 120 BPM, 2 per beat: steps at 120, 370, 620 ms. 400 ms is the
      // second half of beat 1.
      output.time = const Duration(milliseconds: 400);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('beat-0-on')), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });
  });

  testWidgets('settings: pick a click sound', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cowbell'));
    await tester.pump();
    expect(controller.clickSound, ClickSound.cowbell);
    expect(output.previewCount, 1);
    final chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Cowbell'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('subdivision wraps from 4 back to 1', (tester) async {
    await pumpScreen(tester);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(MetronomeScreen.subdivisionKey));
      await tester.pump();
    }
    expect(controller.pattern.stepsPerBeat, 1);
    expect(find.byTooltip('Subdivision: quarter notes'), findsOneWidget);
  });

  testWidgets('tempo name follows the bpm', (tester) async {
    await pumpScreen(tester);
    String name() =>
        tester.widget<Text>(find.byKey(MetronomeScreen.tempoNameKey)).data!;
    expect(name(), 'Allegro');
    controller.setBpm(60);
    await tester.pump();
    expect(name(), 'Largo');
  });
}
