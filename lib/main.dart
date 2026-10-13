import 'package:flutter/material.dart';

import 'src/audio/soloud_click_output.dart';
import 'src/controller/metronome_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MetronomeController? controller;
  Object? engineError;
  try {
    controller = MetronomeController(await SoloudClickOutput.create());
    AppLifecycleListener(onStateChange: controller.didChangeAppLifecycleState);
  } catch (e) {
    engineError = e;
  }
  runApp(MetraApp(controller: controller, engineError: engineError));
}

class MetraApp extends StatelessWidget {
  const MetraApp({super.key, this.controller, this.engineError});

  /// Null when the engine failed to start (see [engineError]).
  final MetronomeController? controller;
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
