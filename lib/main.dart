import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'src/audio/call_pause.dart';
import 'src/audio/headphone_guard.dart';
import 'src/audio/metronome_audio_handler.dart';
import 'src/audio/soloud_click_output.dart';
import 'src/controller/keep_awake.dart';
import 'src/controller/library_controller.dart';
import 'src/controller/metronome_controller.dart';
import 'src/model/library.dart';
import 'src/model/whats_new.dart';
import 'src/platform/android_bridge.dart';
import 'src/storage/library_store.dart';
import 'src/ui/haptics.dart';
import 'src/ui/media_cover.dart';
import 'src/ui/metronome_screen.dart';
import 'src/ui/stage_screen.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MetronomeController? controller;
  LibraryController? library;
  Object? engineError;
  String? libraryProblem;
  // Logs are for development; a release build keeps logcat quiet.
  if (kReleaseMode) debugPrint = (message, {wrapWidth}) {};
  // Before the engine starts its output: flutter_soloud leaves the iOS
  // audio session to the app.
  if (Platform.isIOS) await _initIosAudioSession();
  try {
    controller = MetronomeController(await SoloudClickOutput.create());
    AppLifecycleListener(onStateChange: controller.didChangeAppLifecycleState);
  } catch (e) {
    engineError = e;
  }
  if (controller != null) {
    (library, libraryProblem) = await _loadLibrary();
    // A fresh install gets the example songs and set; the What's new of
    // the version it installed counts as seen.
    await WhatsNew.load();
    if (library != null && library.freshInstall) {
      library.addExamples();
      WhatsNew.markSeen(library);
    }
    library?.attach(controller);
    // A fresh launch is always Free play, with the click as it last
    // sounded; the song stays as stored (ui-spec.md "Modes"). Stage mode
    // is the one exception: it returns on the same set and song.
    if (library != null && library.stageMode) {
      library.resumeStageMode(controller);
    } else {
      library?.detachSong();
    }
    keepScreenAwake(
      controller,
      library,
      (awake) => WakelockPlus.toggle(enable: awake),
    );
    if (library case final library?) {
      // "Vibrate on touch" gates every haptic.
      void syncHaptics() => Haptics.enabled = library.vibrate;
      syncHaptics();
      library.addListener(syncHaptics);
    }
    if (Platform.isAndroid) {
      final handler = await _initAndroidBackground(controller, library);
      if (library != null) AndroidBridge.syncLaunchTheme(library);
      // Not awaited: a start from the tile waits for the first frame.
      AndroidBridge.attachTile(controller, stop: handler?.stop);
      AndroidBridge.attachCalls(CallPause(controller, stop: handler?.stop));
    }
  }
  // Edge to edge: the screens keep clear of the bars with SafeArea.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(
    MetraApp(
      controller: controller,
      library: library,
      libraryProblem: libraryProblem,
      engineError: engineError,
      // A failed engine never got as far as the services below, so
      // starting over is safe.
      onRetry: main,
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
/// app still runs, it just doesn't remember anything, and says why.
Future<(LibraryController?, String?)> _loadLibrary() async {
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final library = await LibraryController.load(
      LibraryStore(File('${dir.path}/library.json')),
    );
    return (library, null);
  } on NewerLibraryException catch (e) {
    debugPrint('Library unavailable: $e');
    return (
      null,
      'Your songs were saved by a newer version of Metra. '
          'Update the app to open them.',
    );
  } catch (e) {
    debugPrint('Library unavailable: $e');
    return (null, "Your songs can't be opened, so changes won't be saved.");
  }
}

/// Keeps playing with the screen off or the app in the background. Failure
/// only costs background playback, so it doesn't block the app (null).
Future<MetronomeAudioHandler?> _initAndroidBackground(
  MetronomeController controller,
  LibraryController? library,
) async {
  try {
    final handler = await AudioService.init(
      builder: () => MetronomeAudioHandler(
        controller,
        library: library,
        cover: (bpm) async =>
            mediaCoverFile(await getTemporaryDirectory(), bpm),
        onClosed: () => exit(0),
      ),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.dror.metra.playback',
        androidNotificationChannelName: 'Metronome playback',
      ),
    );
    await stopOnHeadphoneRemoval(controller);
    return handler;
  } catch (e) {
    debugPrint('Background playback unavailable: $e');
    return null;
  }
}

class MetraApp extends StatelessWidget {
  const MetraApp({
    super.key,
    this.controller,
    this.library,
    this.libraryProblem,
    this.engineError,
    this.onRetry,
  });

  /// Null when the engine failed to start (see [engineError]).
  final MetronomeController? controller;
  final LibraryController? library;
  final String? libraryProblem;
  final Object? engineError;

  /// Starts the app over after an engine failure.
  final VoidCallback? onRetry;

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
        home: controller != null && library != null && library.stageMode
            ? StageScreen(controller: controller, library: library)
            : controller != null
            ? MetronomeScreen(
                controller: controller,
                library: library,
                libraryProblem: libraryProblem,
              )
            : _EngineFailure(error: engineError, onRetry: onRetry),
      ),
    );
  }
}

/// The audio engine didn't start: say so plainly, offer a retry, and keep
/// the details for a feedback email.
class _EngineFailure extends StatelessWidget {
  const _EngineFailure({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Metra couldn't start the sound.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20),
              ),
              const SizedBox(height: 8),
              const Text(
                'Try again. If it keeps happening, restart the phone.',
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
