// Generates the click samples in assets/clicks/.
//
// Run with: dart run tool/generate_clicks.dart
//
// Each click is a decaying cosine burst. Cosine phase puts the peak on
// sample 0, so the files have zero leading silence.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 44100;

void main() {
  _write('assets/clicks/accent.wav', freq: 1800, peak: 0.9, decayMs: 6);
  _write('assets/clicks/normal.wav', freq: 1200, peak: 0.7, decayMs: 5);
}

void _write(
  String path, {
  required double freq,
  required double peak,
  required double decayMs,
}) {
  const lengthMs = 30;
  const frames = _sampleRate * lengthMs ~/ 1000;
  final samples = Int16List(frames);
  for (var i = 0; i < frames; i++) {
    final t = i / _sampleRate;
    final envelope = exp(-t * 1000 / decayMs);
    final tone = cos(2 * pi * freq * t) + 0.3 * cos(2 * pi * 2 * freq * t);
    samples[i] = (peak / 1.3 * envelope * tone * 32767).round();
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(_wav(samples));
}

Uint8List _wav(Int16List samples) {
  final dataBytes = samples.lengthInBytes;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // RIFF
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x57415645) // WAVE
    ..setUint32(12, 0x666d7420) // fmt
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, _sampleRate, Endian.little)
    ..setUint32(28, _sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461) // data
    ..setUint32(40, dataBytes, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...samples.buffer.asUint8List(),
  ]);
}
