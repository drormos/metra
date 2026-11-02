import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the microphone permission stands. [unknown]: never asked;
/// [blocked]: refused and Android won't ask again (only the app's
/// settings can allow it).
enum MicPermission { unknown, granted, denied, blocked }

/// The microphone, for the tuner only (ui-spec.md "Tuner"). Samples are
/// processed as they arrive and never kept or sent. Tests use a fake.
abstract class MicInput {
  Future<MicPermission> permission();

  /// Shows Android's permission dialog; the answer.
  Future<MicPermission> request();

  /// The app's page in the phone's settings.
  Future<void> openSettings();

  /// Starts listening; returns the sample rate, or null if it can't.
  /// Samples (mono, −1…1) arrive on [samples] until [stop].
  Future<int?> start();
  Future<void> stop();
  Stream<Float32List> get samples;
}

/// `MicBridge.kt`: `AudioRecord` in float, unprocessed where the phone
/// offers it. Elsewhere (Mac, iPhone) there's no microphone yet: it reads
/// as allowed and never starts, so the page shows "Play a string".
class AndroidMicInput implements MicInput {
  static const _channel = MethodChannel('metra/mic');
  static const _pcm = EventChannel('metra/mic/pcm');

  @override
  late final Stream<Float32List> samples = _pcm.receiveBroadcastStream().map(
    (data) => data as Float32List,
  );

  @override
  Future<MicPermission> permission() => _permission('permission');

  @override
  Future<MicPermission> request() => _permission('request');

  @override
  Future<void> openSettings() => _call('openSettings');

  @override
  Future<int?> start() async => (await _call('start')) as int?;

  @override
  Future<void> stop() => _call('stop');

  Future<MicPermission> _permission(String method) async {
    if (!Platform.isAndroid) return MicPermission.granted;
    return MicPermission.values.asNameMap()[await _call(method)] ??
        MicPermission.denied;
  }

  static Future<Object?> _call(String method) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Object?>(method);
    } on Exception catch (e) {
      debugPrint('metra/mic.$method: $e');
      return null;
    }
  }
}
