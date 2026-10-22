import 'package:flutter/services.dart';

import '../controller/library_controller.dart';

/// One version's entry in `assets/whats_new.md`.
typedef Release = ({String version, String heading, List<String> lines});

/// What's new (ui-spec.md "First launch and updates"): every version from
/// `assets/whats_new.md`, newest first. After an update the ☰ button
/// shows a dot (cleared by opening the Menu) and the Menu a block for the
/// newest version (until "Got it"); a fresh install counts as seen.
abstract final class WhatsNew {
  static const asset = 'assets/whats_new.md';

  /// Newest first; empty until [load] (and in tests unless set).
  static List<Release> releases = const [];

  static Release? get latest => releases.firstOrNull;

  static Future<void> load([AssetBundle? bundle]) async {
    try {
      releases = parse(await (bundle ?? rootBundle).loadString(asset));
    } catch (_) {
      releases = const []; // No notes: no dot, no block.
    }
  }

  /// "## 1.4.0 · Oct 2026" headings, each followed by "- " lines.
  static List<Release> parse(String text) {
    final releases = <Release>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        final heading = line.substring(3).trim();
        releases.add((
          version: heading.split('·').first.trim(),
          heading: heading,
          lines: <String>[],
        ));
      } else if (line.startsWith('- ') && releases.isNotEmpty) {
        releases.last.lines.add(line.substring(2).trim());
      }
    }
    return releases;
  }

  static String _dot(String version) => 'whats-new-dot:$version';
  static String _block(String version) => 'whats-new:$version';

  /// The ☰ dot: an update not yet looked at.
  static bool showDot(LibraryController? library) {
    final latest = WhatsNew.latest;
    return library != null &&
        latest != null &&
        !library.tipSeen(_dot(latest.version));
  }

  /// The Menu's block: an update not yet dismissed with "Got it".
  static bool showBlock(LibraryController? library) {
    final latest = WhatsNew.latest;
    return library != null &&
        latest != null &&
        !library.tipSeen(_block(latest.version));
  }

  /// Opening the Menu clears the dot.
  static void menuOpened(LibraryController? library) {
    final latest = WhatsNew.latest;
    if (library != null && latest != null) {
      library.markTipSeen(_dot(latest.version));
    }
  }

  /// "Got it", or a fresh install: no block, no dot until the next update.
  static void markSeen(LibraryController library) {
    final latest = WhatsNew.latest;
    if (latest == null) return;
    library
      ..markTipSeen(_dot(latest.version))
      ..markTipSeen(_block(latest.version));
  }
}
