// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/audio/headphone_guard.dart';

AudioDevice _device(AudioDeviceType type, {bool isOutput = true}) =>
    AudioDevice(
      id: '1',
      name: 'test',
      isInput: !isOutput,
      isOutput: isOutput,
      type: type,
    );

void main() {
  test('headphones and headsets are personal outputs', () {
    for (final type in [
      AudioDeviceType.wiredHeadphones,
      AudioDeviceType.wiredHeadset,
      AudioDeviceType.bluetoothA2dp,
      AudioDeviceType.usbAudio,
    ]) {
      expect(isPersonalOutput(_device(type)), isTrue, reason: '$type');
    }
  });

  test('speakers, HDMI and inputs are not', () {
    expect(isPersonalOutput(_device(AudioDeviceType.builtInSpeaker)), isFalse);
    expect(isPersonalOutput(_device(AudioDeviceType.hdmi)), isFalse);
    expect(
      isPersonalOutput(_device(AudioDeviceType.wiredHeadset, isOutput: false)),
      isFalse,
    );
  });
}
