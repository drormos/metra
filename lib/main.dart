import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/audio/headphone_guard.dart';
import 'src/audio/metronome_audio_handler.dart';
import 'src/audio/soloud_click_output.dart';
import 'src/controller/library_controller.dart';
import 'src/controller/metronome_controller.dart';
import 'src/storage/library_store.dart';
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
  if (controller != null) {
    (await _loadLibrary())?.attach(controller);
    if (Platform.isAndroid) await _initAndroidBackground(controller);
  }
  runApp(MetraApp(controller: controller, engineError: engineError));
}

/// Saved songs, setlists and last-session settings. Without storage the
/// app still runs, it just doesn't remember anything.
Future<LibraryController?> _loadLibrary() async {
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return await LibraryController.load(
      LibraryStore(File('${dir.path}/library.json')),
    );
  } catch (e) {
    debugPrint('Library unavailable: $e');
    return null;
  }
}

/// Keeps playing with the screen off or the app in the background. Failure
/// only costs background playback, so it doesn't block the app.
Future<void> _initAndroidBackground(MetronomeController controller) async {
  try {
    await AudioService.init(
      builder: () => MetronomeAudioHandler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.metra.playback',
        androidNotificationChannelName: 'Metronome playback',
        androidNotificationOngoing: true,
      ),
    );
    await stopOnHeadphoneRemoval(controller);
  } catch (e) {
    debugPrint('Background playback unavailable: $e');
  }
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
