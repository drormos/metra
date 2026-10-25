import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import '../platform/android_bridge.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'icons.dart';
import 'motion.dart';
import 'play_marker.dart';
import 'search_match.dart';
import 'swipe_row.dart';
import 'panel_motion.dart';
import 'theme.dart';
import 'top_panel.dart';

/// Which dropdown: the Songs or Setlists mode tab, or the set's "4/12 ⌄"
/// (setlist mode).
enum QuickPickKind { songs, sets, set }

/// What the panel does as it opens: the context row's empty-state "+"
/// buttons (ui-spec.md "Empty lists") go straight to creating.
enum QuickPickStart { none, newSong, newSetlist, addSongs }

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
  QuickPickStart start = QuickPickStart.none,
}) {
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero) & box.size;
  return Navigator.push(
    context,
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: RowGestures.motion(context, MetraMotion.arrive),
      reverseTransitionDuration: RowGestures.motion(
        context,
        PanelMotion.settle,
      ),
      pageBuilder: (_, _, _) => _QuickPickLayer(
        anchor: anchor,
        inset: inset,
        // Lists follow the system font size fully (rows grow).
        child: QuickPick(
          kind: kind,
          library: library,
          metronome: metronome,
          start: start,
        ),
      ),
      // [PanelMotion] in the layer moves it (out of the center button).
      transitionsBuilder: (_, _, _, child) => child,
    ),
  );
}

/// The dim (with the bar cut out of it) and the panel above [anchor].
class _QuickPickLayer extends StatefulWidget {
  const _QuickPickLayer({
    required this.anchor,
    required this.inset,
    required this.child,
  });

  final Rect anchor;
  final double inset;
  final Widget child;

  @override
  State<_QuickPickLayer> createState() => _QuickPickLayerState();
}

