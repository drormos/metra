import 'dart:math';

import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'icons.dart';
import 'play_marker.dart';
import 'setlist_picker.dart';
import 'song_editor.dart';
import 'song_library.dart';
import 'theme.dart';

/// Which dropdown: the Songs or Setlists mode tab, or the set's "4/12 ⌄"
/// (setlist mode).
enum QuickPickKind { songs, sets, set }

/// Opens a quick-pick dropdown (ui-spec.md "Quick-pick dropdowns",
/// `drop-songs` / `drop-sets` / `drop-set` references) just above the
/// bottom bar that [context] belongs to (context row and mode tabs), which
/// stays clear of the dim. The panel is [inset] narrower on each side than
/// the bar (the content width). Tap outside or back closes it; choosing a
/// row loads and closes.
/// Pages it opens are pushed from [context], so back from them returns to
/// the main screen.
Future<void> showQuickPick(
  BuildContext context, {
  required QuickPickKind kind,
  required LibraryController library,
  required MetronomeController metronome,
  double inset = 0,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return Navigator.push(
    context,
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (_, _, _) => _QuickPickLayer(
        anchor: anchor,
        inset: inset,
        child: QuickPick(
          kind: kind,
          library: library,
          metronome: metronome,
          pages: context,
        ),
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The dim (with the bar cut out of it) and the panel above [anchor].
class _QuickPickLayer extends StatelessWidget {
  const _QuickPickLayer({
    required this.anchor,
    required this.inset,
    required this.child,
  });

  final Rect anchor;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    // Above the bar, or above the keyboard while searching.
    final bottom = max(
      size.height - anchor.top + 18,
      MediaQuery.viewInsetsOf(context).bottom + 8,
    );
    final maxHeight = min(470.0, size.height - bottom - padding.top - 16);
    return Stack(
      children: [
        Positioned.fill(
          child: Semantics(
            label: 'Close',
            button: true,
            child: GestureDetector(
              key: QuickPick.outsideKey,
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: CustomPaint(painter: _Dim(colors.dim, anchor)),
            ),
          ),
        ),
        Positioned(
          left: anchor.left + inset,
          right: size.width - anchor.right + inset,
          bottom: bottom,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: max(0, maxHeight)),
            child: Material(
              color: colors.sheet,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.border),
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

/// Dims everything except [hole] (the bottom bar).
class _Dim extends CustomPainter {
  _Dim(this.color, this.hole);

  final Color color;
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(4))),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_Dim old) => old.color != color || old.hole != hole;
}

/// The panel's content: a pinned search (Songs, with more than
/// [searchAbove] songs), the scrolling list, and pinned action rows.
class QuickPick extends StatefulWidget {
  const QuickPick({
    super.key,
    required this.kind,
    required this.library,
    required this.metronome,
    required this.pages,
  });

  final QuickPickKind kind;
  final LibraryController library;
  final MetronomeController metronome;

  /// The main screen's context, for the pages the panel opens.
  final BuildContext pages;

  static const searchAbove = 8;
  static const outsideKey = Key('quick-pick-outside');
  static const songLibraryKey = Key('quick-pick-song-library');
  static const manageSetlistsKey = Key('quick-pick-manage-setlists');
  static const otherSetlistsKey = Key('quick-pick-other-setlists');
  static const setHeaderKey = Key('quick-pick-set-header');
  static const newSongKey = Key('quick-pick-new-song');
  static const newSetlistKey = Key('quick-pick-new-setlist');

  @override
  State<QuickPick> createState() => _QuickPickState();
}

class _QuickPickState extends State<QuickPick> {
  static const _rowHeight = 52.0;

  // "Other setlists ›" swaps the set's songs for the sets list, in place.
  late QuickPickKind _kind = widget.kind;
  final _search = TextEditingController();
  late final _scroll = ScrollController();

  LibraryController get _library => widget.library;

  @override
  void initState() {
    super.initState();
    // The current song scrolled into view, a couple of rows down.
    final index = widget.kind == QuickPickKind.set ? _library.currentIndex : -1;
    if (index > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final position = _scroll.position;
        _scroll.jumpTo(
          min((index - 1.5) * _rowHeight, position.maxScrollExtent),
        );
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Applies a choice and closes, with the song-change haptic.
  void _choose(VoidCallback load) {
    Haptics.medium();
    load();
    Navigator.pop(context);
  }

  /// Closes, then opens a page from the main screen.
  void _open(void Function(BuildContext pages) open) {
    Navigator.pop(context);
    open(widget.pages);
  }

  /// Long-press = edit: closes, then opens the editor or the set's page.
  void _edit(void Function(BuildContext pages) open) {
    Haptics.medium();
    _open(open);
  }

  @override
  Widget build(BuildContext context) => switch (_kind) {
    QuickPickKind.songs => _songsPanel(),
    QuickPickKind.sets => _setsPanel(),
    QuickPickKind.set => _setPanel(),
  };

  Widget _songsPanel() {
    final colors = context.colors;
    final all = _library.songsAZ;
    final query = _search.text.trim().toLowerCase();
    final songs = [
      for (final song in all)
        if (query.isEmpty || song.name.toLowerCase().contains(query)) song,
    ];
    final current = _library.currentSong?.id;
    return _Panel(
      top: all.length > QuickPick.searchAbove
          ? Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: SearchField(
                controller: _search,
                onChanged: (_) => setState(() {}),
              ),
            )
          : null,
      list: all.isEmpty
          ? _empty('No songs yet')
          : ListView(
              shrinkWrap: true,
              controller: _scroll,
              padding: EdgeInsets.zero,
              children: [
                for (final song in songs)
                  _songRow(
                    colors,
                    song,
                    key: ValueKey('quick-song-${song.id}'),
                    current: song.id == current,
                    onTap: () => _choose(
                      () => _library.playSingleSong(song, widget.metronome),
                    ),
                  ),
              ],
            ),
      actions: [
        all.isEmpty
            ? _action(
                key: QuickPick.newSongKey,
                label: 'New song',
                opens: true,
                onTap: () => _open(
                  (pages) => openSongEditor(pages, _library, widget.metronome),
                ),
              )
            : _action(
                key: QuickPick.songLibraryKey,
                label: 'Song library',
                opens: true,
                onTap: () => _open(
                  (pages) => openSongLibrary(pages, _library, widget.metronome),
                ),
              ),
      ],
    );
  }

  Widget _setsPanel() {
    final colors = context.colors;
    final sets = _library.setlistsRecentlyPlayed;
    return _Panel(
      list: sets.isEmpty
          ? _empty('No setlists yet')
          : ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [for (final set in sets) _setRow(colors, set)],
            ),
      actions: [
        sets.isEmpty
            ? _action(
                key: QuickPick.newSetlistKey,
                label: 'New setlist',
                opens: true,
                onTap: () => _open(
                  (pages) => openSetlists(
                    pages,
                    library: _library,
                    metronome: widget.metronome,
                    newSet: true,
                  ),
                ),
              )
            : _action(
                key: QuickPick.manageSetlistsKey,
                label: 'Manage setlists',
                opens: true,
                onTap: () => _open(
                  (pages) => openSetlists(
                    pages,
                    library: _library,
                    metronome: widget.metronome,
                  ),
                ),
              ),
      ],
    );
  }

  Widget _setPanel() {
    final colors = context.colors;
    final setlist = _library.activeSetlist;
    final songs = _library.visibleSongs;
    final current = _library.currentIndex;
    return _Panel(
      // Long-press the set itself = its page, like its rows.
      top: InkWell(
        key: QuickPick.setHeaderKey,
        enableFeedback: false, // Our own haptic, gated by the setting.
        onLongPress: setlist == null
            ? null
            : () => _edit(
                (pages) => openSetlists(
                  pages,
                  library: _library,
                  metronome: widget.metronome,
                  setId: setlist.id,
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  setlist?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.muted),
                ),
              ),
              if (current >= 0)
                Text(
                  '${current + 1} of ${songs.length}',
                  style: TextStyle(fontSize: 13, color: colors.muted),
                ),
            ],
          ),
        ),
      ),
      list: ListView(
        shrinkWrap: true,
        controller: _scroll,
        padding: EdgeInsets.zero,
        children: [
          for (final (i, song) in songs.indexed)
            _songRow(
              colors,
              song,
              key: ValueKey('quick-set-song-$i'),
              current: i == current,
              onTap: () => _choose(
                () => _library.playSong(song, widget.metronome, index: i),
              ),
            ),
        ],
      ),
      actions: [
        _action(
          key: QuickPick.otherSetlistsKey,
          label: 'Other setlists',
          opens: true,
          onTap: () => setState(() => _kind = QuickPickKind.sets),
        ),
      ],
    );
  }

  /// Tap = play; long-press = edit in the song editor.
  Widget _songRow(
    MetraColors colors,
    Song song, {
    required Key key,
    required bool current,
    required VoidCallback onTap,
  }) => _row(
    colors,
    key: key,
    selected: current,
    onTap: onTap,
    onLongPress: () => _edit(
      (pages) => openSongEditor(pages, _library, widget.metronome, song: song),
    ),
    children: [
      SizedBox(width: 16, child: PlayMarker(current: current)),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          song.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        '${song.bpm}',
        style: const TextStyle(
          fontFamily: MetraFonts.condensed,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 28,
        child: Text(
          song.pattern.timeSignature,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
      ),
    ],
  );

  /// Tap = load at song 1; long-press = that set's page.
  Widget _setRow(MetraColors colors, Setlist setlist) => _row(
    colors,
    key: ValueKey('quick-set-${setlist.id}'),
    selected: false,
    onTap: () =>
        _choose(() => _library.loadSetlist(setlist.id, widget.metronome)),
    onLongPress: () => _edit(
      (pages) => openSetlists(
        pages,
        library: _library,
        metronome: widget.metronome,
        setId: setlist.id,
      ),
    ),
    children: [
      SetlistIcon(size: 16, color: colors.muted),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          setlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      const SizedBox(width: 12),
      Text(
        setlist.songIds.length == 1
            ? '1 song'
            : '${setlist.songIds.length} songs',
        style: TextStyle(fontSize: 13, color: colors.muted),
      ),
    ],
  );

  Widget _row(
    MetraColors colors, {
    required Key key,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
    required List<Widget> children,
  }) => Material(
    color: selected ? colors.selectedRow : colors.sheet,
    child: InkWell(
      key: key,
      onTap: onTap,
      onLongPress: onLongPress,
      enableFeedback: false, // Our own haptic, gated by the setting.
      child: Ink(
        height: _rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(children: children),
      ),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: context.colors.muted),
    ),
  );

  /// A pinned action row; [opens] adds the › of a row that opens a page.
  Widget _action({
    required Key key,
    required String label,
    required VoidCallback onTap,
    Widget? icon,
    bool opens = false,
  }) {
    final colors = context.colors;
    return InkWell(
      key: key,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              if (icon != null) ...[icon, const SizedBox(width: 12)],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (opens)
                Icon(Icons.chevron_right, size: 18, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned [top], the scrolling [list], then the pinned [actions] under a
/// 2px line, with 1px lines between them, so they never read as rows.
class _Panel extends StatelessWidget {
  const _Panel({this.top, required this.list, required this.actions});

  final Widget? top;
  final Widget list;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (top case final top?) ...[
          top,
          Divider(height: 1, thickness: 1, color: colors.divider),
        ],
        Flexible(child: list),
        Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border, width: 2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, action) in actions.indexed) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: colors.divider),
                action,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
