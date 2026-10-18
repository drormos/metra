import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/tabular_text.dart';
import 'package:metra/src/ui/theme.dart';
import 'package:metra/src/ui/repeat_button.dart';
import 'package:metra/src/ui/haptics.dart';
import 'package:metra/src/ui/tempo_ruler.dart';
import 'package:metra/src/ui/time_signature_sheet.dart';

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

  TabularText bpmText(WidgetTester tester) =>
      tester.widget<TabularText>(find.byKey(MetronomeScreen.bpmKey));

  testWidgets('shows the current bpm', (tester) async {
    await pumpScreen(tester);
    expect(bpmText(tester).text, '120');
    expect(find.text('bpm'), findsWidgets); // plus its invisible twin
  });

  testWidgets('step buttons change the tempo', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.text('+5'));
    await tester.pump();
    expect(bpmText(tester).text, '125');
    await tester.tap(find.text('−1'));
    await tester.pump();
    expect(bpmText(tester).text, '124');
    await tester.tap(find.text('+1'));
    await tester.tap(find.text('−5'));
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
    expect(enabled('+5'), isFalse);
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
    expect(controller.bpm, 125);

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

    testWidgets('a common meter applies and closes the sheet', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(find.text('Time signature'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('common-12-8')));
      await tester.pumpAndSettle();
      expect(controller.pattern.timeSignature, '12/8');
      expect(find.byType(TimeSignatureSheet), findsNothing);
    });

    testWidgets('custom applies as it changes and stays open', (tester) async {
      await pumpScreen(tester);
      controller.cycleBeat(1); // beat 2 accented
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      final sheet = find.byType(TimeSignatureSheet);
      await tester.tap(find.descendant(of: sheet, matching: find.text('+')));
      await tester.pump();
      expect(controller.pattern.timeSignature, '5/4');
      await tester.tap(find.byKey(const ValueKey('segment-8')));
      await tester.pump();
      expect(controller.pattern.timeSignature, '5/8');
      expect(sheet, findsOneWidget);
      expect(controller.pattern.beatLevels, [
        StepLevel.accent,
        StepLevel.accent,
        StepLevel.normal,
        StepLevel.normal,
        StepLevel.normal,
      ], reason: 'beat states kept, the new beat regular');
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
    expect(name(), 'Larghetto');
    controller.setBpm(200);
    await tester.pump();
    expect(name(), 'Prestissimo', reason: 'the longest name fits');
    expect(tester.takeException(), isNull);
  });

  group('beat blocks', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    /// Advances the engine clock like a real one, in small steps, so the
    /// scheduler's refill timer keeps up instead of skipping late clicks.
    Future<void> playAt(WidgetTester tester, int ms) async {
      final target = Duration(milliseconds: ms);
      while (output.time < target) {
        final next = output.time + const Duration(milliseconds: 20);
        output.time = next < target ? next : target;
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Future<void> startTwoPerBeat(WidgetTester tester) async {
      controller
        ..setPattern(MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2))
        ..setVisualOffset(Duration.zero);
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      // 120 BPM, 2 per beat: steps at 120, 370, 620, 870 ms ...
    }

    Future<void> stop(WidgetTester tester) async {
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    }

    testWidgets('no strip without subdivision', (tester) async {
      await pumpScreen(tester);
      expect(key('tick-0-0-off'), findsNothing);
      controller.setSubdivision(3);
      await tester.pump();
      expect(key('tick-3-2-off'), findsOneWidget);
    });

    testWidgets('a tick lights only for its own click; the block for the '
        'whole beat', (tester) async {
      await startTwoPerBeat(tester);
      await playAt(tester, 150);
      expect(key('beat-0-on'), findsOneWidget);
      expect(key('tick-0-0-on'), findsOneWidget);
      expect(key('tick-0-1-off'), findsOneWidget);

      await playAt(tester, 400);
      expect(key('beat-0-on'), findsOneWidget, reason: 'still beat 1');
      expect(key('tick-0-0-off'), findsOneWidget);
      expect(key('tick-0-1-on'), findsOneWidget);

      await playAt(tester, 650);
      expect(key('beat-0-off'), findsOneWidget, reason: 'nothing stays lit');
      expect(key('beat-1-on'), findsOneWidget);
      await stop(tester);
      expect(key('beat-1-off'), findsOneWidget);
    });

    testWidgets('a muted beat never lights; its subdivisions still do', (
      tester,
    ) async {
      controller.cycleBeat(0); // accent -> muted
      expect(controller.pattern.beatLevels[0], StepLevel.silent);
      await startTwoPerBeat(tester);
      controller.cycleBeat(0); // accent -> muted (setPattern reset it)
      await tester.pump();
      expect(controller.pattern.beatLevels[0], StepLevel.silent);

      await playAt(tester, 150); // muted beat's own (silent) click
      expect(key('beat-0-off'), findsOneWidget);
      expect(key('tick-0-0-off'), findsOneWidget);

      await playAt(tester, 400); // its eighth sounds
      expect(key('beat-0-off'), findsOneWidget);
      expect(key('tick-0-1-on'), findsOneWidget);
      await stop(tester);
    });
  });

  testWidgets('every beat block, muted included, fills its width', (
    tester,
  ) async {
    await pumpScreen(tester);
    controller
      ..cycleBeat(3) // regular -> accent
      ..cycleBeat(3); // accent -> muted
    await tester.pump();
    expect(controller.pattern.beatLevels[3], StepLevel.silent);
    final widths = [
      for (var i = 0; i < 4; i++)
        tester.getSize(find.byKey(ValueKey('beat-$i-off'))).width,
    ];
    expect(widths[3], greaterThan(40));
    expect(widths.toSet(), hasLength(1), reason: 'equal widths');
  });

  testWidgets('a tapped block changes on screen at once while playing', (
    tester,
  ) async {
    controller.setVisualOffset(Duration.zero);
    await pumpScreen(tester);
    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
    output.time = const Duration(milliseconds: 150); // beat 1 sounding
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.bySemanticsLabel(RegExp('^Beat 3, regular')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('beat-2-off')));
    await tester.pump(); // one frame, no clock movement
    expect(find.bySemanticsLabel(RegExp('^Beat 3, accented')), findsOneWidget);

    await tester.tap(find.byKey(MetronomeScreen.playKey));
    await tester.pump();
  });

  group('tempo ruler', () {
    Finder ruler() => find.byType(TempoRuler);

    testWidgets('dragging left raises the tempo, 14 px per bpm', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.drag(ruler(), const Offset(-140, 0), touchSlopX: 0);
      await tester.pump();
      expect(controller.bpm, 130);
      await tester.drag(ruler(), const Offset(70, 0), touchSlopX: 0);
      await tester.pump();
      expect(controller.bpm, 125);
    });

    testWidgets('clamps to 30-300', (tester) async {
      await pumpScreen(tester);
      await tester.drag(ruler(), const Offset(-5000, 0), touchSlopX: 0);
      await tester.pump();
      expect(controller.bpm, MetronomeController.maxBpm);
      await tester.drag(ruler(), const Offset(5000, 0), touchSlopX: 0);
      await tester.pump();
      expect(controller.bpm, MetronomeController.minBpm);
    });

    testWidgets('a tap does nothing', (tester) async {
      await pumpScreen(tester);
      await tester.tapAt(tester.getCenter(ruler()) + const Offset(100, 0));
      await tester.pump();
      expect(controller.bpm, 120);
    });

    testWidgets('a slow drag is precise: 1 bpm per 14 px, no glide', (
      tester,
    ) async {
      await pumpScreen(tester);
      // 70 px over a second: well under the acceleration threshold.
      await tester.timedDrag(
        ruler(),
        const Offset(-70, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(controller.bpm, 125);
    });

    testWidgets('a fast swipe goes further and glides on', (tester) async {
      await pumpScreen(tester);
      await tester.fling(ruler(), const Offset(-140, 0), 2000);
      final atRelease = controller.bpm;
      expect(atRelease, greaterThan(130), reason: 'accelerated');
      await tester.pumpAndSettle();
      expect(controller.bpm, greaterThan(atRelease), reason: 'glided');
      expect(controller.bpm, lessThanOrEqualTo(MetronomeController.maxBpm));
    });

    testWidgets('touching the ruler stops a glide', (tester) async {
      await pumpScreen(tester);
      await tester.fling(ruler(), const Offset(-100, 0), 1500);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(ruler());
      final stoppedAt = controller.bpm;
      await tester.pumpAndSettle();
      expect(controller.bpm, stoppedAt);
    });

    test('a fling always rests on a multiple of 5, ahead of where it was', () {
      expect(TempoRuler.flingTarget(123, 5), 125);
      expect(TempoRuler.flingTarget(123, -5), 120);
      expect(TempoRuler.flingTarget(125, 1), 130, reason: 'at least one ahead');
      expect(TempoRuler.flingTarget(125, -1), 120);
      final far = TempoRuler.flingTarget(123, 200);
      expect(far % 5, 0);
      expect(far, greaterThan(150));
      expect(TempoRuler.flingTarget(297, 500), 300, reason: 'clamped');
      expect(TempoRuler.flingTarget(32, -500), 30);
    });

    test('one swipe covers at most half the range', () {
      expect(TempoRuler.flingTarget(150, 5000, start: 100), 235);
      expect(TempoRuler.flingTarget(150, -5000, start: 200), 65);
      expect(TempoRuler.flingTarget(30, 5000), 165);
    });

    testWidgets('a hard flick from 30 stops halfway', (tester) async {
      controller.setBpm(30);
      await pumpScreen(tester);
      await tester.fling(ruler(), const Offset(-300, 0), 8000);
      await tester.pumpAndSettle();
      expect(controller.bpm, lessThanOrEqualTo(165));
      expect(controller.bpm % 5, 0);
    });

    testWidgets('a slow drag then a rest stays exactly where released', (
      tester,
    ) async {
      controller.setBpm(121);
      await pumpScreen(tester);
      final gesture = await tester.startGesture(tester.getCenter(ruler()));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(-7, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(TempoRuler.lockDelay);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.bpm, 126, reason: 'not snapped to 130');
    });

    testWidgets('a normal drag snaps ahead to a multiple of 5', (tester) async {
      await pumpScreen(tester);
      // 98 px in 0.4 s: faster than fine-tuning, not a fling.
      await tester.timedDrag(
        ruler(),
        const Offset(-98, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(controller.bpm, 130, reason: '127 moving up');
      await tester.timedDrag(
        ruler(),
        const Offset(98, 0),
        const Duration(milliseconds: 400),
      );
      await tester.pumpAndSettle();
      expect(controller.bpm, 120, reason: '123 moving down');
    });

    /// Drags up to about 127 at a normal pace, then rests [restMs] with the
    /// jitter of a real finger, then lifts.
    Future<void> dragThenRest(WidgetTester tester, int restMs) async {
      final gesture = await tester.startGesture(tester.getCenter(ruler()));
      var t = Duration.zero;
      Future<void> move(double dx, int ms) async {
        t += Duration(milliseconds: ms);
        await gesture.moveBy(Offset(dx, 0), timeStamp: t);
        await tester.pump(Duration(milliseconds: ms));
      }

      for (var i = 0; i < 10; i++) {
        await move(-10, 30); // ~330 px/s
      }
      for (var i = 0; i < restMs ~/ 16; i++) {
        await move(i.isEven ? 1 : -1, 16);
      }
      await gesture.up(timeStamp: t);
      await tester.pumpAndSettle();
    }

    testWidgets('resting on a value before lifting keeps it exactly', (
      tester,
    ) async {
      await pumpScreen(tester);
      await dragThenRest(tester, 400);
      expect(controller.bpm, isNot(anyOf(125, 130)));
      expect(controller.bpm, inInclusiveRange(126, 129));
    });

    /// Drags [steps] × 14 px (1 bpm each) leftwards, one step per [ms],
    /// and lifts at once.
    Future<void> dragSteps(WidgetTester tester, int steps, int ms) async {
      final gesture = await tester.startGesture(tester.getCenter(ruler()));
      var t = Duration.zero;
      for (var i = 0; i < steps; i++) {
        t += Duration(milliseconds: ms);
        await gesture.moveBy(const Offset(-14, 0), timeStamp: t);
        await tester.pump(Duration(milliseconds: ms));
      }
      await gesture.up(timeStamp: t);
      await tester.pumpAndSettle();
    }

    testWidgets('a short drag keeps its exact value, no pause needed', (
      tester,
    ) async {
      await pumpScreen(tester);
      await dragSteps(tester, 3, 60); // 233 px/s: not slow, but short
      expect(controller.bpm, 123);
    });

    testWidgets('a slow long drag keeps its exact value, no pause needed', (
      tester,
    ) async {
      await pumpScreen(tester);
      await dragSteps(tester, 13, 100); // 140 px/s
      expect(controller.bpm, 133);
    });

    testWidgets('a brief pause before lifting still snaps ahead', (
      tester,
    ) async {
      await pumpScreen(tester);
      await dragThenRest(tester, 160);
      expect(controller.bpm, 130);
    });

    test('a drag snaps to the next multiple of 5 in its direction', () {
      expect(TempoRuler.snapTarget(121, 1), 125);
      expect(TempoRuler.snapTarget(124, -1), 120);
      expect(TempoRuler.snapTarget(120.3, 1), 120, reason: 'already on it');
      expect(TempoRuler.snapTarget(124.6, -1), 125, reason: 'already on it');
      expect(TempoRuler.snapTarget(298, 1), 300);
    });

    testWidgets('a fling from 123 settles on a multiple of 5 above it', (
      tester,
    ) async {
      controller.setBpm(123);
      await pumpScreen(tester);
      await tester.fling(ruler(), const Offset(-60, 0), 800);
      await tester.pumpAndSettle();
      expect(controller.bpm % 5, 0);
      expect(controller.bpm, greaterThan(123));
    });

    testWidgets(
      'a haptic tick on every multiple of 5 crossed, a firmer one on lock',
      (tester) async {
        final clicks = <Object?>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              clicks.add(call.arguments);
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
        await pumpScreen(tester);
        // 120 -> 132 slowly: crosses 125 and 130, then rests to lock 132.
        final gesture = await tester.startGesture(tester.getCenter(ruler()));
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(const Offset(-14, 0));
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(TempoRuler.lockDelay);
        await gesture.up();
        await tester.pumpAndSettle();
        expect(controller.bpm, 132);
        expect(clicks, [
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.heavyImpact', // locked
        ]);
      },
    );

    test('gain grows with finger speed, capped', () {
      expect(TempoRuler.gainFor(100), 1);
      expect(TempoRuler.gainFor(900), closeTo(1.75, 0.01));
      expect(TempoRuler.gainFor(5000), TempoRuler.maxGain);
    });

    testWidgets('screen readers can adjust it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester);
      final node = tester.getSemantics(ruler());
      expect(node.value, '120 bpm');
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(controller.bpm, 121);
      semantics.dispose();
    });
  });

  testWidgets('no jitter: holding +1 from 100 to 199 never changes the width', (
    tester,
  ) async {
    // The real font: the test font's digits are all the same width anyway.
    await tester.runAsync(() async {
      final loader = FontLoader(MetraFonts.condensed)
        ..addFont(rootBundle.load('assets/fonts/SairaExtraCondensed-Bold.ttf'));
      await loader.load();
    });
    controller.setBpm(100);
    await pumpScreen(tester);
    final number = find.byKey(MetronomeScreen.bpmKey);
    final rect = tester.getRect(number);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('+1')),
    );
    final seen = <int>{};
    for (var i = 0; i < 400 && controller.bpm < 199; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(controller.bpm);
      expect(tester.getRect(number), rect, reason: '${controller.bpm}');
    }
    await gesture.up();
    expect(controller.bpm, greaterThanOrEqualTo(199));
    expect(seen, containsAll([111, 188]));
  });

  Future<void> loadNumberFonts(WidgetTester tester) =>
      tester.runAsync(() async {
        TabularText.clearCache(); // measured with the test font so far
        for (final (family, file) in [
          (MetraFonts.condensed, 'SairaExtraCondensed-Bold'),
          (MetraFonts.body, 'Saira-Medium'),
        ]) {
          await (FontLoader(
            family,
          )..addFont(rootBundle.load('assets/fonts/$file.ttf'))).load();
        }
      });

  double numberSize(WidgetTester tester) => tester
      .widget<TabularText>(find.byKey(MetronomeScreen.bpmKey))
      .style!
      .fontSize!;

  testWidgets('the BPM size comes from the area: bigger on taller screens', (
    tester,
  ) async {
    await loadNumberFonts(tester);
    addTearDown(tester.view.reset);
    tester.view
      ..physicalSize = const Size(400, 560)
      ..devicePixelRatio = 1;
    await pumpScreen(tester);
    final short = numberSize(tester); // height-bound
    tester.view.physicalSize = const Size(400, 1100);
    await tester.pump();
    final tall = numberSize(tester); // width-bound: three digits fit
    expect(tall, greaterThan(short));
    expect(tall, lessThanOrEqualTo(240));
  });

  testWidgets('99 and 100: same size, the number stays centred', (
    tester,
  ) async {
    await loadNumberFonts(tester);
    controller.setBpm(100);
    await pumpScreen(tester);
    final number = find.byKey(MetronomeScreen.bpmKey);
    final size = numberSize(tester);
    final centre = tester.getRect(number).center;
    final ruler = tester.getRect(find.byType(TempoRuler));
    final line = tester.getRect(find.byKey(MetronomeScreen.tempoNameKey));
    expect(line.bottom, lessThanOrEqualTo(ruler.top), reason: 'no overlap');
    controller.setBpm(99);
    await tester.pump();
    expect(numberSize(tester), size);
    expect(tester.getRect(number).center, centre);
  });

  testWidgets('the BPM number alone is centred; "bpm" hangs off its right', (
    tester,
  ) async {
    await pumpScreen(tester);
    final screen = tester.getRect(find.byType(MetronomeScreen));
    final number = tester.getRect(find.byKey(MetronomeScreen.bpmKey));
    expect(number.center.dx, closeTo(screen.center.dx, 0.5));
    final label = tester.getRect(find.text('bpm').last);
    expect(label.left, greaterThan(number.right));
  });

  group('haptics', () {
    /// Records haptic types ('lightImpact', 'mediumImpact', ...).
    List<String> recordHaptics(WidgetTester tester) {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add((call.arguments as String).split('.').last);
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
      return haptics;
    }

    testWidgets('Start/Stop is medium', (tester) async {
      await pumpScreen(tester);
      final haptics = recordHaptics(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      expect(haptics, ['mediumImpact']);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });

    testWidgets('small adjustments tick lightly', (tester) async {
      await pumpScreen(tester);
      final haptics = recordHaptics(tester);
      await tester.tap(find.text('+1'));
      await tester.tap(find.byKey(MetronomeScreen.tapKey));
      await tester.tap(find.byKey(MetronomeScreen.subdivisionKey));
      await tester.tap(find.byKey(const ValueKey('beat-1-off')));
      await tester.pump(const Duration(seconds: 1));
      expect(haptics, List.filled(4, 'lightImpact'));
    });

    testWidgets('holding ±1 ticks on every step', (tester) async {
      await pumpScreen(tester);
      final haptics = recordHaptics(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('+1')),
      );
      await tester.pump(RepeatButton.holdDelay); // first press: 121
      await tester.pump(const Duration(seconds: 1)); // repeats to 130
      await gesture.up();
      await tester.pump();
      expect(controller.bpm, 130);
      expect(haptics, List.filled(10, 'lightImpact')); // 121 … 130
    });

    testWidgets('a hold hitting 300 stops with a medium bump', (tester) async {
      controller.setBpm(MetronomeController.maxBpm - 12);
      await pumpScreen(tester);
      final haptics = recordHaptics(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('+5')),
      );
      await tester.pump(RepeatButton.holdDelay);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      await tester.pump();
      expect(controller.bpm, MetronomeController.maxBpm);
      expect(haptics.last, 'mediumImpact');
      expect(haptics.where((h) => h == 'mediumImpact'), hasLength(1));
    });

    testWidgets('"Vibrate on touch" off silences every haptic', (tester) async {
      await pumpScreen(tester);
      final haptics = recordHaptics(tester);
      Haptics.enabled = false;
      addTearDown(() => Haptics.enabled = true);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.tap(find.text('+1'));
      await tester.pump();
      Haptics.firm();
      expect(haptics, isEmpty);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });

    test('reaching a multiple of 5, either direction', () {
      expect(Haptics.reachesFive(124, 125), isTrue);
      expect(Haptics.reachesFive(125, 126), isFalse);
      expect(Haptics.reachesFive(126, 125), isTrue);
      expect(Haptics.reachesFive(125, 124), isFalse);
      expect(Haptics.reachesFive(123, 128), isTrue);
      expect(Haptics.reachesFive(121, 124), isFalse);
    });
  });

  group('hold to repeat', () {
    testWidgets('holding +1 keeps adding until released', (tester) async {
      await pumpScreen(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('+1')),
      );
      await tester.pump(RepeatButton.holdDelay); // first step: 121
      await tester.pump(const Duration(seconds: 1)); // accelerating
      await gesture.up();
      await tester.pump();
      final held = controller.bpm;
      expect(held, inInclusiveRange(129, 131));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.bpm, held, reason: 'stops on release');
    });

    testWidgets('waits ~0.4 s, then 6 per second rising to 15', (tester) async {
      controller.setBpm(MetronomeController.minBpm);
      await pumpScreen(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('+1')),
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.bpm, 30, reason: 'a normal tap never repeats');
      await tester.pump(const Duration(milliseconds: 50));
      expect(controller.bpm, 31);
      await tester.pump(const Duration(milliseconds: 340));
      expect(controller.bpm, 33, reason: '~6 per second at first');
      await tester.pump(const Duration(milliseconds: 760)); // held 1.5 s
      final atFullSpeed = controller.bpm;
      await tester.pump(const Duration(seconds: 1));
      expect(controller.bpm - atFullSpeed, inInclusiveRange(14, 16));
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a quick tap adds once', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('+5'));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.bpm, 125);
    });

    testWidgets('repeat stops at the limit', (tester) async {
      controller.setBpm(MetronomeController.maxBpm - 12);
      await pumpScreen(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('+5')),
      );
      await tester.pump(RepeatButton.holdDelay);
      await tester.pump(const Duration(seconds: 2));
      expect(controller.bpm, MetronomeController.maxBpm);
      await gesture.up();
      await tester.pump();
    });
  });

  testWidgets('says why the library is unavailable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MetronomeScreen(
          controller: controller,
          libraryProblem: 'Update the app',
        ),
      ),
    );
    addTearDown(controller.dispose);
    expect(find.text('Update the app'), findsOneWidget);
  });
}
