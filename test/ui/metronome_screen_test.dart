import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/model/on_start.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/on_start_sheet.dart';
import 'package:metra/src/ui/value_stepper.dart';
import 'package:metra/src/ui/poly_lane.dart';
import 'package:metra/src/ui/tabular_text.dart';
import 'package:metra/src/ui/theme.dart';
import 'package:metra/src/ui/repeat_button.dart';
import 'package:metra/src/ui/haptics.dart';
import 'package:metra/src/ui/tempo_ruler.dart';
import 'package:metra/src/ui/time_signature_sheet.dart';
import 'package:metra/src/ui/top_panel.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

const _frame = Duration(milliseconds: 16);

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

    testWidgets('Polyrhythm row: Off · 2–7, beat count dimmed, live', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(find.text('Add a second pulse across each bar'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('poly-4')));
      await tester.tap(find.byKey(const ValueKey('poly-4')));
      await tester.pump();
      expect(controller.pattern.polyrhythm, 0, reason: '4 against 4');
      await tester.tap(find.byKey(const ValueKey('poly-3')));
      await tester.pumpAndSettle();
      expect(controller.pattern.polyrhythm, 3);
      expect(
        find.text('3 against 4: three even clicks per bar, in their own sound'),
        findsOneWidget,
      );
      expect(
        find.byKey(TopPanel.surfaceKey),
        findsOneWidget,
        reason: 'stays open',
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text(' · 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Rhythm 4/4, polyrhythm 3'), findsOneWidget);
    });

    testWidgets('lane: cells by time, cell 1 under beat 1; taps cycle; '
        'the BPM never moves', (tester) async {
      await pumpScreen(tester);
      final bpm = tester.getRect(find.byKey(MetronomeScreen.bpmKey));
      expect(find.byType(PolyLane), findsNothing, reason: 'off: no lane');
      controller.setPolyrhythm(3);
      await tester.pump();
      expect(tester.getRect(find.byKey(MetronomeScreen.bpmKey)), bpm);
      final cells = [
        for (var k = 0; k < 3; k++)
          tester.getRect(find.byKey(ValueKey('pulse-$k-off'))),
      ];
      final beat1 = tester.getRect(find.byKey(const ValueKey('beat-0-off')));
      final beat4 = tester.getRect(find.byKey(const ValueKey('beat-3-off')));
      expect(cells.first.left, beat1.left);
      expect(cells.last.right, closeTo(beat4.right, 0.01));
      expect(cells[1].left - cells[0].right, closeTo(6, 0.01));
      expect(cells.first.height, PolyLane.height);
      expect(
        cells.first.top - beat1.bottom,
        closeTo(2, 0.5),
        reason: 'subdivision 1 hides the strip: 2px under the blocks',
      );
      await tester.tap(find.byKey(const ValueKey('pulse-1-off')));
      expect(controller.pattern.polyStates[1], StepLevel.accent);
    });
    testWidgets('the panels drop from the top row: under it, 12px from the '
        'edges, the top row sharp above; tap outside, the same button, Back '
        'or a swipe up closes; the other button swaps; the click plays on', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      final rowBottom = tester.getBottomLeft(find.byKey(TopPanel.topRowKey)).dy;
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await settle();
      final panel = tester.getRect(find.byKey(TopPanel.surfaceKey));
      expect(panel.top, rowBottom);
      expect(panel.left, 12);
      expect(panel.right, 800 - 12);
      expect(
        tester.getBottomLeft(find.byKey(TopPanel.handleKey)).dy,
        lessThan(panel.bottom),
        reason: 'the handle at its bottom edge',
      );
      // The same button again closes it.
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await settle();
      expect(find.byType(TimeSignatureSheet), findsNothing);
      // Outside (the dimmed screen) closes it.
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await settle();
      await tester.tapAt(const Offset(4, 300)); // beside the panel
      await settle();
      expect(find.byType(TimeSignatureSheet), findsNothing);
      // The other top-row button swaps to its panel.
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await settle();
      await tester.tap(find.byKey(MetronomeScreen.onStartKey));
      await settle();
      expect(find.byType(TimeSignatureSheet), findsNothing);
      expect(find.byType(OnStartSheet), findsOneWidget);
      // Back closes it.
      await tester.binding.handlePopRoute();
      await settle();
      expect(find.byType(OnStartSheet), findsNothing);
      // A short swipe up springs back; past a third closes.
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await settle();
      final height = tester.getSize(find.byKey(TopPanel.surfaceKey)).height;
      final top = tester.getTopLeft(find.byKey(TopPanel.surfaceKey));
      await tester.timedDrag(
        find.byKey(TopPanel.handleKey),
        Offset(0, -height * 0.2),
        const Duration(seconds: 1),
      );
      await settle();
      expect(tester.getTopLeft(find.byKey(TopPanel.surfaceKey)), top);
      await tester.timedDrag(
        find.byKey(TopPanel.handleKey),
        Offset(0, -height * 0.45),
        const Duration(seconds: 1),
      );
      await settle();
      expect(find.byType(TimeSignatureSheet), findsNothing);
      expect(controller.isPlaying, isTrue, reason: 'the click plays on');
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });

    for (final (size, fits) in [
      (const Size(412, 915), true),
      (const Size(360, 560), false),
    ]) {
      testWidgets('panels fit their content down to 16px above the bottom '
          '(over the gesture bar): ${size.width.toInt()}×'
          '${size.height.toInt()}', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1
          ..padding = const FakeViewPadding(bottom: 24)
          ..viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.reset);
        controller.setPolyrhythm(3);
        await pumpScreen(tester);
        for (final button in [
          MetronomeScreen.meterKey,
          MetronomeScreen.onStartKey,
        ]) {
          await tester.tap(find.byKey(button));
          await tester.pumpAndSettle();
          final panel = tester.getRect(find.byKey(TopPanel.surfaceKey));
          final scroll = tester
              .state<ScrollableState>(
                find.descendant(
                  of: find.byKey(TopPanel.surfaceKey),
                  matching: find.byType(Scrollable),
                ),
              )
              .position;
          expect(panel.bottom, lessThanOrEqualTo(size.height - 24 - 16));
          if (fits || button == MetronomeScreen.onStartKey) {
            expect(scroll.maxScrollExtent, 0, reason: 'opens fully');
          } else {
            expect(panel.bottom, size.height - 24 - 16);
            expect(scroll.maxScrollExtent, greaterThan(0));
          }
          await tester.tapAt(Offset(4, size.height - 4));
          await tester.pumpAndSettle();
        }
      });
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
      expect(find.text('Rhythm'), findsOneWidget);
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

    testWidgets('the Rhythm sheet sets the subdivision live and stays '
        'open; the 4/4 button shows its note', (tester) async {
      await pumpScreen(tester);
      expect(find.bySemanticsLabel('Rhythm 4/4'), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.meterKey));
      await tester.pumpAndSettle();
      expect(find.text('Rhythm'), findsOneWidget);
      Finder segment(int steps) => find.descendant(
        of: find.byKey(TimeSignatureSheet.subdivisionKey),
        matching: find.byKey(ValueKey('segment-$steps')),
      );
      for (final expected in [2, 3, 4, 1]) {
        await tester.tap(segment(expected));
        await tester.pump();
        expect(controller.pattern.stepsPerBeat, expected);
      }
      await tester.tap(segment(2));
      await tester.pump();
      expect(find.byType(TimeSignatureSheet), findsOneWidget);
      expect(controller.pattern.timeSignature, '4/4');
      expect(find.byKey(const ValueKey('beat-3-off')), findsOneWidget);
      expect(find.byKey(const ValueKey('tick-3-1-off')), findsOneWidget);
      expect(find.bySemanticsLabel('Rhythm 4/4, eighth notes'), findsOneWidget);
      controller.setPolyrhythm(3);
      await tester.pump();
      expect(
        find.bySemanticsLabel('Rhythm 4/4, eighth notes, polyrhythm 3'),
        findsOneWidget,
      );
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

    testWidgets('with subdivisions the beat dot lights at the beat only', (
      tester,
    ) async {
      controller.setPattern(
        MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2),
      );
      controller.setVisualOffset(Duration.zero);
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      // 120 BPM, 2 per beat: steps at 120, 370, 620 ms.
      output.time = const Duration(milliseconds: 140);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('beat-0-on')), findsOneWidget);
      // After its pulse, in frames, as the clock moves.
      while (output.time < const Duration(milliseconds: 520)) {
        output.time += const Duration(milliseconds: 20);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const ValueKey('beat-0-off')), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('top row at ${(scale * 100).round()}% text: stopwatch, 4/4 '
        'and gear share one visible 44px box on one line; 4/4 only wider; '
        '48dp touch targets', (tester) async {
      controller
        ..setPattern(
          MetronomePattern.simple(
            beatsPerBar: 12,
            stepsPerBeat: 3,
            beatUnit: 8,
          ),
        )
        ..setPolyrhythm(5);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(412, 915),
            textScaler: TextScaler.linear(scale),
          ),
          child: MaterialApp(
            theme: testTheme,
            home: MetronomeScreen(controller: controller),
          ),
        ),
      );
      addTearDown(controller.dispose);
      Rect box(Key key) => tester.getRect(
        find.descendant(of: find.byKey(key), matching: find.byType(Material)),
      );
      final boxes = [
        for (final key in [
          MetronomeScreen.onStartKey,
          MetronomeScreen.meterKey,
          MetronomeScreen.settingsKey,
        ])
          box(key),
      ];
      for (final b in boxes) {
        expect(b.height, 44);
        expect(b.top, boxes.first.top);
      }
      expect(boxes[0].width, 44);
      expect(boxes[2].width, 44);
      expect(boxes[1].width, greaterThan(44));
      for (final key in [
        MetronomeScreen.onStartKey,
        MetronomeScreen.meterKey,
      ]) {
        expect(tester.getSize(find.byKey(key)).height, 48, reason: 'touch');
      }
      final side = tester
          .widget<OutlinedButton>(find.byKey(MetronomeScreen.meterKey))
          .style;
      expect(side?.side, isNull, reason: 'the theme border, as the others');
      expect(tester.takeException(), isNull);
    });
  }

  group('when I press Start', () {
    // Null: the theme's plain outline.
    Color? outline(WidgetTester tester) => tester
        .widget<OutlinedButton>(find.byKey(MetronomeScreen.onStartKey))
        .style
        ?.side
        ?.resolve({})
        ?.color;

    testWidgets('the sheet: three equal switch rows when off; on unfolds the '
        'controls with a summary; off folds them, values kept; the stopwatch '
        'is red while any is on', (tester) async {
      tester.view
        ..physicalSize = const Size(420, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpScreen(tester);
      expect(outline(tester), isNull);
      await tester.tap(find.byKey(MetronomeScreen.onStartKey));
      await tester.pumpAndSettle();
      expect(find.text('When I press Start'), findsOneWidget);
      double rowHeight(String name) => tester
          .getSize(
            find
                .ancestor(of: find.text(name), matching: find.byType(Container))
                .first,
          )
          .height;
      for (final name in ['Count-in', 'Speed up', 'Stop after']) {
        expect(rowHeight(name), 56, reason: name);
      }
      expect(find.byType(Switch), findsNWidgets(3));
      expect(find.text(OnStartSheet.countInHint), findsNothing);
      expect(find.text(OnStartSheet.everyLabel), findsNothing);
      expect(find.text(OnStartSheet.lengthLabel), findsNothing);

      Finder inSheet(String text) => find.descendant(
        of: find.byType(OnStartSheet),
        matching: find.text(text),
      );
      // Count-in: 1 bar by default.
      await tester.tap(find.byKey(OnStartSheet.countInKey));
      await tester.pumpAndSettle();
      expect(controller.countIn, 1);
      expect(outline(tester), testTheme.extension<MetraColors>()!.accent);
      expect(inSheet('2 bars'), findsOneWidget);
      expect(inSheet('1 bar'), findsNWidgets(2), reason: 'summary + choice');
      await tester.tap(inSheet('2 bars'));
      await tester.pump();
      expect(controller.countIn, 2);
      expect(
        find.byTooltip('When I press Start: count-in 2 bars'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(OnStartSheet.countInKey));
      await tester.pumpAndSettle();
      expect(controller.countIn, 0);
      expect(
        find.text(OnStartSheet.countInHint),
        findsNothing,
        reason: 'folded',
      );
      expect(outline(tester), isNull);
      await tester.tap(find.byKey(OnStartSheet.countInKey));
      await tester.pumpAndSettle();
      expect(controller.countIn, 2, reason: 'kept while off');
      await tester.tap(find.byKey(OnStartSheet.countInKey));
      await tester.pumpAndSettle();

      // Speed up: three steppers, the summary.
      await tester.tap(find.byKey(OnStartSheet.speedUpKey));
      await tester.pumpAndSettle();
      expect(controller.onStart.speedUp, isTrue);
      expect(outline(tester), isNotNull, reason: 'speed up alone');
      for (final text in [
        OnStartSheet.changeLabel,
        OnStartSheet.everyLabel,
        'Up to',
        OnStartSheet.speedUpHint,
        '+5 every 8 bars',
        'No limit',
      ]) {
        expect(inSheet(text), findsOneWidget, reason: text);
      }
      controller.setOnStart(controller.onStart.withUpTo(160));
      await tester.pump();
      expect(inSheet('+5 every 8 bars, up to 160'), findsOneWidget);
      await tester.tap(find.byKey(OnStartSheet.speedUpKey));
      await tester.pumpAndSettle();
      expect(outline(tester), isNull);

      // Stop after: Time by default, Length.
      await tester.tap(find.byKey(OnStartSheet.stopAfterKey));
      await tester.pumpAndSettle();
      expect(controller.onStart.stopAfter, StopAfter.time);
      expect(outline(tester), isNotNull, reason: 'stop after alone');
      expect(inSheet(OnStartSheet.lengthLabel), findsOneWidget);
      expect(inSheet('5:00'), findsNWidgets(2), reason: 'summary + field');
      expect(inSheet(OnStartSheet.stopAfterHint), findsOneWidget);
      await tester.tap(inSheet('Bars'));
      await tester.pump();
      expect(controller.onStart.stopAfter, StopAfter.bars);
      expect(inSheet('32 bars'), findsOneWidget);
    });

    testWidgets('styling: 18px semibold headings; off switches outlined in '
        'white, never greyed; choices are labelled chip rows', (tester) async {
      tester.view
        ..physicalSize = const Size(420, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final colors = testTheme.extension<MetraColors>()!;
      controller.setOnStart(const OnStart(countInOn: true, stopOn: true));
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.onStartKey));
      await tester.pumpAndSettle();
      final heading = tester.widget<Text>(find.text('Speed up'));
      expect(heading.style!.fontSize, 18);
      expect(heading.style!.fontWeight, FontWeight.w600);
      final off = tester.widget<Switch>(find.byKey(OnStartSheet.speedUpKey));
      expect(off.trackOutlineColor!.resolve({}), colors.text);
      expect(off.thumbColor!.resolve({}), colors.text);
      expect(off.trackColor!.resolve({})!.a, 0);
      expect(off.onChanged, isNotNull, reason: 'off is not disabled');
      final on = tester.widget<Switch>(find.byKey(OnStartSheet.countInKey));
      expect(on.trackColor!.resolve({WidgetState.selected}), colors.text);
      expect(on.thumbColor!.resolve({WidgetState.selected}), colors.background);
      expect(find.text(OnStartSheet.countByLabel), findsOneWidget);
      expect(find.text(OnStartSheet.lengthLabel), findsNWidgets(2));
      ShapeDecoration chip(String key) =>
          tester
                  .widget<Container>(
                    find.descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(Container),
                    ),
                  )
                  .decoration!
              as ShapeDecoration;
      expect(chip('chip-1').color, colors.tickResting);
      expect((chip('chip-1').shape as StadiumBorder).side.color, colors.text);
      expect(chip('chip-2').color, isNull);
      expect((chip('chip-2').shape as StadiumBorder).side.color, colors.border);
      expect(tester.getSize(find.byKey(const ValueKey('chip-1'))).height, 48);
      await tester.tap(find.byKey(const ValueKey('chip-StopBy.bars')));
      await tester.pump();
      expect(controller.onStart.stopBy, StopBy.bars);
    });

    group('editing values', () {
      Future<void> openSheet(WidgetTester tester, OnStart on) async {
        tester.view
          ..physicalSize = const Size(420, 1400)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        controller.setOnStart(on);
        await pumpScreen(tester);
        await tester.tap(find.byKey(MetronomeScreen.onStartKey));
        await tester.pumpAndSettle();
      }

      Future<void> tapStep(WidgetTester tester, Key key) async {
        await tester.tap(find.byKey(key));
        await tester.pump();
      }

      Future<void> type(WidgetTester tester, String label, String text) async {
        await tester.tap(find.byKey(ValueStepper.fieldKey(label)));
        await tester.pump();
        await tester.enterText(find.byKey(ValueStepper.fieldKey(label)), text);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
      }

      testWidgets('− / + steps fit the unit; Up to starts at tempo + 20, '
          'stays above the tempo, and − from its lowest goes to No limit', (
        tester,
      ) async {
        await openSheet(
          tester,
          const OnStart(speedUp: true, changeBy: 1, every: 16),
        );
        await tapStep(tester, ValueStepper.plusKey(OnStartSheet.everyLabel));
        expect(controller.onStart.every, 20);
        await tapStep(tester, ValueStepper.plusKey('Up to'));
        expect(controller.onStart.upTo, 140, reason: '120 + 20');
        await tapStep(tester, ValueStepper.plusKey('Up to'));
        expect(controller.onStart.upTo, 145);
        controller.setOnStart(controller.onStart.withUpTo(125));
        await tester.pump();
        await tapStep(tester, ValueStepper.minusKey('Up to'));
        expect(controller.onStart.upTo, 121, reason: 'tempo + 1 at least');
        await tapStep(tester, ValueStepper.minusKey('Up to'));
        expect(controller.onStart.upTo, isNull);
        expect(find.text('No limit'), findsOneWidget);
        // Slowing down: "Down to", below the tempo; the old limit drops.
        controller.setOnStart(controller.onStart.withUpTo(150));
        await tester.pump();
        await tapStep(tester, ValueStepper.minusKey(OnStartSheet.changeLabel));
        expect(controller.onStart.changeBy, -1, reason: 'skips 0');
        expect(controller.onStart.upTo, isNull);
        expect(find.text('Down to'), findsOneWidget);
        expect(find.text('Up to'), findsNothing);
        await tapStep(tester, ValueStepper.minusKey('Down to'));
        expect(controller.onStart.upTo, 100, reason: '120 − 20');
        await tapStep(tester, ValueStepper.plusKey('Down to'));
        expect(controller.onStart.upTo, 105);
        controller.setOnStart(controller.onStart.withUpTo(115));
        await tester.pump();
        await tapStep(tester, ValueStepper.plusKey('Down to'));
        expect(controller.onStart.upTo, 119, reason: 'tempo − 1 at most');
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(
                  of: find.byKey(ValueStepper.plusKey('Down to')),
                  matching: find.byType(FilledButton),
                ),
              )
              .enabled,
          isFalse,
        );
      });

      testWidgets('tap to type: snaps into range (Up to above the tempo); '
          'time fills from the right; an empty Up to is No limit', (
        tester,
      ) async {
        await openSheet(
          tester,
          const OnStart(speedUp: true, upTo: 150, stopOn: true),
        );
        await type(tester, OnStartSheet.everyLabel, '99');
        expect(controller.onStart.every, 64);
        expect(find.text('64 bars'), findsOneWidget);
        await type(tester, 'Up to', '100');
        expect(controller.onStart.upTo, 121, reason: 'above the tempo');
        await type(tester, 'Up to', '999');
        expect(controller.onStart.upTo, 300);
        await type(tester, 'Up to', '');
        expect(controller.onStart.upTo, isNull);
        await type(tester, OnStartSheet.changeLabel, '0');
        expect(controller.onStart.changeBy, 1);
        await type(tester, OnStartSheet.changeLabel, '-7');
        expect(controller.onStart.changeBy, -7);
        // Typing 1, 2, 3, 0 over the selected value.
        final field = find.byKey(
          ValueStepper.fieldKey(OnStartSheet.lengthLabel),
        );
        await tester.tap(field);
        await tester.pump();
        var text = '';
        for (final digit in ['1', '2', '3', '0']) {
          text = '${tester.widget<TextField>(field).controller!.text}$digit';
          tester.testTextInput.updateEditingValue(TextEditingValue(text: text));
          await tester.pump();
        }
        expect(tester.widget<TextField>(field).controller!.text, '12:30');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(
          controller.onStart.stopTime,
          const Duration(minutes: 12, seconds: 30),
        );
        await type(tester, OnStartSheet.lengthLabel, '5');
        expect(controller.onStart.stopTime, OnStart.minTime, reason: 'snaps');
      });

      testWidgets('holding + repeats, accelerating, with a bump at the limit', (
        tester,
      ) async {
        await openSheet(
          tester,
          const OnStart(stopOn: true, stopBy: StopBy.bars, stopBars: 1),
        );
        final haptics = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments as String);
            }
            return null;
          },
        );
        final plus = find.byKey(ValueStepper.plusKey(OnStartSheet.lengthLabel));
        final gesture = await tester.startGesture(tester.getCenter(plus));
        await tester.pump(const Duration(milliseconds: 450));
        expect(controller.onStart.stopBars, 2, reason: 'one step at 0.4 s');
        Future<int> stepsIn(Duration span) async {
          final from = controller.onStart.stopBars;
          for (var t = Duration.zero; t < span; t += _frame) {
            await tester.pump(_frame);
          }
          return controller.onStart.stopBars - from;
        }

        // Bars step by 1 up to 16: the first half second is ~6 per second.
        final early = await stepsIn(const Duration(milliseconds: 500));
        expect(early, inInclusiveRange(2, 5));
        // Holding on: ~15 per second (from 16 the steps are 4 and 8 bars).
        final fromValue = controller.onStart.stopBars;
        await stepsIn(const Duration(seconds: 1));
        expect(controller.onStart.stopBars - fromValue, greaterThan(early * 4));
        // On to the end of the range: it stops with a medium bump.
        await stepsIn(const Duration(seconds: 12));
        expect(controller.onStart.stopBars, OnStart.maxBars);
        expect(haptics, contains('HapticFeedbackType.mediumImpact'));
        await gesture.up();
        await tester.pump();
      });
    });

    testWidgets('while a run plays, the line under the BPM shows progress', (
      tester,
    ) async {
      controller.setOnStart(
        const OnStart(
          speedUp: true,
          changeBy: 5,
          every: 2,
          stopOn: true,
          stopBy: StopBy.bars,
          stopBars: 8,
        ),
      );
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      // 120 bpm 4/4 from 120 ms: bar 1 starts at 2120.
      while (output.time < const Duration(milliseconds: 2200)) {
        output.time += const Duration(milliseconds: 20);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        find.text('↗ +5 every 2 bars · next in 1 · 7 bars left'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      expect(find.byKey(MetronomeScreen.countInLineKey), findsNothing);
      expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
    });

    testWidgets('counting in: numbers in the blocks, lit as they sound, '
        'ticks dark, "Count-in · 3 of 4"; then the song, nothing moved', (
      tester,
    ) async {
      controller
        ..setPattern(MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 2))
        ..setCountIn(2);
      await pumpScreen(tester);
      final bpmAt = tester.getTopLeft(find.byKey(MetronomeScreen.bpmKey));
      final rulerAt = tester.getTopLeft(find.byType(TempoRuler));
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      Future<void> to(int ms) async {
        while (output.time < Duration(milliseconds: ms)) {
          output.time += const Duration(milliseconds: 20);
          await tester.pump(const Duration(milliseconds: 20));
        }
      }

      // 120 bpm: count-in beats every 500 ms from 120 ms, 2 bars.
      await to(140);
      expect(find.byKey(const ValueKey('count-in-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat-0-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('tick-0-0-off')), findsOneWidget);
      expect(find.text('Count-in · 1 · 1 of 4'), findsOneWidget);
      await to(1140);
      expect(find.text('Count-in · 1 · 3 of 4'), findsOneWidget);
      expect(find.byKey(const ValueKey('beat-2-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('tick-2-0-off')), findsOneWidget);
      expect(find.byKey(const ValueKey('tick-2-1-off')), findsOneWidget);
      await to(3640);
      expect(find.text('Count-in · 2 · 4 of 4'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(MetronomeScreen.bpmKey)), bpmAt);
      expect(tester.getTopLeft(find.byType(TempoRuler)), rulerAt);
      // The song: beat 1 at 120 + 8 × 500 ms.
      await to(4140);
      expect(find.byKey(const ValueKey('count-in-1')), findsNothing);
      expect(find.byKey(MetronomeScreen.countInLineKey), findsNothing);
      expect(find.byKey(const ValueKey('beat-0-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('tick-0-0-on')), findsOneWidget);
      expect(find.byKey(MetronomeScreen.tempoNameKey), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
    });

    testWidgets('Stop during a count-in stops; the numbers go', (tester) async {
      controller.setCountIn(1);
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      output.time = const Duration(milliseconds: 140);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('count-in-1')), findsOneWidget);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      expect(controller.isPlaying, isFalse);
      expect(find.byKey(const ValueKey('count-in-1')), findsNothing);
      expect(find.byKey(MetronomeScreen.countInLineKey), findsNothing);
    });
  });

  testWidgets('tempo name follows the bpm', (tester) async {
    await pumpScreen(tester);
    String name() =>
        // The newest, while the old one cross-fades out.
        tester
            .widget<Text>(find.byKey(MetronomeScreen.tempoNameKey).last)
            .data!;
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

    testWidgets('lights pulse: up just before the click, lit ~35% of their '
        'interval, then down; a block over its beat, a tick over its own '
        'click', (tester) async {
      await startTwoPerBeat(tester);
      // Beat 1 at 120 ms; beats 500 ms apart, eighths 250 ms.
      await playAt(tester, 140);
      expect(key('beat-0-on'), findsOneWidget);
      expect(key('tick-0-0-on'), findsOneWidget);
      expect(key('tick-0-1-off'), findsOneWidget);
      final full = tester.widget<Container>(key('beat-0-on')).color;
      await playAt(tester, 300); // still within 15 + 175 ms
      expect(tester.widget<Container>(key('beat-0-on')).color, full);
      await playAt(tester, 400); // coming down; the eighth is up
      expect(key('beat-0-on'), findsOneWidget);
      expect(tester.widget<Container>(key('beat-0-on')).color, isNot(full));
      expect(key('tick-0-0-off'), findsOneWidget);
      expect(key('tick-0-1-on'), findsOneWidget);
      await playAt(tester, 500);
      expect(key('beat-0-off'), findsOneWidget, reason: 'resting');
      await playAt(tester, 610); // 10 ms before beat 2: already rising
      expect(key('beat-1-on'), findsOneWidget);
      await stop(tester);
      expect(key('beat-1-off'), findsOneWidget);
    });

    testWidgets('300 bpm in 16ths: each tick pulses at its click and is '
        'back at rest by the next', (tester) async {
      controller
        ..setBpm(300)
        ..setPattern(MetronomePattern.simple(beatsPerBar: 4, stepsPerBeat: 4))
        ..setVisualOffset(Duration.zero);
      await pumpScreen(tester);
      await tester.tap(find.byKey(MetronomeScreen.playKey));
      await tester.pump();
      // 16ths at 300 bpm are 50 ms apart, from 120 ms.
      for (var n = 1; n < 8; n++) {
        final at = 120 + n * 50;
        final (beat, tick) = (n ~/ 4, n % 4);
        final (pb, pt) = ((n - 1) ~/ 4, (n - 1) % 4);
        await playAt(tester, at + 4);
        expect(key('tick-$beat-$tick-on'), findsOneWidget, reason: 'step $n');
        expect(key('tick-$pb-$pt-off'), findsOneWidget, reason: 'rested');
      }
      await stop(tester);
    });

    testWidgets('"Remove animations": fully on at the click for the same lit '
        'time, then off (no ramp)', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await startTwoPerBeat(tester);
      await playAt(tester, 110);
      expect(key('beat-0-off'), findsOneWidget, reason: 'no early rise');
      await playAt(tester, 140);
      final lit = tester.widget<Container>(key('beat-0-on')).color;
      await playAt(tester, 300);
      expect(tester.widget<Container>(key('beat-0-on')).color, lit);
      await playAt(tester, 320);
      expect(key('beat-0-off'), findsOneWidget);
      await stop(tester);
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
      expect(node.value, '120 BPM, Allegro');
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
      await tester.tap(find.byKey(const ValueKey('beat-1-off')));
      await tester.pump(const Duration(seconds: 1));
      expect(haptics, List.filled(3, 'lightImpact'));
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

  group('motion: text swaps in place', () {
    Finder digits() => find.descendant(
      of: find.byKey(MetronomeScreen.bpmKey),
      matching: find.byType(Text),
    );

    Iterable<double> dims(WidgetTester tester) => tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byKey(MetronomeScreen.bpmKey),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity);

    testWidgets('BPM: the changed digit snaps in at ~60% and brightens to '
        'full; the old is gone at once; the others untouched; nothing '
        'moves', (tester) async {
      controller.setBpm(120);
      await pumpScreen(tester);
      Rect at(Finder f) => tester.getRect(f);
      final bpm = at(find.byKey(MetronomeScreen.bpmKey));
      final ruler = at(find.byType(TempoRuler));
      final units = at(find.text('0'));
      controller.setBpm(121);
      await tester.pump();
      expect(digits(), findsNWidgets(3), reason: 'never two shapes');
      expect(find.text('0'), findsNothing, reason: 'the old is gone');
      expect(dims(tester), [MetraMotion.brightenFrom], reason: 'units only');
      expect(at(find.text('1').last).center, units.center);
      await tester.pump(MetraMotion.brighten ~/ 2);
      expect(dims(tester).single, inExclusiveRange(0.6, 1));
      expect(at(find.byKey(MetronomeScreen.bpmKey)), bpm);
      expect(at(find.byType(TempoRuler)), ruler);
      await tester.pump(MetraMotion.brighten);
      expect(dims(tester), isEmpty, reason: 'full');
    });

    testWidgets('a change within ~250 ms of the last shows at full at once '
        '(fast tapping never pulses)', (tester) async {
      controller.setBpm(120);
      await pumpScreen(tester);
      controller.setBpm(121);
      await tester.pump();
      expect(dims(tester), isNotEmpty);
      await tester.pump(const Duration(milliseconds: 150));
      controller.setBpm(122);
      await tester.pump();
      expect(dims(tester), isEmpty);
      await tester.pump(const Duration(milliseconds: 400));
      controller.setBpm(123);
      await tester.pump();
      expect(dims(tester), isNotEmpty, reason: 'a slow change brightens');
      await tester.pump(MetraMotion.brighten * 2);
    });

    testWidgets('while the tempo is being held or dragged, instant', (
      tester,
    ) async {
      await pumpScreen(tester);
      MetraMotion.tempoMoving.value++;
      addTearDown(() => MetraMotion.tempoMoving.value--);
      await tester.pump();
      controller.setBpm(121);
      await tester.pump();
      expect(dims(tester), isEmpty, reason: 'at full at once');
    });

    testWidgets('"Remove animations": instant', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScreen(tester);
      controller.setBpm(121);
      await tester.pump();
      expect(dims(tester), isEmpty);
    });
  });
}
