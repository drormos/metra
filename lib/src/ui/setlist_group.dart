import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'fit_text.dart';
import 'haptics.dart';
import 'icons.dart';
import 'quick_pick.dart';
import 'save_as_new_dialog.dart';
import 'subdivision_icon.dart';
import 'tabular_text.dart';
import 'theme.dart';

/// The bottom of the main screen (ui-spec.md "Mode tabs and context row"):
/// the context row (64px) over the mode tabs (58px, edge to edge), the
/// same height in every mode, so Start/Tap never move. Tabs switch at once
/// and never open a list; lists open only from the context row's center
/// button. Context row: setlist mode previous | the set's "4/12 ⌄" | next;
/// Single song previous | "Songs ⌄" | next through the library A–Z; Free
/// play a quiet "+ New song from this"; an empty Songs / Setlists tab
/// "No songs yet" / "No setlists yet" with a "+ New" button. Placed
/// outside the screen's side padding; the context row adds its own.
class SetlistGroup extends StatelessWidget {
  const SetlistGroup({
    super.key,
    required this.library,
    required this.metronome,
  });

  final LibraryController library;
  final MetronomeController metronome;

  static const rowHeight = 64.0;
  static const tabsHeight = 58.0;

  /// The context row's side padding: the main screen's content width.
  static const sidePadding = 24.0;

  /// The center "4/12 ⌄" button: the set dropdown.
  static const headerKey = Key('setlist-header');

  /// The center "Songs ⌄" button (Single song): the Songs list.
  static const songsKey = Key('songs-list');
  static const previousKey = Key('previous-song');
  static const nextKey = Key('next-song');
  static const newSongKey = Key('new-song');
  static const firstSongKey = Key('first-song');
  static const firstSetlistKey = Key('first-setlist');
  static const emptySetKey = Key('empty-set-add-songs');
  static const songsTabKey = Key('tab-songs');
  static const freePlayTabKey = Key('tab-free-play');
  static const setlistsTabKey = Key('tab-setlists');

