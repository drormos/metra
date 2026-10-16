import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';

/// Android-only links to `MainActivity` and the Quick Settings tile
/// (`PlaybackTile.kt`). Failures only cost the extra, never the app.
abstract final class AndroidBridge {
  static const android = MethodChannel('metra/android');
  static const tile = MethodChannel('metra/tile');

  /// Keeps the splash screen's theme in step with the app's theme
  /// setting, for the next launch.
  static void syncLaunchTheme(LibraryController library) {
    ThemeMode? sent;
    void sync() {
      final mode = library.themeMode;
      if (mode == sent) return;
      sent = mode;
      _call(android, 'setLaunchTheme', switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
      });
    }

    sync();
    library.addListener(sync);
  }

  /// The tile shows Playing / Stopped and toggles the click; opened from
  /// the tile, the app starts it. [stop] is the media handler's stop, so a
  /// stop from the tile keeps the stopped media card.
  static Future<void> attachTile(
    MetronomeController controller, {
    Future<void> Function()? stop,
  }) async {
    bool? sent;
    void sync() {
      if (controller.isPlaying == sent) return;
      sent = controller.isPlaying;
      _call(tile, 'playing', sent);
    }

    sync();
    controller.addListener(sync);
    tile.setMethodCallHandler((call) async {
      switch (call.method) {
        // False tells the tile to open the app and start there instead.
        case 'toggle':
          try {
            if (controller.isPlaying && stop != null) {
              await stop();
            } else {
              await controller.toggle();
            }
            return true;
          } on Object {
            return false;
          }
        case 'start':
          if (!controller.isPlaying) await controller.play();
          return null;
      }
      throw MissingPluginException();
    });
    if (await _call(tile, 'takePendingStart') == true &&
        !controller.isPlaying) {
      await controller.play();
    }
  }

  static Future<Object?> _call(
    MethodChannel channel,
    String method, [
    Object? arguments,
  ]) async {
    try {
      return await channel.invokeMethod<Object?>(method, arguments);
    } on Exception catch (e) {
      debugPrint('${channel.name}.$method: $e');
      return null;
    }
  }
}
