import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/platform/android_bridge.dart';

import '../audio/fake_click_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  late List<MethodCall> sent;
  late bool pendingStart;
  late MetronomeController controller;

  setUp(() {
    sent = [];
    pendingStart = false;
    controller = MetronomeController(FakeClickOutput());
    messenger.setMockMethodCallHandler(AndroidBridge.tile, (call) async {
      sent.add(call);
      return call.method == 'takePendingStart' ? pendingStart : null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(AndroidBridge.tile, null);
    controller.dispose();
  });

  /// The tile calling into Dart, as PlaybackTile.kt does.
  Future<Object?> fromTile(String method) async {
    final reply = await messenger.handlePlatformMessage(
      AndroidBridge.tile.name,
      codec.encodeMethodCall(MethodCall(method)),
      (_) {},
    );
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  List<Object?> playingSent() => [
    for (final call in sent)
      if (call.method == 'playing') call.arguments,
  ];

  test('the tile shows the state and toggles the click', () async {
    await AndroidBridge.attachTile(controller);
    expect(playingSent(), [false]);
    expect(await fromTile('toggle'), isTrue);
    expect(controller.isPlaying, isTrue);
    expect(playingSent(), [false, true]);
    expect(await fromTile('toggle'), isTrue);
    expect(controller.isPlaying, isFalse);
    expect(playingSent(), [false, true, false]);
  });

  test('opened from the tile, the app starts the click', () async {
    pendingStart = true;
    await AndroidBridge.attachTile(controller);
    expect(controller.isPlaying, isTrue);
    controller.stop();
  });

  test('"start" (app already open) starts, never stops', () async {
    await AndroidBridge.attachTile(controller);
    await fromTile('start');
    await fromTile('start');
    expect(controller.isPlaying, isTrue);
    controller.stop();
  });
}
