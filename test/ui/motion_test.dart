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
    expect(current[' 2'], closeTo(0.25, 0.02), reason: 'linear');
    expect(current[' 2']! + old['']!, closeTo(1, 1e-9), reason: 'sum 1');
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
    expect(layers[0].opacity + layers[1].opacity, closeTo(1, 1e-9));
    expect(layers[1].opacity, closeTo(0.3, 0.02), reason: 'linear');
    final baselines = [
      for (final b in tester.widgetList<Baseline>(find.byType(Baseline)))
        b.baseline,
    ];
    expect(baselines.toSet(), {30.0});
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
