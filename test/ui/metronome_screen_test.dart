import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/ui/metronome_screen.dart';

import '../audio/fake_click_output.dart';

void main() {
  late FakeClickOutput output;
  late MetronomeController controller;

  setUp(() {
    output = FakeClickOutput();
    controller = MetronomeController(output);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MetronomeScreen(controller: controller)),
    );
    // Stop the scheduler timer before the test ends.
    addTearDown(controller.dispose);
  }

  Text bpmText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(MetronomeScreen.bpmKey));

  testWidgets('shows the current bpm', (tester) async {
    await pumpScreen(tester);
    expect(bpmText(tester).data, '120');
    expect(find.text('BPM'), findsOneWidget);
  });

  testWidgets('step buttons change the tempo', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(bpmText(tester).data, '130');
    await tester.tap(find.text('-1'));
    await tester.pump();
    expect(bpmText(tester).data, '129');
    await tester.tap(find.text('+1'));
    await tester.tap(find.text('-10'));
    await tester.pump();
    expect(controller.bpm, 120);
  });

  testWidgets('step buttons disable at the tempo limits', (tester) async {
    controller.setBpm(MetronomeController.maxBpm);
    await pumpScreen(tester);
    bool enabled(String label) => tester
        .widget<OutlinedButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(OutlinedButton),
          ),
        )
        .enabled;
    expect(enabled('+1'), isFalse);
    expect(enabled('+10'), isFalse);
    expect(enabled('-1'), isTrue);

    controller.setBpm(MetronomeController.minBpm);
    await tester.pump();
    expect(enabled('-1'), isFalse);
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
    expect(find.text('Play'), findsOneWidget);
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
}
