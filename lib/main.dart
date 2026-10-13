import 'package:flutter/material.dart';

import 'src/audio/soloud_click_output.dart';
import 'src/controller/metronome_controller.dart';
import 'src/ui/metronome_screen.dart';

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
    final controller = this.controller;
    return MaterialApp(
      title: 'Metra',
      debugShowCheckedModeBanner: false,
      theme: _highContrastTheme,
      home: controller != null
          ? MetronomeScreen(controller: controller)
          : Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Audio engine failed to start: $engineError',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
    );
  }
}

final _highContrastTheme = ThemeData(
  colorScheme: const ColorScheme.highContrastDark(
    primary: Colors.amber,
    onPrimary: Colors.black,
    surface: Colors.black,
    onSurface: Colors.white,
  ),
  scaffoldBackgroundColor: Colors.black,
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white, width: 2),
    ),
  ),
);
