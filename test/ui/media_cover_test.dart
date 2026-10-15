import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/ui/media_cover.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('SairaExtraCondensed')
      ..addFont(rootBundle.load('assets/fonts/SairaExtraCondensed-Bold.ttf'));
    await loader.load();
  });

  test('renders a square PNG', () async {
    final png = await renderMediaCover(120);
    expect(png.sublist(1, 4), 'PNG'.codeUnits);
    // Width and height from the IHDR chunk: 512 × 512.
    final header = ByteData.sublistView(png, 16, 24);
    expect(header.getUint32(0), 512);
    expect(header.getUint32(4), 512);
    final out = Platform.environment['METRA_COVER_OUT'];
    if (out != null) File(out).writeAsBytesSync(png);
  });

  test('one file per tempo, written once', () async {
    final dir = Directory.systemTemp.createTempSync('metra_cover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final uri = await mediaCoverFile(dir, 96);
    expect(uri.pathSegments.last, 'media_cover_96.png');
    final written = File.fromUri(uri).lastModifiedSync();
    await mediaCoverFile(dir, 96);
    expect(File.fromUri(uri).lastModifiedSync(), written);
  });
}
