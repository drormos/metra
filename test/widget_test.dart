import 'package:flutter_test/flutter_test.dart';
import 'package:metra/main.dart';

void main() {
  testWidgets('shows the app title when the engine is up', (tester) async {
    await tester.pumpWidget(const MetraApp());
    expect(find.text('Metra'), findsOneWidget);
  });

  testWidgets('reports an engine failure', (tester) async {
    await tester.pumpWidget(const MetraApp(engineError: 'no device'));
    expect(find.textContaining('no device'), findsOneWidget);
  });
}