/// ui-spec.md "Taller panel": the handle drags the panel up to the full
/// space above the context row and snaps to normal or tall (nearer, or by
/// flick); dragged down from normal it follows and closes. It always
/// opens normal; with the keyboard up the handle does nothing.
class _QuickPickLayerState extends State<_QuickPickLayer>
    with SingleTickerProviderStateMixin {
  final _panel = GlobalKey();
  // The panel's height while dragged or tall; null = normal (its own).
  late final _height = AnimationController.unbounded(vsync: this)
    ..addListener(() => setState(() {}));
  double? _normal; // measured when a drag starts
  bool _sized = false; // [_height] is in use

  // The panel's motion (its own swipe down to close).
  PanelMotionState get _motion => PanelMotion.of(_panel.currentContext!);

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  double get _tallHeight {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return max(0, size.height - _bottom - padding.top - 8);
  }

  // Above the bar, or above the keyboard while searching.
  double get _bottom => max(
    MediaQuery.sizeOf(context).height - widget.anchor.top + 18,
    MediaQuery.viewInsetsOf(context).bottom + 8,
  );

  bool get _keyboard => MediaQuery.viewInsetsOf(context).bottom > 0;

  void _start(DragStartDetails _) {
    _height.stop();
    if (!_sized) {
      final box = _panel.currentContext?.findRenderObject() as RenderBox?;
      _normal = box?.size.height ?? 0;
      _height.value = _normal!;
    }
  }

  void _update(DragUpdateDetails d) {
    final normal = _normal ?? 0;
    final next = _height.value - d.delta.dy;
    setState(() {
      if (next >= normal) {
        _sized = true;

        _height.value = min(next, _tallHeight);
      } else {
        // Below normal: the panel follows the finger down, to close.
        _height.value = normal;
        _sized = false;
        _motion.dragBy(d.delta.dy);
      }
    });
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final normal = _normal ?? 0;
    final motion = _motion;
    if (motion.dragged > 0) {
      // Past the threshold or flicked down: it flies off the bottom, from
      // where it is; otherwise it springs back.
      return motion.release(
        velocity: v,
        close:
            v > QuickPick.flick ||
            (motion.dragged > QuickPick.closeDrag && v >= -QuickPick.flick),
      );
    }
    final tall =
        v < -QuickPick.flick ||
        (v <= QuickPick.flick &&
            _height.value - normal > (_tallHeight - normal) / 2);
    _snap(tall ? _tallHeight : normal, tall: tall);
  }

  void _snap(double target, {required bool tall}) {
    void done() {
      if (mounted && !tall) setState(() => _sized = false);
    }

    if (MetraMotion.reduced(context)) {
      _height.value = target;
      return done();
    }
    _height
        .animateTo(
          target,
          duration: MetraMotion.arrive,
          curve: MetraMotion.arriveCurve,
        )
        .whenCompleteOrCancel(done);
  }

  /// TalkBack and a tap: switch between normal and tall.
  void _toggle() {
    if (_keyboard) return;
    _start(DragStartDetails());
    final tall = !(_sized && _height.value >= _tallHeight - 1);
    if (tall) _sized = true;
    _snap(tall ? _tallHeight : _normal ?? 0, tall: tall);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final anchor = widget.anchor;
    final bottom = _bottom;
    final normalMax = min(470.0, _tallHeight);
    final tall = _sized && _height.value > (_normal ?? 0) + 0.5;
    final height = _sized ? _height.value : null;
    return PanelMotion(
      route: ModalRoute.of(context)!,
      // The context row's center button, which opens every list.
      origin: Offset(anchor.center.dx, anchor.top + 32),
      edge: PanelEdge.bottom,
      builder: (context, motion) => Stack(
        children: [
          Positioned.fill(
            child: CloseOnTouch(
              key: QuickPick.outsideKey,
              child: CustomPaint(
                painter: _Dim(
                  colors.dim.withValues(alpha: colors.dim.a * motion.dim),
                  anchor,
                ),
              ),
            ),
          ),
          Positioned(
            left: anchor.left + widget.inset,
            right: size.width - anchor.right + widget.inset,
            bottom: bottom,
            child: motion.panel(
              ConstrainedBox(
                key: _panel,
                constraints: height == null
                    ? BoxConstraints(maxHeight: max(0, normalMax))
                    : BoxConstraints.tightFor(height: max(0, height)),
                child: Semantics(
                  customSemanticsActions: _keyboard
                      ? null
                      : {
                          CustomSemanticsAction(
                            label: tall
                                ? 'Make the list shorter'
                                : 'Make the list taller',
                          ): _toggle,
                        },
                  child: Material(
                    color: colors.sheet,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: colors.border),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _handle(colors),
                        Flexible(
                          fit: height == null ? FlexFit.loose : FlexFit.tight,
                          child: _FillsPanel(
                            fills: height != null,
                            child: widget.child,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // The grab strip: the handle's drag (taller, shorter, close),
              // inert while the keyboard is up.
              onGrabStart: _keyboard ? null : _start,
              onGrabUpdate: _keyboard ? null : _update,
              onGrabEnd: _keyboard ? null : _end,
            ),
          ),
        ],
      ),
    );
  }

  /// 36×4 in a 24px area, centered at the panel's top edge; dragged
  /// through the panel's grab strip ([PanelMotionState.panel]). Screen
  /// readers get it as an action on the panel ([build]).
  Widget _handle(MetraColors colors) => ExcludeSemantics(
    child: KeyedSubtree(
      key: QuickPick.handleKey,
      child: SizedBox(
        height: QuickPick.handleArea,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              // The resting-beat grey (#3A3A3A).
              color: colors.beatResting,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Tells the panel's list whether to fill a set height (tall, or while
/// dragged) or size to its rows.
class _FillsPanel extends InheritedWidget {
  const _FillsPanel({required this.fills, required super.child});

  final bool fills;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FillsPanel>()?.fills ?? false;

  @override
  bool updateShouldNotify(_FillsPanel old) => old.fills != fills;
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
    this.start = QuickPickStart.none,
  });

  final QuickPickKind kind;
  final LibraryController library;
  final MetronomeController metronome;

  final QuickPickStart start;

  static const searchAbove = 8;
  static const outsideKey = Key('quick-pick-outside');
  static const handleKey = Key('quick-pick-handle');

  /// The handle's drag area; a drag down from normal past [closeDrag], or
  /// a flick faster than [flick] (dp/s), closes or snaps.
  static const handleArea = 24.0;
  static const closeDrag = 80.0;
  static const flick = 700.0;
  static const songLibraryKey = Key('quick-pick-song-library');
  static const setHeaderKey = Key('quick-pick-set-header');
  static const changeSetKey = Key('quick-pick-change-set');
  static const pickBackKey = Key('quick-pick-picker-back');
  static const pickAddKey = Key('quick-pick-picker-add');
  static const pickSearchKey = Key('quick-pick-picker-search');

  /// How long a list's one-time hint line stays.
  static const hintLineFor = Duration(seconds: 3);

  /// How long rows just added from the picker show "Added".
  static const addedFor = Duration(seconds: 2);
  static const setSearchKey = Key('quick-pick-set-search');
  static const backKey = Key('quick-pick-back');
  static const addSongsKey = Key('quick-pick-add-songs');
  static const stageModeKey = Key('quick-pick-stage-mode');
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
  int _undoSwiped = 0;
  Timer? _undoTimer;

  // ~6 s, or longer if Android's "Time to take action" asks for it.
  Duration _undoFor = QuickPick.undoFor;

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

  // The one-time hint: in list [_hintKind], [_hintRow] slides out and
  // back, then [_hintLine] shows under the list for a moment.
  QuickPickKind? _hintKind;
  int? _hintRow;
  String? _hintLine;
  Timer? _hintLineTimer;
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
    if (widget.start == QuickPickStart.none) _maybeHint(widget.kind);
    // After the first frame: creating changes the library mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.start) {
        case QuickPickStart.none:
          break;
        case QuickPickStart.newSong:
          _newSong();
        case QuickPickStart.newSetlist:
          _newSetlist();
        case QuickPickStart.addSongs:
          if (_library.activeSetlist case final set?) _openPicker(set.id);
      }
    });
    AndroidBridge.recommendedTimeout(QuickPick.undoFor).then((d) {
      _undoFor = d;
    });
  }

  /// Principle 7's one-time hints (ui-spec.md "One-time hints"): the
  /// first time each list shows 2+ rows, a row that isn't current slides
  /// out to show the swipe, then a muted line names both gestures for
  /// [QuickPick.hintLineFor]. Once per list (stored flag); with "Remove
  /// animations" it's skipped but still counts as shown.
  void _maybeHint(QuickPickKind kind) {
    final int count;
    final int current;
    final VoidCallback seen;
    final String line;
    switch (kind) {
      case QuickPickKind.set when !_library.swipeHintSeen:
        count = _library.visibleSongs.length;
        current = _library.currentIndex;
        seen = _library.markSwipeHintSeen;
        line = 'Hold a song to move it · Swipe to remove';
      case QuickPickKind.sets when !_library.setsHintSeen:
        final sets = _library.setlistsRecentlyPlayed;
        count = sets.length;
        current = sets.indexWhere((s) => s.id == _library.activeSetlist?.id);
        seen = _library.markSetsHintSeen;
        line = 'Hold a set to rename it · Swipe to delete';
      case QuickPickKind.songs when !_library.songsHintSeen:
        final songs = _library.songsAZ;
        count = songs.length;
        current = songs.indexWhere((s) => s.id == _library.currentSong?.id);
        seen = _library.markSongsHintSeen;
        line = 'Hold a song to rename it · Swipe to delete';
      default:
        return;
    }
    if (count < 2) return;
    _hintKind = kind;
    _hintRow = current == 0 ? 1 : 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      seen();
      // "Remove animations": no hint (it still counts as shown).
      if (RowGestures.reduceMotion(context)) {
        return setState(() => _hintRow = null);
      }
      _hint.forward(from: 0).whenComplete(() {
        if (!mounted) return;
        setState(() {
          _hintRow = null;
          _hintLine = line;
        });
        _hintLineTimer?.cancel();
        _hintLineTimer = Timer(QuickPick.hintLineFor, () {
          if (mounted) setState(() => _hintLine = null);
        });
      });
    });
  }

  /// The hint for list [kind]'s row [i], while it runs.
  Animation<double>? _hintFor(QuickPickKind kind, int i) =>
      _hintKind == kind && i == _hintRow ? _hint : null;

  /// The muted line under the list, after the nudge.
  Widget? _hintNote(MetraColors colors) {
    final line = _hintLine;
    if (line == null || _hintKind != _kind) return null;
    return Padding(
      key: const ValueKey('hint-line'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        line,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: colors.muted),
      ),
    );
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _addedTimer?.cancel();
    _hintLineTimer?.cancel();
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
    _undoTimer = Timer(_undoFor, () {
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
        // Swapping lists in place, the new one arrives.
        builder: (context, _) => Arrive(
          value: _pickFor != null ? 'picker' : _kind,
          child: switch (_kind) {
            _ when _pickFor != null => _pickerPanel(),
            QuickPickKind.songs => _songsPanel(),
            QuickPickKind.sets => _setsPanel(),
            QuickPickKind.set => _setPanel(),
          },
        ),
      ),
    ),
  );

  /// The Songs list, A–Z: tap = load (Single song); long-press renames in
  /// place; swipe deletes after a dialog (not the loaded song), with
  /// Undo; "+ New song ›" names a song made from the click as it is now.
  Widget _songsPanel() {
    final colors = context.colors;
    final all = _library.songsAZ;
    final query = _search.text;
    final songs = [
      for (final song in all)
        if (query.isEmpty ||
            song.id == _renaming ||
            matchesSearch(song.name, query))
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
          : songs.isEmpty && _renaming == null
          ? NoMatches('songs', query, color: colors.muted)
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
                            moreActions: {
                              'Rename': () => _startRename(
                                song.id,
                                song.name,
                                _Rename.song,
                              ),
                            },
                            ask: () => confirmDelete(
                              context,
                              title: 'Delete ${song.name}?',
                              body: switch (_library.setlistsUsing(song.id)) {
                                final sets when sets.isEmpty => null,
                                final sets =>
                                  'It will also be removed from '
                                      '${whereUsed(sets)}.',
                              },
                            ),
                            onSwiped: () => _deleteSong(song),
                            hint: query.isEmpty
                                ? _hintFor(QuickPickKind.songs, i)
                                : null,
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
      note: ArriveLeave(child: _hintNote(colors)),
      // Swiped away, the bar is already gone: no leaving copy.
      bar: ArriveLeave(key: ValueKey(_undoSwiped), child: _undoBar(colors)),
      actions: [
        _action(
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
    // A set just built from "+ New setlist": stopped, it loads at song 1
    // and the panel shows its songs; playing, nothing switches and the
    // sets view shows it on top (ui-spec.md "Adding songs to sets").
    final load = toSets && !widget.metronome.isPlaying;
    if (load) {
      Haptics.medium();
      _library.loadSetlist(set.id, widget.metronome);
    }
    setState(() {
      _pickFor = null;
      _generation++;
      if (load) _kind = QuickPickKind.set;
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
    final query = _pickSearch.text;
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
            if (matchesSearch(song.name, query))
              _pickRow(colors, song, inSet: inSet.contains(song.id)),
          if (!all.any((s) => matchesSearch(s.name, query)))
            NoMatches('songs', query, color: colors.muted),
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
    final faint = inSet ? colors.disabledText : null;
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
          constraints: const BoxConstraints(minHeight: _rowHeight),
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
                        : colors.controlOutline,
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
                    SearchName(
                      song.name,
                      query: _pickSearch.text,
                      matchColor: faint ?? colors.text,
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
                    color: inSet ? colors.disabledText : colors.muted,
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
                    color: inSet ? colors.disabledText : colors.muted,
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
    final query = _setSearch.text;
    final sets = [
      for (final set in all)
        if (query.isEmpty ||
            set.id == _renaming ||
            matchesSearch(set.name, query))
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
          : sets.isEmpty
          ? NoMatches('sets', query, color: colors.muted)
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
                            hint: _hintFor(QuickPickKind.sets, i),
                            onHold: () =>
                                _startRename(set.id, set.name, _Rename.set),
                            label: 'Delete set',
                            actionLabel: 'Delete set',
                            moreActions: {
                              'Rename': () =>
                                  _startRename(set.id, set.name, _Rename.set),
                            },
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
      note: ArriveLeave(child: _hintNote(colors)),
      // Swiped away, the bar is already gone: no leaving copy.
      bar: ArriveLeave(key: ValueKey(_undoSwiped), child: _undoBar(colors)),
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
                  moreActions: {
                    if (i > 0) 'Move up': () => _move(setlist, i, i - 1),
                    if (i < songs.length - 1)
                      'Move down': () => _move(setlist, i, i + 1),
                  },
                  onSwiped: () => _removeSong(setlist, i, songs[i]),
                  hint: _hintFor(QuickPickKind.set, i),
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
      note: ArriveLeave(child: _hintNote(colors)),
      // Swiped away, the bar is already gone: no leaving copy.
      bar: ArriveLeave(key: ValueKey(_undoSwiped), child: _undoBar(colors)),
      actions: [
        // The panel's main action, so an outlined button, not a row
        // (ui-spec.md "Adding songs to sets").
        // "Add songs" and "Stage mode" share the row, half width each
        // (ui-spec.md "Stage mode").
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: _outlined(
                  key: QuickPick.addSongsKey,
                  colors: colors,
                  onPressed: () => _openPicker(setlist.id),
                  icon: const SetlistIcon(),
                  label: 'Add songs',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _outlined(
                  key: QuickPick.stageModeKey,
                  colors: colors,
                  onPressed: () {
                    Haptics.medium();
                    Navigator.pop(context);
                    _library.enterStageMode();
                  },
                  icon: const StageIcon(),
                  label: 'Stage mode',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A 48px outlined button of the set panel's pinned row.
  Widget _outlined({
    required Key key,
    required MetraColors colors,
    required VoidCallback onPressed,
    required Widget icon,
    required String label,
  }) => OutlinedButton.icon(
    key: key,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      side: BorderSide(color: colors.border, width: 2),
    ),
    onPressed: onPressed,
    icon: icon,
    label: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  );

  /// TalkBack's "Move up" / "Move down": one place, saved at once.
  void _move(Setlist setlist, int from, int to) {
    _library.reorderSetlist(setlist.id, from, to);
    setState(() => _generation++);
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

  /// 56px: the set name with "Song 4 of 12" under it, and "Change set"
  /// on the right.
  Widget _setHeader(
    MetraColors colors,
    Setlist setlist,
    int count,
    int current,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: QuickPick.setHeaderKey,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
          ),
          const SizedBox(width: 8),
          // Large system text: the button gives way before the name does.
          Flexible(
            // 40px to see, 48dp to touch (padded tap target).
            child: SizedBox(
              child: OutlinedButton.icon(
                key: QuickPick.changeSetKey,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: () {
                  setState(() => _kind = QuickPickKind.sets);
                  _maybeHint(QuickPickKind.sets);
                },
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
        constraints: const BoxConstraints(minHeight: _entryHeight),
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
                      style: TextStyle(fontSize: 13, color: colors.muted),
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
            if (current)
              Semantics(label: 'playing', child: const SizedBox.shrink()),
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
            fresh: true,
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
    constraints: const BoxConstraints(minHeight: _rowHeight),
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
    // Swiped sideways it goes (the action stays done); screen readers
    // announce it as it appears.
    return Dismissible(
      key: ObjectKey(undo),
      onDismissed: (_) {
        _undoTimer?.cancel();
        setState(() {
          _undo = null;
          _undoSwiped++;
        });
      },
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
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
        ),
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
        child: SearchName(
          song.name,
          query: _search.text,
          matchColor: colors.text,
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
      if (current) Semantics(label: 'playing', child: const SizedBox.shrink()),
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
            child: SearchName(
              setlist.name,
              query: _setSearch.text,
              matchColor: colors.text,
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _rowHeight),
          child: Row(children: children),
        ),
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
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
  const _Panel({
    this.top,
    required this.list,
    required this.actions,
    this.bar,
    this.note,
  });

  final Widget? top;
  final Widget list;
  final List<Widget> actions;

  /// Just above the pinned actions (the Undo bar).
  final Widget? bar;

  /// Under the list (the one-time hint line).
  final Widget? note;

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
          fit: _FillsPanel.of(context) ? FlexFit.tight : FlexFit.loose,
          // Where committed rows slide off and the gap closes.
          child: RowExitHost(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(gestureSettings: RowGestures.listSettings),
              child: list,
            ),
          ),
        ),
        ?note,
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
