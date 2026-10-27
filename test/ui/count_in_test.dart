import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/ui/count_in.dart';

import '../audio/fake_click_output.dart';
import 'button_text.dart';
import 'test_theme.dart';

/// The Stop button's count-in (ui-spec.md "The button you pressed shows
/// the count").
void main() {
  const key = Key('stop');

  Future<MetronomeController> pump(
    WidgetTester tester, {
    required double width,
    double scale = 1,
  }) async {
    final controller = MetronomeController(FakeClickOutput())..setCountIn(1);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Center(
            child: SizedBox(
              width: width,
              height: 56,
              child: FilledButton(
                key: key,
                onPressed: () {},
                child: StopLabel(
                  controller: controller,
                  fontSize: 18,
                  iconSize: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.play();
    await tester.pump();
    return controller;
  }

  testWidgets('room for it: one line', (tester) async {
    final controller = await pump(tester, width: 790);
    expect(buttonText(tester, key), 'Stop · Count-in 1 of 4');
    controller.stop();
    await tester.pump();
    expect(buttonText(tester, key), 'Stop');
  });

  testWidgets('narrow, large text: two lines, the count whole, nothing '
      'overflows', (tester) async {
    final controller = await pump(tester, width: 200, scale: 2);
    expect(buttonText(tester, key), 'Stop | Count-in 1 of 4');
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(key));
    for (final text in tester.widgetList<RichText>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    )) {
      final rect = tester.getRect(find.byWidget(text));
      expect(
        button.contains(rect.topLeft) &&
            button.contains(rect.bottomRight - const Offset(0.01, 0.01)),
        isTrue,
      );
    }
    controller.stop();
    await tester.pump();
  });
}