  @override
  Widget build(BuildContext context) {
    final setlist = library.activeSetlist;
    final tab = library.tab;
    // Each list opens just above the context row; the row and the tabs
    // stay clear of the dim.
    void pick(
      QuickPickKind kind, [
      QuickPickStart start = QuickPickStart.none,
    ]) => showQuickPick(
      context,
      kind: kind,
      start: start,
      library: library,
      metronome: metronome,
      inset: sidePadding,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: sidePadding),
          child: SizedBox(
            height: rowHeight,
            child: switch (tab) {
              ModeTab.setlists
                  when setlist != null && library.visibleSongs.isEmpty =>
                _emptyRow(
                  context,
                  key: emptySetKey,
                  message: 'No songs in this set',
                  action: 'Add songs',
                  onPressed: () =>
                      pick(QuickPickKind.set, QuickPickStart.addSongs),
                ),
              ModeTab.setlists when setlist != null => _setRow(
                context,
                setlist,
                pick,
              ),
              ModeTab.setlists => _emptyRow(
                context,
                key: firstSetlistKey,
                message: 'No setlists yet',
                action: 'New setlist',
                onPressed: () =>
                    pick(QuickPickKind.sets, QuickPickStart.newSetlist),
              ),
              ModeTab.songs when library.singleSong => _songRow(context, pick),
              ModeTab.songs => _emptyRow(
                context,
                key: firstSongKey,
                message: 'No songs yet',
                action: 'New song',
                onPressed: () =>
                    pick(QuickPickKind.songs, QuickPickStart.newSong),
              ),
              ModeTab.freePlay => _freePlayRow(context),
            },
          ),
        ),
        const SizedBox(height: 16),
        _tabs(context, tab),
      ],
    );
  }

  Widget _tabs(BuildContext context, ModeTab current) {
    final colors = context.colors;
    // Tap = you're there; the tab you're on does nothing.
    void go(ModeTab tab, VoidCallback open) {
      if (tab == current) return;
      Haptics.medium(); // the song changed or detached
      open();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: SizedBox(
          height: tabsHeight,
          // Read as tabs, the current one "selected".
          child: Semantics(
            role: SemanticsRole.tabBar,
            container: true,
            explicitChildNodes: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tab(
                  colors,
                  key: songsTabKey,
                  icon: const SubdivisionIcon(1, size: 20),
                  label: 'Songs',
                  active: current == ModeTab.songs,
                  onTap: () =>
                      go(ModeTab.songs, () => library.openSongsTab(metronome)),
                ),
                _tab(
                  colors,
                  key: freePlayTabKey,
                  icon: const MetronomeIcon(size: 18),
                  label: 'Free play',
                  active: current == ModeTab.freePlay,
                  onTap: () => go(ModeTab.freePlay, library.detachSong),
                ),
                _tab(
                  colors,
                  key: setlistsTabKey,
                  icon: const SetlistIcon(),
                  label: 'Setlists',
                  active: current == ModeTab.setlists,
                  onTap: () => go(
                    ModeTab.setlists,
                    () => library.openSetlistsTab(metronome),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// An empty Songs / Setlists tab: what's missing, and the way to add it.
  Widget _emptyRow(
    BuildContext context, {
    required Key key,
    required String message,
    required String action,
    required VoidCallback onPressed,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Flexible(
        child: Text(
          message,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, color: context.colors.muted),
        ),
      ),
      const SizedBox(width: 8),
      TextButton.icon(
        key: key,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        onPressed: onPressed,
        icon: const Icon(Icons.add, size: 14),
        label: Text(
          action,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );

  /// An icon over a 12px label; the current mode white with a 2px red
  /// line on its top edge (over the bar's 1px line), the others muted.
  Widget _tab(
    MetraColors colors, {
    required Key key,
    required Widget icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final color = active ? colors.text : colors.muted;
    return Expanded(
      // The bar's 1px line is drawn over the tabs' top edge, so the active
      // tab's red line covers it.
      child: Semantics(
        role: SemanticsRole.tab,
        selected: active,
        child: InkWell(
          key: key,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: active ? colors.accent : colors.accent.withAlpha(0),
                  width: 2,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(color: color),
                  child: SizedBox.square(
                    dimension: 20,
                    child: Center(child: icon),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Free play: a quiet centered text button that saves what's sounding
  /// as a new song.
  Widget _freePlayRow(BuildContext context) => Center(
    child: TextButton.icon(
      key: newSongKey,
      style: TextButton.styleFrom(
        foregroundColor: context.colors.muted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: () => showSaveAsNewSong(context, library, metronome),
      icon: const Icon(Icons.add, size: 14),
      label: const Text(
        'New song from this',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
  );

  void _previous() {
    Haptics.medium();
    library.previousSong(metronome);
  }

  void _next() {
    Haptics.medium();
    library.nextSong(metronome);
  }

  /// Single song: previous | "Songs ⌄" | next through the library A–Z,
  /// the same shape as in a set.
  Widget _songRow(BuildContext context, void Function(QuickPickKind) pick) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _stepButton(
            key: previousKey,
            colors: colors,
            song: library.songBefore,
            forward: false,
            onPressed: _previous,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 76,
          child: OutlinedButton(
            key: songsKey,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              // Our own haptic on long-press, gated by "Vibrate on touch".
              enableFeedback: false,
            ),
            onPressed: () => pick(QuickPickKind.songs),
            child: Semantics(
              label: 'Songs, opens song list',
              excludeSemantics: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SubdivisionIcon(1, size: 18),
                  const SizedBox(height: 3),
                  FittedBox(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text(
                          'Songs',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 3),
                        Icon(Icons.expand_more, size: 16),
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
            song: library.songAfter,
            forward: true,
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  /// Previous | the set's position | next. Previous and next show the
  /// neighbouring song (no words), filled, disabled at the ends.
  Widget _setRow(
    BuildContext context,
    Setlist setlist,
    void Function(QuickPickKind) pick,
  ) {
    final colors = context.colors;
    final index = library.currentIndex;
    final position =
        '${index < 0 ? '–' : index + 1}/${library.visibleSongs.length}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _stepButton(
            key: previousKey,
            colors: colors,
            song: library.songBefore,
            forward: false,
            onPressed: _previous,
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
            // The label goes inside, so the button keeps its actions.
            child: Semantics(
              label: index < 0
                  ? '${setlist.name}, opens song list'
                  : '${setlist.name}, song ${index + 1} of '
                        '${library.visibleSongs.length}, opens song list',
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
            song: library.songAfter,
            forward: true,
            onPressed: _next,
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
    final chevron = CustomPaint(
      size: const Size.square(15),
      painter: _Chevron(color: colors.muted, forward: forward),
    );
    // One grey bold unit with the chevron: "‹ 98 BPM" / "168 BPM ›".
    final bpm = Flexible(
      child: Text(
        '${song?.bpm} BPM',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 13 * 0.02,
          color: colors.muted,
        ),
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
            : '${forward ? 'Next' : 'Previous'} song: ${song.name}, '
                  '${song.bpm} BPM',
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
                        ? [bpm, const SizedBox(width: 5), chevron]
                        : [chevron, const SizedBox(width: 5), bpm],
                  ),
                ],
              ),
      ),
    );
  }
}

/// The Previous / Next chevron on the tempo line: 15px, 2.8 stroke (in a
/// 16-unit box, as in main-screen.reference.html).
class _Chevron extends CustomPainter {
  _Chevron({required this.color, required this.forward});

  final Color color;
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 16);
    final (tip, back) = forward ? (11.0, 6.0) : (5.0, 10.0);
    canvas.drawPath(
      Path()
        ..moveTo(back, 3)
        ..lineTo(tip, 8)
        ..lineTo(back, 13),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_Chevron old) =>
      old.color != color || old.forward != forward;
}
