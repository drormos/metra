import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/fit_text.dart';
import 'package:metra/src/ui/theme.dart';

void main() {
  const key = Key('name');
  Widget host(String text, {double width = 400}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: Align(
          alignment: Alignment.topLeft,
          child: DissolveText(
            text,
            textKey: key,
            minFontSize: 10,
            baseline: 30,
            style: const TextStyle(fontSize: 34, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ),
  );

  /// The alpha of each run of [rich] text's spans, by text.
  Map<String, double> alphas(WidgetTester tester, Finder f) => {
    for (final span
        in (tester.widget<Text>(f).textSpan! as TextSpan).children!
            .cast<TextSpan>())
      span.text!: span.style?.color?.a ?? 1,
  };

  testWidgets('same size: the shared start stays at full opacity; only the '
      'rest dissolves, old and new adding up to full', (tester) async {
    await tester.pumpWidget(host('Dead Weight', width: 600));
    await tester.pumpWidget(host('Dead Weight 2', width: 600));
    await tester.pump(MetraMotion.dissolve * 0.25);
    final texts = find.byType(RichText);
    expect(texts, findsNWidgets(2));
    final current = alphas(tester, find.byKey(key));
    final old = alphas(
      tester,
      find.byWidgetPredicate((w) => w is Text && w.key == null),
    );
    expect(old['Dead Weight'], 1, reason: 'drawn once, never dimmed');
    expect(current['Dead Weight'], 0);
    // The new leads: it's on its way in while the old is still full.
    expect(current[' 2'], inExclusiveRange(0, 1));
    expect(old[''], 1);
    // No Opacity anywhere: nothing dims as a whole.
    expect(find.byType(Opacity), findsNothing);
    await tester.pump(MetraMotion.dissolve);
    expect(texts, findsOneWidget);
    expect(tester.widget<Text>(find.byKey(key)).data, 'Dead Weight 2');
  });

  testWidgets('another size: the whole name dissolves, both on one '
      'baseline, linear and adding up to full', (tester) async {
    await tester.pumpWidget(host('Short', width: 200));
    await tester.pumpWidget(
      host('A much longer name that has to shrink', width: 200),
    );
    await tester.pump(MetraMotion.dissolve * 0.3);
    final layers = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(layers, hasLength(2));
    expect(layers[0].opacity, 1, reason: 'the old waits for the new');
    expect(layers[1].opacity, inExclusiveRange(0, 1));
    final baselines = [
      for (final b in tester.widgetList<Baseline>(find.byType(Baseline)))
        b.baseline,
    ];
    expect(baselines.toSet(), {30.0});
  });

  test('the new leads: the old stays full until the new is at 80%, then '
      'fades over 90 ms; ~160 ms in all', () {
    expect(MetraMotion.dissolve.inMilliseconds, inInclusiveRange(140, 170));
    for (var ms = 0; ms <= MetraMotion.dissolve.inMilliseconds; ms += 5) {
      final o = MetraMotion.dissolveAt(Duration(milliseconds: ms));
      if (o.old < 1) expect(o.next, greaterThanOrEqualTo(0.8), reason: '$ms');
      // Where strokes overlap, normal blending shows at least this much.
      expect(1 - (1 - o.next) * (1 - o.old), greaterThan(0.95), reason: '$ms');
    }
    final end = MetraMotion.dissolveAt(MetraMotion.dissolve);
    expect((end.next, end.old), (1.0, 0.0));
  });

  testWidgets('a rebuild with the same text: no animation', (tester) async {
    await tester.pumpWidget(host('One'));
    await tester.pumpWidget(host('One'));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(RichText), findsOneWidget);
  });

  testWidgets('"Remove animations": instant', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host('One'));
    await tester.pumpWidget(host('Two'));
    expect(find.byType(RichText), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(key)).data, 'Two');
  });
}
