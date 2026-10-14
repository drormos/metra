// AudioDeviceType is marked experimental; pinned to audio_session 0.2.x.
// ignore_for_file: experimental_member_use

import 'package:audio_session/audio_session.dart';

import '../controller/metronome_controller.dart';

/// Stops the click when headphones disappear, so it never jumps to the
/// phone speaker.
///
/// Deliberately takes no audio focus: focus would pause the user's music,
/// and playing along with a track is a core metronome use. (audio_session's
/// "becoming noisy" event needs focus, so this watches device removal.)
Future<void> stopOnHeadphoneRemoval(MetronomeController controller) async {
  final session = await AudioSession.instance;
  session.devicesChangedEventStream.listen((event) {
    if (event.devicesRemoved.any(isPersonalOutput)) controller.stop();
  });
}

const _personalOutputs = {
  AudioDeviceType.wiredHeadset,
  AudioDeviceType.wiredHeadphones,
  AudioDeviceType.bluetoothA2dp,
  AudioDeviceType.bluetoothLe,
  AudioDeviceType.bluetoothSco,
  AudioDeviceType.usbAudio,
  AudioDeviceType.hearingAid,
};

/// Output devices only the wearer hears.
bool isPersonalOutput(AudioDevice device) =>
    device.isOutput && _personalOutputs.contains(device.type);
