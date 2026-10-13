import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Click samples must start sounding on their first sample (CLAUDE.md
/// SAMPLE RULES), otherwise every click lands late by the silence length.
void main() {
  for (final name in ['accent', 'normal']) {
    test('$name.wav has zero leading silence', () {
      final bytes = File('assets/clicks/$name.wav').readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
      expect(data.getUint16(34, Endian.little), 16, reason: '16-bit PCM');

      final first = data.getInt16(44, Endian.little).abs();
      // At least 25% of full scale on the very first sample.
      expect(first, greaterThan(32767 ~/ 4));
    });
  }
}
