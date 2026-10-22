import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/fit_text.dart';
import 'package:metra/src/ui/motion.dart';
import 'package:metra/src/ui/theme.dart';

void main() {
  const key = Key('name');
  Widget host(String text, {double width = 600, TextAlign? align}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Align(
              alignment: Alignment.topLeft,
              child: BrightenText(
                text,
                textKey: key,
                minFontSize: 10,
                baseline: 30,
                textAlign: align,
                style: const TextStyle(fontSize: 34, color: Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ),
      );

  /// Each span's text and alpha (1 when it has no color of its own).
  List<(String, double)> spans(WidgetTester tester) => [
    for (final span
        in (tester.widget<Text>(find.byKey(key)).textSpan! as TextSpan)
            .children!
            .cast<TextSpan>())
      (span.text!, span.style?.color?.a ?? 1),
  ];

  testWidgets('only the changed part snaps in at ~60% and brightens; the '
      'unchanged start stays at full; the old is gone at once', (tester) async {
    await tester.pumpWidget(host('Dead Weight'));
    await tester.pumpWidget(host('Dead Weight 2'));
    expect(find.byType(RichText), findsOneWidget, reason: 'one text');
    final [(same, full), (fresh, dim)] = spans(tester);
    expect((same, full), ('Dead Weight', 1.0));
    expect(fresh, ' 2');
    expect(dim, closeTo(MetraMotion.brightenFrom, 0.01));
    await tester.pump(MetraMotion.brighten ~/ 2);
    expect(spans(tester).last.$2, inExclusiveRange(0.6, 1));
    await tester.pump(MetraMotion.brighten);
    expect(tester.widget<Text>(find.byKey(key)).data, 'Dead Weight 2');
  });

  testWidgets('end-aligned text keeps its unchanged end', (tester) async {
    await tester.pumpWidget(host('98 BPM', align: TextAlign.right));
    await tester.pumpWidget(host('110 BPM', align: TextAlign.right));
    expect(spans(tester).map((s) => s.$1), ['110', ' BPM']);
    expect(spans(tester).last.$2, 1);
  });

  testWidgets('a new fitted size counts as all changed', (tester) async {
    await tester.pumpWidget(host('Short', width: 200));
    await tester.pumpWidget(host('A much longer name to shrink', width: 200));
    final [(same, _), (fresh, dim)] = spans(tester);
    expect(same, isEmpty);
    expect(fresh, 'A much longer name to shrink');
    expect(dim, closeTo(MetraMotion.brightenFrom, 0.01));
  });

  testWidgets('a change within 250 ms of the last shows at full; a rebuild '
      'with the same text never animates', (tester) async {
    await tester.pumpWidget(host('One'));
    await tester.pumpWidget(host('Two'));
    expect(tester.widget<Text>(find.byKey(key)).data, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(host('Three'));
    expect(tester.widget<Text>(find.byKey(key)).data, 'Three');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(host('Three'));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('instant while the tempo is held or dragged, and with '
      '"Remove animations"', (tester) async {
    await tester.pumpWidget(host('One'));
    MetraMotion.tempoMoving.value++;
    await tester.pumpWidget(host('Two'));
    MetraMotion.tempoMoving.value--;
    expect(tester.widget<Text>(find.byKey(key)).data, 'Two');
    await tester.pump(const Duration(milliseconds: 400));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(host('Three'));
    expect(tester.widget<Text>(find.byKey(key)).data, 'Three');
  });

  testWidgets('BrightenSwap: a new state snaps in at ~60% and brightens', (
    tester,
  ) async {
    Widget swap(String v) => Directionality(
      textDirection: TextDirection.ltr,
      child: BrightenSwap(value: v, child: Text(v)),
    );
    await tester.pumpWidget(swap('Allegro'));
    expect(find.byType(Opacity), findsNothing);
    await tester.pumpWidget(swap('Revert'));
    expect(find.text('Allegro'), findsNothing, reason: 'gone at once');
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      closeTo(MetraMotion.brightenFrom, 0.01),
    );
    await tester.pump(MetraMotion.brighten * 2);
    expect(find.byType(Opacity), findsNothing);
  });
}
