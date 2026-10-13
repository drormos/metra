import 'package:flutter/material.dart';

import 'src/audio/soloud_click_output.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SoloudClickOutput? output;
  Object? engineError;
  try {
    output = await SoloudClickOutput.create();
  } catch (e) {
    engineError = e;
  }
  runApp(MetraApp(output: output, engineError: engineError));
}

class MetraApp extends StatelessWidget {
  const MetraApp({super.key, this.output, this.engineError});

  /// Null when the engine failed to start (see [engineError]).
  final SoloudClickOutput? output;
  final Object? engineError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Metra',
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          // Placeholder until the UI shell (PLAN.md Phase 1 step 4).
          child: Text(
            engineError == null
                ? 'Metra'
                : 'Audio engine failed to start: $engineError',
          ),
        ),
      ),
    );
  }
}
