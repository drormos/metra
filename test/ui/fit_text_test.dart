import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/fit_text.dart';

/// The test font draws every character one em wide, so widths are exact.
void main() {
  Future<double> sizeFor(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 100,
            child: FitText(
              text,
              minFontSize: 13,
              textKey: const Key('text'),
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ),
      ),
    );
    final shown = tester.widget<Text>(find.byKey(const Key('text')));
    expect(shown.maxLines, 1);
    expect(shown.overflow, TextOverflow.ellipsis);
    return shown.style!.fontSize!;
  }

  testWidgets('full size when it fits', (tester) async {
    expect(await sizeFor(tester, 'Iron'), 18); // 72px
  });

  testWidgets('shrinks to fit', (tester) async {
    expect(await sizeFor(tester, 'Rust Be'), 14); // 126px at 18 → 14.3
  });

  testWidgets('stops at the minimum, then ellipsis', (tester) async {
    expect(await sizeFor(tester, 'A very long song name'), 13);
  });
}
