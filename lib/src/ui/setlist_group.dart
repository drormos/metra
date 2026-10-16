import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'fit_text.dart';
import 'haptics.dart';
import 'icons.dart';
import 'quick_pick.dart';
import 'setlist_picker.dart';
import 'subdivision_icon.dart';
import 'tabular_text.dart';
import 'theme.dart';

/// The source bar at the bottom of the main screen (ui-spec.md "Source
/// bar"): one 68px row, no frame, the same height and place in every mode,
/// so no control ever moves. Setlist mode: previous | the set's "4/12 ⌄" |
/// next. Free play and Single song: "Setlists ⌄" | "Songs ⌄".
class SetlistGroup extends StatelessWidget {
  const SetlistGroup({
    super.key,
    required this.library,
    required this.metronome,
  });

  final LibraryController library;
  final MetronomeController metronome;

  static const height = 68.0;

  /// The center "4/12 ⌄" button: the set dropdown.
  static const headerKey = Key('setlist-header');
  static const previousKey = Key('previous-song');
  static const nextKey = Key('next-song');
  static const setlistsKey = Key('free-play-setlists');
  static const songsKey = Key('free-play-songs');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final setlist = library.activeSetlist;
    // Each ⌄ opens its dropdown just above this bar.
    void pick(QuickPickKind kind) => showQuickPick(
      context,
      kind: kind,
      library: library,
      metronome: metronome,
    );
    return SizedBox(
      height: height,
      child: setlist == null
          ? _pickRow(colors, pick)
          : _stepRow(context, colors, setlist, pick),
    );
  }

  /// Two equal outlined buttons, the same in Free play and Single song.
  Widget _pickRow(MetraColors colors, void Function(QuickPickKind) pick) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: _pickButton(
          colors,
          key: setlistsKey,
          icon: const SetlistIcon(),
          label: 'Setlists',
          onPressed: () => pick(QuickPickKind.sets),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _pickButton(
          colors,
          key: songsKey,
          icon: const SubdivisionIcon(1, size: 18),
          label: 'Songs',
          onPressed: () => pick(QuickPickKind.songs),
        ),
      ),
    ],
  );

  Widget _pickButton(
    MetraColors colors, {
    required Key key,
    required Widget icon,
    required String label,
    required VoidCallback onPressed,
  }) => OutlinedButton(
    key: key,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14),
    ),
    onPressed: onPressed,
    child: Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        Icon(Icons.expand_more, size: 18, color: colors.muted),
      ],
    ),
  );

  /// Previous | the set's position | next. Previous and next show the
  /// neighbouring song (no words), filled, disabled at the ends.
  Widget _stepRow(
    BuildContext context,
    MetraColors colors,
    Setlist setlist,
    void Function(QuickPickKind) pick,
  ) {
    final songs = library.visibleSongs;
    final index = library.currentIndex;
    // With no current song in the set, "next" is its first song.
    final previous = library.hasPrevious ? songs[index - 1] : null;
    final next = library.hasNext ? songs[index + 1] : null;
    final position = '${index < 0 ? '–' : index + 1}/${songs.length}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _stepButton(
            key: previousKey,
            colors: colors,
            song: previous,
            forward: false,
            onPressed: () {
              Haptics.medium();
              library.previousSong(metronome);
            },
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 76,
          child: OutlinedButton(
            key: headerKey,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              // Our own haptic on long-press, gated by "Vibrate on touch".
              enableFeedback: false,
            ),
            onPressed: () => pick(QuickPickKind.set),
            // Long-press = the set's page; back returns here.
            onLongPress: () {
              Haptics.medium();
              openSetlists(
                context,
                library: library,
                metronome: metronome,
                setId: setlist.id,
              );
            },
            // The label goes inside, so the button keeps its actions.
            child: Semantics(
              label: '${setlist.name}, song $position',
              excludeSemantics: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SetlistIcon(),
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabularText(
                          position,
                          style: const TextStyle(
                            fontFamily: MetraFonts.condensed,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.expand_more, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _stepButton(
            key: nextKey,
            colors: colors,
            song: next,
            forward: true,
            onPressed: () {
              Haptics.medium();
              library.nextSong(metronome);
            },
          ),
        ),
      ],
    );
  }

  /// The name on line 1, full width (18px, shrinking to 13px); line 2
  /// small and muted with a small chevron: "‹ 98 bpm" / "168 bpm ›".
  Widget _stepButton({
    required Key key,
    required MetraColors colors,
    required Song? song,
    required bool forward,
    required VoidCallback onPressed,
  }) {
    // Bolder and larger than the bpm text: it says which way.
    final chevron = CustomPaint(
      size: const Size(10, 16),
      painter: _Chevron(color: colors.text, forward: forward),
    );
    final bpm = Flexible(
      child: Text(
        '${song?.bpm} bpm',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: colors.muted),
      ),
    );
    return FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: song == null ? null : onPressed,
      // The label goes inside, so the button keeps its actions.
      child: Semantics(
        label: song == null
            ? (forward ? 'No next song' : 'No previous song')
            : '${forward ? 'Next' : 'Previous'} song: ${song.name}',
        excludeSemantics: true,
        child: song == null
            ? const SizedBox.expand()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                // Full width: the name uses all of it, aligned by textAlign.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A fixed line box for 18px, the name at its bottom: a
                  // shrunk name never moves the bpm line.
                  SizedBox(
                    height: 22,
                    child: Align(
                      alignment: forward
                          ? Alignment.bottomRight
                          : Alignment.bottomLeft,
                      child: FitText(
                        song.name,
                        minFontSize: 13,
                        textAlign: forward ? TextAlign.right : TextAlign.left,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: forward
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: forward
                        ? [bpm, const SizedBox(width: 4), chevron]
                        : [chevron, const SizedBox(width: 4), bpm],
                  ),
                ],
              ),
      ),
    );
  }
}

/// The small Previous / Next chevron on the bpm line: 16px tall, 2.6px
/// stroke.
class _Chevron extends CustomPainter {
  _Chevron({required this.color, required this.forward});

  final Color color;
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    final (tip, back) = forward ? (8.0, 2.0) : (2.0, 8.0);
    canvas.drawPath(
      Path()
        ..moveTo(back, 1)
        ..lineTo(tip, 8)
        ..lineTo(back, 15),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Chevron old) =>
      old.color != color || old.forward != forward;
}
