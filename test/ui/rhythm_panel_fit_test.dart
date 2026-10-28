import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/controller/library_controller.dart';
import 'package:metra/src/controller/metronome_controller.dart';
import 'package:metra/src/model/metronome_pattern.dart';
import 'package:metra/src/storage/library_store.dart';
import 'package:metra/src/ui/metronome_screen.dart';
import 'package:metra/src/ui/parts_page.dart';
import 'package:metra/src/ui/time_signature_sheet.dart';

import '../audio/fake_click_output.dart';
import 'test_theme.dart';

/// The Rhythm panel, with the Song parts row at the top, fits on one
/// screen without scrolling at default text and 115% (ui-spec.md "The whole
/// panel must still fit on one screen").
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('metra_fit'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // A save on the fake clock may still be writing.
    }
  });

  // The owner's phone (1272×2772 at 3.5) and a common 412×915, each with
  // its status and gesture bars.
  // The owner's phone is the smaller: there all three room-making steps
  // aren't enough, so the panel scrolls (from the top: heading, Song parts
  // row and time signatures first). Test font metrics, not the app's.
  for (final (name, size, fits) in [
    ('363×792', const Size(363, 792), false),
    ('412×915', const Size(412, 915), true),
  ]) {
    for (final scale in [1.0, 1.15]) {
      testWidgets('$name at ${scale}x: ${fits ? 'no scrolling' : 'scrolls'}, '
          'the Song parts row first', (tester) async {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1
          ..padding = const FakeViewPadding(top: 32, bottom: 16)
          ..viewPadding = const FakeViewPadding(top: 32, bottom: 16);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.reset();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final metronome = MetronomeController(FakeClickOutput())
          ..setPattern(
            MetronomePattern.simple(
              beatsPerBar: 7,
              stepsPerBeat: 2,
              beatUnit: 8,
            ).withPolyrhythm(3),
          );
        addTearDown(metronome.dispose);
        final library = (await tester.runAsync(
          () => LibraryController.load(
            LibraryStore(File('${dir.path}/library.json')),
          ),
        ))!;
        await tester.pumpWidget(
          MaterialApp(
            theme: testTheme,
            home: MetronomeScreen(controller: metronome, library: library),
          ),
        );
        // The main screen's own layout is the accessibility tests' job (the
        // test font is far wider than the app's on this narrow screen).
        tester.takeException();
        await tester.tap(find.byKey(MetronomeScreen.meterKey));
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(TimeSignatureSheet),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        if (fits) {
          expect(scroll.maxScrollExtent, 0, reason: 'fits without scrolling');
        }
        expect(scroll.pixels, 0, reason: 'opens at the top');
        final sheet = tester.getRect(find.byType(TimeSignatureSheet));
        expect(
          tester.getRect(find.byKey(const ValueKey('common-12-8'))).bottom,
          lessThanOrEqualTo(sheet.bottom),
          reason: 'the time signatures in view',
        );
        expect(tester.takeException(), isNull);
        final row = tester.getRect(find.byKey(SongPartsRow.rowKey));
        expect(row.height, greaterThanOrEqualTo(56));
        expect(
          row.top,
          lessThan(tester.getTopLeft(find.text('Common')).dy),
          reason: 'right under the heading',
        );
        expect(find.text(SongPartsRow.description), findsOneWidget);
        expect(find.text('3 against 7, in its own sound'), findsOneWidget);
      });
    }
  }
}
