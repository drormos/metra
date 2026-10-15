import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/audio/headphone_guard.dart';
import 'src/audio/metronome_audio_handler.dart';
import 'src/audio/soloud_click_output.dart';
import 'src/controller/keep_awake.dart';
import 'src/controller/library_controller.dart';
import 'src/controller/metronome_controller.dart';
import 'src/platform/android_bridge.dart';
import 'src/storage/library_store.dart';
import 'src/ui/haptics.dart';
import 'src/ui/media_cover.dart';
import 'src/ui/metronome_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MetronomeController? controller;
  LibraryController? library;
  Object? engineError;
  // Before the engine starts its output: flutter_soloud leaves the iOS
  // audio session to the app.
  if (Platform.isIOS) await _initIosAudioSession();
  try {
    controller = MetronomeController(await SoloudClickOutput.create());
    AppLifecycleListener(onStateChange: controller.didChangeAppLifecycleState);
    keepAwakeWhilePlaying(
      controller,
      (awake) => WakelockPlus.toggle(enable: awake),
    );
  } catch (e) {
    engineError = e;
  }
  if (controller != null) {
    library = await _loadLibrary();
    library?.attach(controller);
    if (library case final library?) {
      // "Vibrate on touch" gates every haptic.
      void syncHaptics() => Haptics.enabled = library.vibrate;
      syncHaptics();
      library.addListener(syncHaptics);
    }
    if (Platform.isAndroid) {
      await _initAndroidBackground(controller, library);
      if (library != null) AndroidBridge.syncLaunchTheme(library);
      // Not awaited: a start from the tile waits for the first frame.
      AndroidBridge.attachTile(controller);
    }
  }
  // Edge to edge: the screens keep clear of the bars with SafeArea.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    MetraApp(
      controller: controller,
      library: library,
      engineError: engineError,
    ),
  );
}

/// Playback category: plays with the silent switch on and with the screen
/// locked (with the `audio` background mode in Info.plist). Mixes with other
/// audio, like Android, so the user's music keeps playing alongside.
Future<void> _initIosAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
      ),
    );
    await session.setActive(true);
  } catch (e) {
    debugPrint('iOS audio session setup failed: $e');
  }
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
Future<void> _initAndroidBackground(
  MetronomeController controller,
  LibraryController? library,
) async {
  try {
    await AudioService.init(
      builder: () => MetronomeAudioHandler(
        controller,
        library: library,
        cover: (bpm) async =>
            mediaCoverFile(await getTemporaryDirectory(), bpm),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.dror.metra.playback',
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
  const MetraApp({super.key, this.controller, this.library, this.engineError});

  /// Null when the engine failed to start (see [engineError]).
  final MetronomeController? controller;
  final LibraryController? library;
  final Object? engineError;

  static final _dark = metraTheme(MetraColors.stageBlack, Brightness.dark);
  static final _light = metraTheme(MetraColors.daylight, Brightness.light);

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final library = this.library;
    return ListenableBuilder(
      // Rebuilds for the theme setting; a null library follows the OS.
      listenable: Listenable.merge([?library]),
      builder: (context, _) => MaterialApp(
        title: 'Metra',
        debugShowCheckedModeBanner: false,
        theme: _light,
        darkTheme: _dark,
        themeMode: library?.themeMode ?? ThemeMode.system,
        // Bars match the theme (transparent, icons in contrast); English
        // only, so the layout never mirrors (ui-spec.md "Android basics").
        builder: (context, child) => AnnotatedRegion(
          value: systemBarsStyle(Theme.of(context).brightness),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child!,
          ),
        ),
        home: controller != null
            ? MetronomeScreen(controller: controller, library: library)
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
      ),
    );
  }
}
