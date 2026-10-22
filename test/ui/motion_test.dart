import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/motion.dart';
import 'package:metra/src/ui/theme.dart';

void main() {
  Widget host(String text) => Directionality(
    textDirection: TextDirection.ltr,
    child: FadeThrough(value: text, child: Text(text)),
  );

  double opacity(WidgetTester tester) {
    final o = find.ancestor(
      of: find.byType(Text),
      matching: find.byType(Opacity),
    );
    return o.evaluate().isEmpty ? 1 : tester.widget<Opacity>(o.first).opacity;
  }

  testWidgets('fade-through: old fades out fully, then the new fades in; '
      'never both', (tester) async {
    await tester.pumpWidget(host('One'));
    await tester.pumpWidget(host('Two'));
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsNothing);
    await tester.pump(MetraMotion.fadeOut ~/ 2);
    expect(find.text('One'), findsOneWidget, reason: 'fading out');
    expect(opacity(tester), inExclusiveRange(0, 1));
    await tester.pump(
      MetraMotion.fadeOut ~/ 2 + const Duration(milliseconds: 1),
    );
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
    expect(opacity(tester), lessThan(0.1), reason: 'starts invisible');
    await tester.pump(MetraMotion.fadeIn);
    expect(opacity(tester), 1);
  });

  testWidgets('the same text rebuilt: no animation', (tester) async {
    await tester.pumpWidget(host('One'));
    await tester.pumpWidget(host('One'));
    expect(opacity(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
