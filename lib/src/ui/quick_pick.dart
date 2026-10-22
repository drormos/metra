import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'icons.dart';
import 'metronome_screen.dart';
import 'play_marker.dart';
import 'setlist_picker.dart';
import 'song_editor.dart';
import 'song_library.dart';
import 'swipe_row.dart';
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
        // Text grows with the system font only as far as on the main
        // screen it opens over, so the rows and the header keep their shape.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: MetronomeScreen.maxTextScale,
          child: QuickPick(
            kind: kind,
            library: library,
            metronome: metronome,
            pages: context,
          ),
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
  static const setHeaderKey = Key('quick-pick-set-header');
  static const changeSetKey = Key('quick-pick-change-set');
  static const pickBackKey = Key('quick-pick-picker-back');
  static const pickAddKey = Key('quick-pick-picker-add');
  static const pickSearchKey = Key('quick-pick-picker-search');

  /// How long rows just added from the picker show "Added".
  static const addedFor = Duration(seconds: 2);
  static const setSearchKey = Key('quick-pick-set-search');
  static const backKey = Key('quick-pick-back');
  static const addSongsKey = Key('quick-pick-add-songs');
  static const undoKey = Key('quick-pick-undo');
  static const renameFieldKey = Key('quick-pick-rename');
  static const renameDoneKey = Key('quick-pick-rename-done');

  /// How long the Undo bar stays.
  static const undoFor = Duration(seconds: 6);
  static const newSongKey = Key('quick-pick-new-song');
  static const newSetlistKey = Key('quick-pick-new-setlist');

  @override
  State<QuickPick> createState() => _QuickPickState();
}

