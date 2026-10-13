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

  testWidgets('reports an engine failure', (tester) async {
    await tester.pumpWidget(const MetraApp(engineError: 'no device'));
    expect(find.textContaining('no device'), findsOneWidget);
  });
}
