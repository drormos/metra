import 'package:flutter_test/flutter_test.dart';
import 'package:metra/main.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/ui/metronome_screen.dart';

import 'audio/fake_click_output.dart';

void main() {
  testWidgets('shows the metronome when the engine is up', (tester) async {
    final controller = MetronomeController(FakeClickOutput());
    addTearDown(controller.dispose);
    await tester.pumpWidget(MetraApp(controller: controller));
    expect(find.byType(MetronomeScreen), findsOneWidget);
  });

  testWidgets('reports an engine failure and offers a retry', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MetraApp(engineError: 'no device', onRetry: () => retries++),
    );
    expect(find.textContaining('no device'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });
}