class _QuickPickState extends State<QuickPick>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 52.0;

  // The set panel's rows (the reference's denser 48px).
  static const _entryHeight = 48.0;

  // "Change set" swaps the set's songs for the sets view, in place.
  late QuickPickKind _kind = widget.kind;
  final _search = TextEditingController();
  final _setSearch = TextEditingController();
  late final _scroll = ScrollController();

  // The Undo bar: the last removal or deletion, for [QuickPick.undoFor].
  ({String message, VoidCallback undo})? _undo;
  Timer? _undoTimer;

  // Bumped by every removal and undo, so a swiped row's key never comes
  // back while the list rebuilds.
  int _generation = 0;

  // The row being renamed in place (a set or song id, or [_newSongId]),
  // and what Done does with it.
  String? _renaming;
  _Rename? _renameKind;
  static const _newSongId = '\u0000new-song';
  final _rename = TextEditingController();

  // Reordering a set's songs: the list (to end its drag at release), the
  // lifted row (where it was let go), the row's start, and the settle.
  final _reorderKey = GlobalKey<ReorderableListState>();
  final _proxyKey = GlobalKey();
  int? _dragFrom;
  bool _reordering = false;

  // The song picker (ui-spec.md "Song picker"): the set it adds to, the
  // ticked songs in tick order, its search and list, and where Back goes.
  String? _pickFor;
  bool _pickReturnsToSets = false;
  final _picked = <String>[];
  final _pickSearch = TextEditingController();
  final _pickScroll = ScrollController();

  // Rows just added from the picker, marked "Added" for a moment.
  ({int from, int count})? _justAdded;
  Timer? _addedTimer;
  ({int index, double fromTop})? _settle;
  final _catchUp = CatchUp();

  // The one-time swipe hint: [_hintRow] slides out and back.
  int? _hintRow;
  late final _hint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

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
          min((index - 1.5) * _entryHeight, position.maxScrollExtent),
        );
      });
    }
    _maybeHint();
  }

  /// The first time ever the set panel (or, with its own flag, the Songs
  /// list) opens on 2+ songs, a row that isn't playing slides out to show
  /// what a swipe does, then springs back. No haptic.
  void _maybeHint() {
    final List<Song> songs;
    final int current;
    final VoidCallback seen;
    switch (widget.kind) {
      case QuickPickKind.set when !_library.swipeHintSeen:
        songs = _library.visibleSongs;
        current = _library.currentIndex;
        seen = _library.markSwipeHintSeen;
      case QuickPickKind.songs when !_library.songsHintSeen:
        songs = _library.songsAZ;
        current = songs.indexWhere((s) => s.id == _library.currentSong?.id);
        seen = _library.markSongsHintSeen;
      default:
        return;
    }
    if (songs.length < 2) return;
    _hintRow = current == 0 ? 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      seen();
      _hint.forward().whenComplete(() {
        if (mounted) setState(() => _hintRow = null);
      });
    });
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _addedTimer?.cancel();
    _pickSearch.dispose();
    _pickScroll.dispose();
    _hint.dispose();
    _rename.dispose();
    _search.dispose();
    _setSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shows the Undo bar, replacing any earlier one.
  void _showUndo(String message, VoidCallback undo) {
    _undoTimer?.cancel();
    setState(() => _undo = (message: message, undo: undo));
    _undoTimer = Timer(QuickPick.undoFor, () {
      if (mounted) setState(() => _undo = null);
    });
  }

  void _runUndo() {
    final undo = _undo;
    if (undo == null) return;
    _undoTimer?.cancel();
    undo.undo();
    setState(() {
      _undo = null;
      _generation++;
    });
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

  // Back from the sets view returns to the set's songs; Back while
  // renaming cancels the rename. Otherwise Back closes the panel.
  bool get _backStaysOpen =>
      _renaming != null ||
      _pickFor != null ||
      (_kind == QuickPickKind.sets && _library.activeSetlist != null);

  void _back() => setState(() {
    if (_renaming != null) {
      _renaming = null;
      _renameKind = null;
    } else if (_pickFor != null) {
      _pickFor = null; // nothing added
    } else {
      _kind = QuickPickKind.set;
    }
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_backStaysOpen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    // Edits here (reorder, remove, rename) change the library under it.
    // Every touch hurries running row animations along (never wait).
    child: CatchUpScope(
      catchUp: _catchUp,
      child: ListenableBuilder(
        listenable: _library,
        builder: (context, _) => switch (_kind) {
          _ when _pickFor != null => _pickerPanel(),
          QuickPickKind.songs => _songsPanel(),
          QuickPickKind.sets => _setsPanel(),
          QuickPickKind.set => _setPanel(),
        },
      ),
    ),
  );

  /// The Songs list, A–Z: tap = load (Single song); long-press renames in
  /// place; swipe deletes after a dialog (not the loaded song), with
  /// Undo; "+ New song ›" names a song made from the click as it is now.
  Widget _songsPanel() {
    final colors = context.colors;
    final all = _library.songsAZ;
    final query = _search.text.trim().toLowerCase();
    final songs = [
      for (final song in all)
        if (query.isEmpty ||
            song.id == _renaming ||
            song.name.toLowerCase().contains(query))
          song,
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
      list: all.isEmpty && _renaming == null
          ? _empty('No songs yet')
          : ListView(
              shrinkWrap: true,
              controller: _scroll,
              padding: EdgeInsets.zero,
              children: [
                if (_renaming == _newSongId)
                  _renameRow(colors, leading: const PlayMarker(current: false)),
                for (final (i, song) in songs.indexed)
                  song.id == _renaming
                      ? _renameRow(
                          colors,
                          leading: PlayMarker(current: song.id == current),
                        )
                      : ExitShift(
                          index: i,
                          child: SwipeRow(
                            key: ValueKey('song-${song.id}-$_generation'),
                            index: i,
                            enabled: _renaming == null,
                            onHold: () =>
                                _startRename(song.id, song.name, _Rename.song),
                            label: 'Delete song',
                            actionLabel: 'Delete song',
                            ask: () => confirmDelete(
                              context,
                              title: 'Delete ${song.name}?',
                              body: switch (_library.setlistsUsing(song.id)) {
                                final sets when sets.isEmpty => null,
                                final sets =>
                                  'It will also be removed from '
                                      '${SongLibrary.whereUsed(sets)}.',
                              },
                            ),
                            onSwiped: () => _deleteSong(song),
                            hint: i == _hintRow && query.isEmpty ? _hint : null,
                            child: _songRow(
                              colors,
                              song,
                              key: ValueKey('quick-song-${song.id}'),
                              current: song.id == current,
                              onTap: () => _choose(
                                () => _library.playSingleSong(
                                  song,
                                  widget.metronome,
                                ),
                              ),
                            ),
                          ),
                        ),
              ],
            ),
      bar: _undoBar(colors),
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
                key: QuickPick.newSongKey,
                label: '+ New song',
                opens: true,
                onTap: _newSong,
              ),
      ],
    );
  }

  bool _isJustAdded(int i) {
    final added = _justAdded;
    return added != null && i >= added.from && i < added.from + added.count;
  }

  /// The panel turns into the song picker for set [id], in place.
  void _openPicker(String id, {bool returnsToSets = false}) => setState(() {
    _pickFor = id;
    _pickReturnsToSets = returnsToSets;
    _picked.clear();
    _pickSearch.clear();
  });

  /// The ticked songs go to the end of the set in tick order (position and
  /// current song unchanged); back to the set's songs, scrolled to the end,
  /// the new rows marked "Added" — or, for a new set, back to the sets.
  void _addPicked() {
    final set = _library.setlists.where((l) => l.id == _pickFor).firstOrNull;
    if (set == null || _picked.isEmpty) return;
    final from = set.id == _library.activeSetlist?.id
        ? _library.visibleSongs.length
        : set.songIds.length;
    final count = _picked.length;
    _library.updateSetlist(set.copyWith(songIds: [...set.songIds, ..._picked]));
    final toSets = _pickReturnsToSets;
    setState(() {
      _pickFor = null;
      _generation++;
      if (!toSets) _justAdded = (from: from, count: count);
    });
    if (toSets) return;
    _addedTimer?.cancel();
    _addedTimer = Timer(QuickPick.addedFor, () {
      if (mounted) setState(() => _justAdded = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// "‹ Back" and "Add to Friday set", search above 8 songs, every song A–Z with
  /// a checkbox (songs already in the set greyed), and the add button.
  Widget _pickerPanel() {
    final colors = context.colors;
    final set = _library.setlists.where((l) => l.id == _pickFor).firstOrNull;
    if (set == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _pickFor = null);
      });
      return const SizedBox.shrink();
    }
    final all = _library.songsAZ;
    final query = _pickSearch.text.trim().toLowerCase();
    final inSet = set.songIds.toSet();
    final count = _picked.length;
    return _Panel(
      top: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                TextButton(
                  key: QuickPick.pickBackKey,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.muted,
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onPressed: _back,
                  child: const Text('‹ Back', style: TextStyle(fontSize: 14)),
                ),
                const Spacer(),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'Add to ${set.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: colors.muted),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (all.length > QuickPick.searchAbove)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: SearchField(
                key: QuickPick.pickSearchKey,
                controller: _pickSearch,
                onChanged: (_) => setState(() {}),
              ),
            ),
        ],
      ),
      list: ListView(
        shrinkWrap: true,
        controller: _pickScroll,
        padding: EdgeInsets.zero,
        children: [
          for (final song in all)
            if (query.isEmpty || song.name.toLowerCase().contains(query))
              _pickRow(colors, song, inSet: inSet.contains(song.id)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              key: QuickPick.pickAddKey,
              onPressed: count == 0 ? null : _addPicked,
              child: Text(
                count == 0
                    ? 'Choose songs to add'
                    : 'Add $count ${count == 1 ? 'song' : 'songs'} '
                          'to ${set.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// One song to pick, 52px: tap anywhere ticks or unticks (light
  /// haptic). Already in the set: greyed, "In this set", not tappable.
  Widget _pickRow(MetraColors colors, Song song, {required bool inSet}) {
    final ticked = _picked.contains(song.id);
    final faint = inSet ? colors.slot : null;
    return Material(
      color: ticked ? colors.surface : colors.sheet,
      child: InkWell(
        key: ValueKey('pick-${song.id}'),
        enableFeedback: false,
        onTap: inSet
            ? null
            : () {
                Haptics.tick();
                setState(
                  () => ticked ? _picked.remove(song.id) : _picked.add(song.id),
                );
              },
        child: Container(
          height: _rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: ticked
                      ? colors.text
                      : inSet
                      ? colors.surface
                      : null,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: ticked
                        ? colors.text
                        : inSet
                        ? colors.lifted
                        : colors.slot,
                    width: 2,
                  ),
                ),
                child: ticked
                    ? Icon(Icons.check, size: 14, color: colors.background)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: faint),
                    ),
                    if (inSet)
                      Text(
                        'In this set',
                        style: TextStyle(fontSize: 12, color: faint),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 34,
                child: Text(
                  '${song.bpm}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: inSet ? colors.beatResting : colors.muted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 30,
                child: Text(
                  song.pattern.timeSignature,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: inSet ? colors.beatResting : colors.slot,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The sets view: "‹ Back" (with a set loaded) and, with more than
  /// [QuickPick.searchAbove] sets, "Search setlists" pinned under it; the
  /// sets most recently played first (the loaded one marked), tap = load
  /// at song 1; long-press renames in place; swipe deletes (not the loaded
  /// set); "+ New setlist ›" pinned.
  Widget _setsPanel() {
    final colors = context.colors;
    final all = _library.setlistsRecentlyPlayed;
    final query = _setSearch.text.trim().toLowerCase();
    final sets = [
      for (final set in all)
        if (query.isEmpty ||
            set.id == _renaming ||
            set.name.toLowerCase().contains(query))
          set,
    ];
    final loaded = _library.activeSetlist?.id;
    final back = loaded == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: QuickPick.backKey,
              style: TextButton.styleFrom(
                foregroundColor: colors.muted,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _back,
              child: const Text('‹ Back', style: TextStyle(fontSize: 14)),
            ),
          );
    final search = all.length > QuickPick.searchAbove
        ? Padding(
            padding: EdgeInsets.fromLTRB(10, back == null ? 10 : 0, 10, 6),
            child: SearchField(
              key: QuickPick.setSearchKey,
              controller: _setSearch,
              hint: 'Search setlists',
              onChanged: (_) => setState(() {}),
            ),
          )
        : null;
    return _Panel(
      top: back == null && search == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [?back, ?search],
            ),
      list: all.isEmpty
          ? _empty('No setlists yet')
          : ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final (i, set) in sets.indexed)
                  set.id == _renaming
                      ? _renameRow(
                          colors,
                          leading: SetlistIcon(size: 16, color: colors.muted),
                        )
                      : ExitShift(
                          index: i,
                          child: SwipeRow(
                            key: ValueKey('set-${set.id}-$_generation'),
                            index: i,
                            enabled: _renaming == null,
                            onHold: () =>
                                _startRename(set.id, set.name, _Rename.set),
                            label: 'Delete set',
                            actionLabel: 'Delete set',
                            ask: () => confirmDelete(
                              context,
                              title: 'Delete ${set.name}?',
                              body: switch (set.songIds.length) {
                                0 => null,
                                1 => 'Its 1 song stays in your library.',
                                final n => 'Its $n songs stay in your library.',
                              },
                            ),
                            onSwiped: () => _deleteSet(set),
                            child: _setRow(
                              colors,
                              set,
                              loaded: set.id == loaded,
                            ),
                          ),
                        ),
              ],
            ),
      bar: _undoBar(colors),
      actions: [
        _action(
          key: QuickPick.newSetlistKey,
          label: '+ New setlist',
          opens: true,
          onTap: _newSetlist,
        ),
      ],
    );
  }

  /// The set's songs: a header (name, "Song 4 of 12", "Change set"), the
  /// songs in order (tap = jump; long-press lifts to reorder; swipe
  /// removes, never the playing song), the Undo bar, "+ Add songs ›".
  Widget _setPanel() {
    final colors = context.colors;
    final setlist = _library.activeSetlist;
    if (setlist == null) return _setsPanel();
    final songs = _library.visibleSongs;
    final current = _library.currentIndex;
    return _Panel(
      top: _setHeader(colors, setlist, songs.length, current),
      list: ReorderableList(
        key: _reorderKey,
        shrinkWrap: true,
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: songs.length,
        onReorderStart: (i) {
          _dragFrom = i;
          // No swiping while a row is being dragged.
          setState(() => _reordering = true);
          Haptics.medium();
        },
        // The new order applies the moment the finger lifts (see _drop);
        // the list's own drop animation would hold the next touch.
        onReorderEnd: (insert) => _drop(setlist, insert),
        onReorderItem: (_, _) {},
        proxyDecorator: (_, i, animation) => KeyedSubtree(
          key: _proxyKey,
          child: _lifted(
            animation,
            _entryRow(
              colors,
              setlist,
              songs[i],
              i,
              current: i == current,
              lifted: true,
            ),
          ),
        ),
        itemBuilder: (context, i) {
          // The dropped row settles from where it was let go, once.
          final settle = _settle?.index == i ? _settle : null;
          if (settle != null) _settle = null;
          return HoldToReorder(
            key: ValueKey('entry-${songs[i].id}-$i-$_generation'),
            index: i,
            child: ExitShift(
              index: i,
              child: SettleIn(
                fromTop: settle?.fromTop,
                child: SwipeRow(
                  index: i,
                  enabled: !_reordering,
                  label: 'Remove',
                  actionLabel: 'Remove from set',
                  onSwiped: () => _removeSong(setlist, i, songs[i]),
                  hint: i == _hintRow ? _hint : null,
                  child: _entryRow(
                    colors,
                    setlist,
                    songs[i],
                    i,
                    current: i == current,
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bar: _undoBar(colors),
      actions: [
        _action(
          key: QuickPick.addSongsKey,
          label: '+ Add songs',
          opens: true,
          onTap: () => _openPicker(setlist.id),
        ),
      ],
    );
  }

  /// The finger lifted a dragged row at list position [insert]: the new
  /// order is saved now, the list's drag ends at once (no waiting for its
  /// drop animation), and the row settles in from where it was let go.
  void _drop(Setlist setlist, int insert) {
    final from = _dragFrom;
    _dragFrom = null;
    _reordering = false;
    if (from == null) return;
    final to = insert > from ? insert - 1 : insert;
    final proxy = _proxyKey.currentContext?.findRenderObject() as RenderBox?;
    final top = proxy != null && proxy.attached
        ? proxy.localToGlobal(Offset.zero).dy
        : null;
    _reorderKey.currentState?.cancelReorder();
    if (to != from) _library.reorderSetlist(setlist.id, from, to);
    setState(() {
      _generation++;
      _settle = top == null ? null : (index: to, fromTop: top);
    });
  }

  /// 56px: the set name with "Song 4 of 12" under it (long-press = the
  /// set's page), and "Change set" on the right.
  Widget _setHeader(
    MetraColors colors,
    Setlist setlist,
    int count,
    int current,
  ) => SizedBox(
    height: 56,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: QuickPick.setHeaderKey,
              enableFeedback: false, // Our own haptic, gated by the setting.
              onLongPress: () => _edit(
                (pages) => openSetlists(
                  pages,
                  library: _library,
                  metronome: widget.metronome,
                  setId: setlist.id,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    setlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    current < 0
                        ? (count == 1 ? '1 song' : '$count songs')
                        : 'Song ${current + 1} of $count',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Large system text: the button gives way before the name does.
          Flexible(
            child: SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                key: QuickPick.changeSetKey,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => setState(() => _kind = QuickPickKind.sets),
                icon: const SetlistIcon(size: 16),
                label: const Text(
                  'Change set',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  /// One of the set's songs, 48px: its position (the red play marker for
  /// the current one, on the selected background), name and tempo.
  Widget _entryRow(
    MetraColors colors,
    Setlist setlist,
    Song song,
    int i, {
    required bool current,
    bool lifted = false,
  }) => Material(
    color: lifted
        ? colors.lifted
        : current
        ? colors.selectedRow
        : _isJustAdded(i)
        ? colors.divider
        : colors.sheet,
    child: InkWell(
      key: ValueKey('quick-set-song-$i'),
      enableFeedback: false,
      onTap: () =>
          _choose(() => _library.playSong(song, widget.metronome, index: i)),
      child: Container(
        height: _entryHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: current
                  ? const PlayMarker(current: true)
                  : Text(
                      '${i + 1}',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13, color: colors.slot),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (_isJustAdded(i)) ...[
              const SizedBox(width: 8),
              Text(
                'Added',
                key: ValueKey('added-$i'),
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
            ],
            const SizedBox(width: 12),
            Text(
              '${song.bpm}',
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
          ],
        ),
      ),
    ),
  );

  /// The row being dragged: lifted (lighter, shadow, slightly larger).
  Widget _lifted(Animation<double> animation, Widget row) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Transform.scale(
      scale: 1 + 0.02 * Curves.easeOut.transform(animation.value),
      child: child,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: context.colors.shadow,
            offset: const Offset(0, 6),
            blurRadius: 16,
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(4), child: row),
    ),
  );

  void _removeSong(Setlist setlist, int i, Song song) {
    final wasCurrent =
        setlist.id == _library.activeSetlist?.id && i == _library.currentIndex;
    _library.removeSongAt(setlist.id, i, widget.metronome);
    setState(() => _generation++);
    _showUndo(
      'Removed from ${setlist.name}',
      () => _library.insertSongAt(
        setlist.id,
        i,
        song.id,
        widget.metronome,
        wasCurrent: wasCurrent,
      ),
    );
  }

  void _deleteSet(Setlist setlist) {
    final deleted = _library.deleteSetlistAt(setlist.id, widget.metronome);
    if (deleted == null) return;
    setState(() => _generation++);
    _showUndo(
      'Deleted set "${setlist.name}"',
      () => _library.restoreSetlist(deleted, widget.metronome),
    );
  }

  void _deleteSong(Song song) {
    final deleted = _library.deleteSongForUndo(song.id, widget.metronome);
    if (deleted == null) return;
    setState(() => _generation++);
    _showUndo(
      'Deleted "${song.name}"',
      () => _library.restoreSong(deleted, widget.metronome),
    );
  }

  /// A row's name becomes a field, selected, keyboard up.
  void _startRename(String id, String name, _Rename kind) {
    if (kind == _Rename.set || kind == _Rename.song) Haptics.medium();
    _rename
      ..text = name
      ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);
    setState(() {
      _renaming = id;
      _renameKind = kind;
    });
  }

  /// Done / Enter: saves (an empty name keeps the old or default one). A
  /// new set then gets its songs from the library and comes back here; a
  /// new song is made from the click, loaded (Single song), and the panel
  /// closes.
  void _finishRename() {
    final id = _renaming;
    final kind = _renameKind;
    if (id == null || kind == null) return;
    setState(() {
      _renaming = null;
      _renameKind = null;
    });
    switch (kind) {
      case _Rename.set:
        _library.renameSetlist(id, _rename.text);
      case _Rename.newSet:
        _library.renameSetlist(id, _rename.text);
        _openPicker(id, returnsToSets: true);
      case _Rename.song:
        _library.renameSong(id, _rename.text);
      case _Rename.newSong:
        final name = _rename.text.trim();
        _choose(
          () => _library.saveAsNewSong(
            name.isEmpty ? _library.newSongName() : name,
            widget.metronome,
          ),
        );
    }
  }

  /// Outside / Back: nothing changes (a new song isn't made; a new set
  /// keeps its default name).
  void _cancelRename() => setState(() {
    _renaming = null;
    _renameKind = null;
  });

  /// "+ New setlist ›": a new set on top, already being named.
  void _newSetlist() {
    final set = _library.createSetlist();
    _startRename(set.id, set.name, _Rename.newSet);
  }

  /// "+ New song ›": a row on top, being named "Song N".
  void _newSong() =>
      _startRename(_newSongId, _library.newSongName(), _Rename.newSong);

  /// The row being renamed: a field with the name selected, and "Done".
  Widget _renameRow(MetraColors colors, {required Widget leading}) => Container(
    height: _rowHeight,
    color: colors.selectedRow,
    padding: const EdgeInsets.only(left: 14, right: 4),
    child: Row(
      children: [
        SizedBox(width: 16, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            key: QuickPick.renameFieldKey,
            controller: _rename,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            decoration: const InputDecoration.collapsed(hintText: ''),
            onSubmitted: (_) => _finishRename(),
            onTapOutside: (_) => _cancelRename(),
          ),
        ),
        // Inside the field's tap region: tapping Done isn't "outside".
        TextFieldTapRegion(
          child: TextButton(
            key: QuickPick.renameDoneKey,
            onPressed: _finishRename,
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );

  /// After a removal or deletion: what happened, and "Undo".
  Widget? _undoBar(MetraColors colors) {
    final undo = _undo;
    if (undo == null) return null;
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: colors.divider,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              undo.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.tickSounding),
            ),
          ),
          TextButton(
            key: QuickPick.undoKey,
            style: TextButton.styleFrom(foregroundColor: colors.text),
            onPressed: _runUndo,
            child: const Text(
              'Undo',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Tap = play (long-press renames: see its [SwipeRow]).
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

  /// Tap = load at song 1 (long-press renames: see its [SwipeRow]). The loaded set is
  /// marked like the current song.
  Widget _setRow(MetraColors colors, Setlist setlist, {required bool loaded}) =>
      _row(
        colors,
        key: ValueKey('quick-set-${setlist.id}'),
        selected: loaded,
        onTap: () =>
            _choose(() => _library.loadSetlist(setlist.id, widget.metronome)),
        children: [
          loaded
              ? const SizedBox(width: 16, child: PlayMarker(current: true))
              : SetlistIcon(size: 16, color: colors.muted),
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
    required List<Widget> children,
    VoidCallback? onLongPress,
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
  const _Panel({this.top, required this.list, required this.actions, this.bar});

  final Widget? top;
  final Widget list;
  final List<Widget> actions;

  /// Just above the pinned actions (the Undo bar).
  final Widget? bar;

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
        // The lists' scroll slop: past it, vertical movement scrolls and a
        // pending long-press is off.
        Flexible(
          // Where committed rows slide off and the gap closes.
          child: RowExitHost(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(gestureSettings: RowGestures.listSettings),
              child: list,
            ),
          ),
        ),
        ?bar,
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

/// What Done does with the row being renamed.
enum _Rename { set, newSet, song, newSong }
