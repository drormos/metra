import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'theme.dart';

/// The media card's cover, style "Tempo ruler" (ui-spec.md "Media
/// controls", media-cover.reference.html): the BPM over a slice of the
/// tempo ruler with its red needle, on black. [size] px square.
Future<Uint8List> renderMediaCover(int bpm, {int size = 512}) async {
  final s = size.toDouble();
  // The reference draws it 200 px wide; everything scales from there.
  final u = s / 200;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, s, s),
      Paint()..color = CoverColors.background,
    );

  final number = TextPainter(
    text: TextSpan(
      text: '$bpm',
      style: TextStyle(
        fontFamily: MetraFonts.condensed,
        fontWeight: FontWeight.w700,
        fontSize: 96 * u, // ~48% of the height
        height: 0.85,
        color: CoverColors.bpm,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // Number and ruler stacked, centred: the number sits a little above
  // the middle.
  const rulerHeight = 20.0, gap = 16.0;
  final top = (s - number.height - (gap + rulerHeight) * u) / 2;
  number.paint(canvas, Offset((s - number.width) / 2, top));

  // The ruler slice: one tick per bpm, longer every fifth, the needle on
  // the current tempo. No numbers.
  final rulerTop = top + number.height + gap * u;
  final paint = Paint();
  paint.color = CoverColors.rule;
  canvas.drawRect(Rect.fromLTWH(0, rulerTop, s, 1.2 * u), paint);
  const pitch = 9.0; // px per bpm at 200 px
  final centre = s / 2;
  final reach = (centre / (pitch * u)).ceil();
  for (var b = bpm - reach; b <= bpm + reach; b++) {
    final major = b % 5 == 0;
    paint.color = major ? CoverColors.majorTick : CoverColors.minorTick;
    final x = centre + (b - bpm) * pitch * u;
    canvas.drawRect(
      Rect.fromLTWH(x - 0.8 * u, rulerTop, 1.6 * u, (major ? 18 : 10) * u),
      paint,
    );
  }
  paint.color = CoverColors.needle;
  canvas.drawRect(
    Rect.fromLTWH(centre - 1.6 * u, rulerTop, 3.2 * u, rulerHeight * u),
    paint,
  );

  final image = await recorder.endRecording().toImage(size, size);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

/// The cover for [bpm] as a PNG file in [dir], written once per tempo (a
/// new file name per tempo, so the system doesn't show a cached one).
Future<Uri> mediaCoverFile(Directory dir, int bpm) async {
  final file = File('${dir.path}/media_cover_$bpm.png');
  if (!await file.exists()) {
    // Through a temp file: a crash mid-write never leaves a broken cover.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(await renderMediaCover(bpm), flush: true);
    await temp.rename(file.path);
  }
  return file.uri;
}
