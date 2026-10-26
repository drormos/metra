import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../controller/rhythm_target.dart';
import '../model/library.dart';
import '../model/metronome_pattern.dart';
import '../model/on_start.dart';
import 'beat_indicator.dart' show MutedLine;
import 'dashed_outline.dart';
import 'editor_scaffold.dart' show confirmDelete;
import 'fit_text.dart';
import 'haptics.dart';
import 'motion.dart';
import 'save_as_new_dialog.dart';
import 'subdivision_icon.dart';
import 'swipe_row.dart';
import 'theme.dart';
import 'time_signature_sheet.dart';
import 'top_panel.dart';
import 'value_stepper.dart';

/// Opens the parts page for the loaded song (ui-spec.md "Song parts" →
/// "The parts page", `song-parts.reference.html` columns 1–2).
Future<void> openPartsPage(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => PartsPage(library: library, metronome: metronome),
  ),
);

/// The song as a list of parts: the strip to scale, a card per part (tap
/// opens it in place, long-press reorders, swipe removes with Undo), "+ Add
/// part", "When the song ends". Every edit is an ordinary unsaved change to
/// the loaded song, applied to the click as it's made
/// ([MetronomeController.setParts]); Revert / Save / Save as new at the
/// bottom, as on the main screen.
class PartsPage extends StatefulWidget {
  const PartsPage({super.key, required this.library, required this.metronome});

  final LibraryController library;
  final MetronomeController metronome;

  static const playKey = Key('parts-play');
  static const nameKey = Key('parts-song-name');
  static const summaryKey = Key('parts-summary');
  static const addKey = Key('parts-add');
  static const endKey = Key('parts-end');
  static const gradualKey = Key('parts-gradual');
  static const titleKey = Key('parts-title');
  static Key fillKey(int i) => ValueKey('parts-fill-$i');

  /// The first "+ Add part" on a plain song gives both parts this many.
  static const firstAddBars = 8;
  static const steadyKey = Key('parts-steady');
  static const loopIconKey = Key('parts-loop-icon');
  static const rhythmKey = Key('parts-rhythm');
  static const playFromKey = Key('parts-play-from');
  static const duplicateKey = Key('parts-duplicate');
  static const partNameKey = Key('parts-part-name');
  static const undoKey = Key('parts-undo');
  static const discardKey = Key('parts-discard');
  static const saveKey = Key('parts-save');

  static Key cardKey(int i) => ValueKey('parts-card-$i');
  static Key stripKey(int i) => ValueKey('parts-strip-$i');
  static Key accentKey(int beat) => ValueKey('parts-accent-$beat');

  static const customName = 'Custom name…';

  @override
  State<PartsPage> createState() => _PartsPageState();
}

class _PartsPageState extends State<PartsPage> with TickerProviderStateMixin {
  LibraryController get _library => widget.library;
  MetronomeController get _metronome => widget.metronome;

  String? _openId;
  // The open part when its end tempo was turned on: "Ends at" stays while
  // Starts at and Ends at pass each other.
  final _gradual = <String>{};
  final _cardKeys = <String, GlobalKey>{};
  // Each open card's body, measured when another card's opening closes it.
  final _bodyKeys = <String, GlobalKey>{};
  final _scroll = ScrollController();
  // Cards that grow in as they're built (added, duplicated, undone).
  final _arriving = <String>{};
  // Keeps a tapped header still while a card above it closes.
  late final AnimationController _anchor = AnimationController(vsync: this);
  Timer? _reveal;
  ({SongPart part, int index})? _removed;
  Timer? _undoTimer;
  int _idCounter = 0;
  // The card of the part playing and how far through it the music is
  // (0–1), read from the engine every frame while playing. Only the
  // header's fill repaints with [_progress]; the cards rebuild only when
  // the part changes.
  late final Ticker _follow = createTicker((_) => _checkPlaying());
  final _progress = ValueNotifier(0.0);
  int? _playing;

  @override
  void initState() {
    super.initState();
    _library.editingParts = true;
    _metronome.addListener(_onMetronome);
    _onMetronome();
  }

  @override
  void dispose() {
    _library.editingParts = false;
    _metronome.removeListener(_onMetronome);
    _undoTimer?.cancel();
    _follow.dispose();
    _progress.dispose();
    _closing?.cancel();
    _reveal?.cancel();
    _anchor.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMetronome() {
    if (_metronome.isPlaying) {
      if (!_follow.isActive) _follow.start();
    } else {
      _follow.stop();
    }
    _checkPlaying();
  }

  /// The part playing and the fill across it: by the beat position the
  /// visual clock is at, so it moves with a Gradual part's tempo and starts
  /// empty on every part start (every pass of a looping part); with
  /// "Remove animations", whole bars only.
  void _checkPlaying() {
    if (!mounted) return;
    final playing = _metronome.isPlaying;
    final at = playing
        ? _metronome.playheadAt(
            SchedulerBinding.instance.currentSystemFrameTimeStamp,
          )
        : null;
    final part = playing ? (at?.part ?? 0) : null;
    if (part != _playing) setState(() => _playing = part);
    final parts = _metronome.parts;
    if (at == null || parts == null || at.part >= parts.length) {
      _progress.value = 0;
      return;
    }
    final bars = parts[at.part].bars;
    final into = MetraMotion.reduced(context) ? 0.0 : at.fraction;
    _progress.value = ((at.bar + into) / bars).clamp(0.0, 1.0);
  }

  /// The loaded song's parts as they play now: a plain one-part song's
  /// one part from the click itself.
  List<SongPart> _parts(Song song) =>
      _metronome.parts ??
      [
        SongPart.steady(
          id: song.parts.first.id,
          name: song.parts.first.name,
          bars: song.parts.first.bars,
          bpm: _metronome.startBpm,
          pattern: _metronome.pattern,
        ),
      ];

  void _set(List<SongPart> parts, {SongEnd? end}) =>
      _metronome.setParts(parts, end: end);

  void _edit(Song song, int i, SongPart Function(SongPart) change) {
    final parts = [..._parts(song)];
    parts[i] = change(parts[i]);
    _set(parts);
  }

  String _newId() =>
      'part-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_idCounter++}';

  // Closes a held open card a frame before the reorder lift.
  Timer? _closing;
  // That press closed it: its tap mustn't open it again.
  bool _heldClosed = false;
  // Closed by a hold, at once: the list takes the lifted card's size at
  // the lift, and a card still collapsing would make it auto-scroll.
  String? _snapClosed;

  void _closeBeforeLift(String id) {
    _heldClosed = false;
    _closing?.cancel();
    _closing = Timer(
      RowGestures.liftPress - const Duration(milliseconds: 40),
      () {
        if (mounted && _openId == id) {
          _heldClosed = true;
          setState(() {
            _openId = null;
            _snapClosed = id;
          });
        }
      },
    );
  }

  /// Opens card [id] (or closes it, open already), in one ~180ms height
  /// change. Its header stays under the finger: when a card above it
  /// closes at the same time, the list scrolls by that card's body on the
  /// same curve. From the strip ([scroll]): scrolls to the card. Never
  /// waits: a tap mid-animation retargets it.
  void _open(String id, {bool scroll = false}) {
    _snapClosed = null;
    if (_heldClosed) {
      _heldClosed = false;
      return;
    }
    final previous = _openId;
    final opening = previous != id;
    final above = opening && previous != null && !scroll
        ? _bodyAbove(previous, id)
        : 0.0;
    setState(() {
      _openId = opening ? id : null;
      // An end equal to its start is a steady part: reopened, it shows
      // the button again.
      _gradual.retainWhere((g) => g == _openId);
    });
    // Started now, its clock counts from the coming frame, as the closing
    // card's size animation (started in that frame's layout) does.
    if (above > 0) _keepStill(above);
    if (!opening) return;
    _reveal?.cancel();
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(id));
    } else {
      // Once open, only if it ends below the screen, only as far as needed.
      _reveal = Timer(MetraMotion.of(context, MetraMotion.cardExpand), () {
        _scrollTo(id, end: true);
      });
    }
  }

  /// The height of [previous]'s open body when that card sits above [id].
  double _bodyAbove(String previous, String id) {
    final before = _cardKeys[previous]?.currentContext?.findRenderObject();
    final card = _cardKeys[id]?.currentContext?.findRenderObject();
    final body = _bodyKeys[previous]?.currentContext?.size?.height;
    if (before is! RenderBox || card is! RenderBox || body == null) return 0;
    final above =
        before.localToGlobal(Offset.zero).dy <
        card.localToGlobal(Offset.zero).dy;
    return above ? body : 0;
  }

  // shortcut: at the top of the list there's nothing to scroll back, so
  // the header moves up by what's left; keeping it still there would need
  // an empty gap above the cards.
  void _keepStill(double height) {
    if (!mounted || !_scroll.hasClients) return;
    final start = _scroll.position.pixels;
    void follow() {
      if (!_scroll.hasClients) return;
      final t = MetraMotion.cardCurve.transform(_anchor.value);
      _scroll.position.jumpTo((start - height * t).clamp(0, double.infinity));
    }

    _anchor
      ..stop()
      ..duration = MetraMotion.of(context, MetraMotion.cardExpand)
      ..removeListener(follow)
      ..addListener(follow)
      ..forward(from: 0).whenComplete(() => _anchor.removeListener(follow));
  }

  /// Scrolls card [id] into view: to it (~250ms ease-in-out), or with
  /// [end] only if it ends below the screen (~200ms).
  void _scrollTo(String id, {bool end = false}) {
    final context = _cardKeys[id]?.currentContext;
    if (context == null || !context.mounted) return;
    Scrollable.ensureVisible(
      context,
      duration: MetraMotion.of(
        context,
        end ? MetraMotion.reveal : MetraMotion.jump,
      ),
      curve: end ? MetraMotion.cardCurve : Curves.easeInOut,
      alignmentPolicy: end
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.explicit,
    );
  }

  void _add(Song song) {
    var parts = _parts(song);
    // The first add on a plain song (one part of 1 bar, a length never
    // really chosen): both parts get 8 bars, a real starting point.
    if (parts.length == 1 && parts.single.bars == 1) {
      parts = [parts.single.copyWith(bars: PartsPage.firstAddBars)];
    }
    final last = parts.last;
    // The last part's rhythm and length, the next name, steady at the
    // tempo the song has reached (a Gradual part's To).
    final added = SongPart(
      id: _newId(),
      name: nextPartName(parts),
      bars: last.bars,
      tempoStart: last.tempoEnd,
      tempoEnd: last.tempoEnd,
      pattern: last.pattern,
    );
    Haptics.tick();
    _arriving.add(added.id);
    _set([...parts, added]);
    _open(added.id);
  }

  void _duplicate(Song song, int i) {
    final parts = _parts(song);
    final p = parts[i];
    final copy = SongPart(
      id: _newId(),
      name: p.name,
      bars: p.bars,
      tempoStart: p.tempoStart,
      tempoEnd: p.tempoEnd,
      pattern: p.pattern,
    );
    Haptics.tick();
    _arriving.add(copy.id);
    _set([...parts]..insert(i + 1, copy));
    _open(copy.id);
  }

  void _remove(Song song, int i) {
    final parts = [..._parts(song)];
    if (parts.length < 2) return;
    final part = parts.removeAt(i);
    _set(parts);
    _undoTimer?.cancel();
    setState(() => _removed = (part: part, index: i));
    _undoTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _removed = null);
    });
  }

  void _undo(Song song) {
    final removed = _removed;
    if (removed == null) return;
    _undoTimer?.cancel();
    final parts = [..._parts(song)];
    parts.insert(removed.index.clamp(0, parts.length), removed.part);
    _arriving.add(removed.part.id);
    _set(parts);
    setState(() => _removed = null);
  }

  /// Part [from] moves to position [to] (counted without it).
  void _reorder(Song song, int from, int to) {
    final parts = [..._parts(song)];
    if (to == from) return;
    parts.insert(to, parts.removeAt(from));
    _set(parts);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_library, _metronome]),
    builder: (context, _) {
      final song = _library.currentSong;
      if (song == null) {
        // Deleted or unloaded elsewhere: nothing left to edit.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.maybePop(context);
        });
        return const Scaffold();
      }
      final parts = _parts(song);
      final changed = _library.songChanged(_metronome);
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _topBar(context, song, parts, changed: changed),
                  // The summary on its own line: beside the name, Save /
                  // Discard cut it short.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: BrightenSwap(
                      value: partsSummary(parts, _metronome.songEnd),
                      child: Text(
                        partsSummary(parts, _metronome.songEnd),
                        key: PartsPage.summaryKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.muted,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: _strip(context, parts),
                  ),
                  Expanded(child: _list(context, song, parts)),
                  if (_removed case final removed?)
                    _undoBar(context, song, removed.part),
                  _playButton(context),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _topBar(
    BuildContext context,
    Song song,
    List<SongPart> parts, {
    required bool changed,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: LayoutBuilder(
        builder: (context, bar) => Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.chevron_left, size: 28),
            ),
            Expanded(
              child: Semantics(
                button: true,
                onTapHint: 'rename',
                child: InkWell(
                  key: PartsPage.nameKey,
                  onTap: () => _rename(context, song),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    // Shrinks to fit like the main-screen title, down to
                    // 22px, before "…".
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FitText(
                        song.name,
                        textKey: PartsPage.titleKey,
                        minFontSize: 22,
                        style: const TextStyle(
                          fontFamily: MetraFonts.condensed,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Save / Discard with unsaved changes; their room is kept
            // either way, so the title never moves.
            AnimatedOpacity(
              opacity: changed ? 1 : 0,
              duration: MetraMotion.of(context, MetraMotion.controlsFade),
              child: IgnorePointer(
                ignoring: !changed,
                child: ExcludeSemantics(
                  excluding: !changed,
                  // Large text: the title keeps room (as the main screen's
                  // fixed controls, at most 1.3×).
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    // Narrow phones: shrinks rather than squeezing out the title.
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: bar.maxWidth * 0.6),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              key: PartsPage.discardKey,
                              style: TextButton.styleFrom(
                                foregroundColor: colors.muted,
                                minimumSize: const Size(48, 48),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              onPressed: changed
                                  ? () => _discard(context, song)
                                  : null,
                              child: const Text(
                                'Discard',
                                style: TextStyle(fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              height: 48,
                              child: Center(
                                child: FilledButton(
                                  key: PartsPage.saveKey,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: colors.text,
                                    foregroundColor: colors.background,
                                    minimumSize: const Size(64, 38),
                                    fixedSize: const Size.fromHeight(38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                  ),
                                  onPressed: changed
                                      ? () {
                                          Haptics.tick();
                                          _library.saveToSong(_metronome);
                                        }
                                      : null,
                                  child: const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The whole song to scale: blocks proportional to bars, a loop icon on
  /// the last when it loops; the playing part's block is filled (stopped,
  /// the open card's). Tap a block:
  /// its card opens and scrolls into view.
  Widget _strip(BuildContext context, List<SongPart> parts) {
    final colors = context.colors;
    final flexes = [for (final p in parts) p.bars];
    final sum = flexes.fold(0, (a, b) => a + b);
    final resize = MetraMotion.of(context, MetraMotion.cardExpand);
    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth - 3 * (parts.length - 1);
        // While blocks resize, their sum can pass the width for a moment:
        // clipped, not an overflow.
        return SizedBox(
          height: 48, // a 28px block in its 48dp touch row
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, part) in parts.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    // Lengths change smoothly (~180ms).
                    AnimatedContainer(
                      duration: resize,
                      curve: MetraMotion.cardCurve,
                      width: room * flexes[i] / sum,
                      child: Semantics(
                        button: true,
                        label: '${part.name}, ${partLine(part)}',
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: PartsPage.stripKey(i),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_openId != part.id) {
                              _open(part.id, scroll: true);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: _block(
                              context,
                              colors,
                              part,
                              // Playing: the part playing; stopped: the
                              // open card's.
                              selected: _playing != null
                                  ? _playing == i
                                  : part.id == _openId,
                              loops:
                                  i == parts.length - 1 &&
                                  _metronome.songEnd == SongEnd.loopLastPart,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _block(
    BuildContext context,
    MetraColors colors,
    SongPart part, {
    required bool selected,
    required bool loops,
  }) {
    final fill = selected ? colors.text : colors.tickResting;
    // The highlight cross-fades.
    return AnimatedContainer(
      duration: MetraMotion.of(context, MetraMotion.cardExpand),
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: fill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              part.name,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? colors.background : colors.muted,
              ),
            ),
          ),
          // The last part loops until you stop.
          if (loops) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.repeat,
              key: PartsPage.loopIconKey,
              size: 12,
              color: selected ? colors.background : colors.muted,
            ),
          ],
        ],
      ),
    );
  }

  Widget _list(BuildContext context, Song song, List<SongPart> parts) =>
      RowExitHost(
        child: ReorderableListView.builder(
          scrollController: _scroll,
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: parts.length,
          onReorderStart: (_) => Haptics.medium(),
          onReorderItem: (from, to) => _reorder(song, from, to),
          proxyDecorator: (child, _, animation) => _lifted(animation, child),
          footer: _footer(context, song, parts),
          itemBuilder: (context, i) {
            final part = parts[i];
            return KeyedSubtree(
              key: ValueKey(part.id),
              child: _Arrive(
                arriving: _arriving.remove(part.id),
                child: ExitShift(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SwipeRow(
                      index: i,
                      enabled: parts.length > 1,
                      label: 'Remove',
                      actionLabel: 'Remove part',
                      moreActions: {
                        if (i > 0) 'Move up': () => _reorder(song, i, i - 1),
                        if (i < parts.length - 1)
                          'Move down': () => _reorder(song, i, i + 1),
                      },
                      onSwiped: () => _remove(song, i),
                      child: _card(context, song, parts, i),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _card(BuildContext context, Song song, List<SongPart> parts, int i) {
    final colors = context.colors;
    final part = parts[i];
    final open = part.id == _openId;
    return Container(
      key: _cardKeys.putIfAbsent(part.id, GlobalKey.new),
      decoration: BoxDecoration(
        color: colors.sheet,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: open,
            // Only the header lifts the card to reorder; held on an open
            // card, it closes just before the lift (one gesture).
            child: HoldToReorder(
              index: i,
              child: Listener(
                onPointerDown: open ? (_) => _closeBeforeLift(part.id) : null,
                onPointerUp: (_) => _closing?.cancel(),
                onPointerCancel: (_) => _closing?.cancel(),
                // Playing, the header fills from the left across the part.
                child: CustomPaint(
                  key: PartsPage.fillKey(i),
                  painter: _playing == i
                      ? _ProgressFill(_progress, colors.selectedRow)
                      : null,
                  child: InkWell(
                    key: PartsPage.cardKey(i),
                    onTap: () => _open(part.id),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 60),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: colors.disabledText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    part.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    partLine(part),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            _tempo(colors, part),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // One height change (~180ms, ease-out); the body fades in, and
          // goes at once on closing.
          _Expand(
            instant: _snapClosed == part.id,
            child: open
                ? KeyedSubtree(
                    key: _bodyKeys.putIfAbsent(part.id, GlobalKey.new),
                    child: _FadeIn(child: _openCard(context, song, parts, i)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _barsStepper(
    int bars, {
    required String label,
    required void Function(SongPart Function(SongPart)) edit,
  }) => ValueStepper(
    compact: true,
    onSheet: true,
    label: label,
    display: bars == 1 ? '1 bar' : '$bars bars',
    editText: '$bars',
    onMinus: bars > SongPart.minBars
        ? () => edit(
            (p) => p.copyWith(
              bars: OnStart.stepDown(bars, OnStart.barsGrid, SongPart.minBars),
            ),
          )
        : null,
    onPlus: bars < SongPart.maxBars
        ? () => edit(
            (p) => p.copyWith(
              bars: OnStart.stepUp(bars, OnStart.barsGrid, SongPart.maxBars),
            ),
          )
        : null,
    onTyped: (text) {
      final v = int.tryParse(text);
      if (v == null) return;
      edit(
        (p) => p.copyWith(
          bars: OnStart.clampInt(v, SongPart.minBars, SongPart.maxBars),
        ),
      );
    },
  );

  /// Steady: a full-width 40px dashed "Gradual tempo change" that gives
  /// the part an end tempo.
  Widget _gradualButton(MetraColors colors, VoidCallback onTap) => InkWell(
    key: PartsPage.gradualKey,
    borderRadius: BorderRadius.circular(4),
    onTap: () {
      Haptics.tick();
      onTap();
    },
    // A 48dp touch row around the 40px dashed outline.
    child: SizedBox(
      height: 48,
      child: Center(
        child: SizedBox(
          height: 40,
          child: CustomPaint(
            painter: DashedOutline(colors.beatResting, radius: 4, width: 2),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.trending_up, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Gradual tempo change',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// "Ends at"'s ✕: back to one tempo. A 40px square outlined white.
  Widget _steadyButton(MetraColors colors, VoidCallback onTap) => Semantics(
    label: 'One tempo',
    button: true,
    excludeSemantics: true,
    // 40px drawn (the spec) in its 48dp touch target, which takes in the
    // small gap before −.
    child: Center(
      child: OutlinedButton(
        key: PartsPage.steadyKey,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(40, 40),
          fixedSize: const Size(40, 40),
          tapTargetSize: MaterialTapTargetSize.padded,
          foregroundColor: colors.text,
          side: BorderSide(color: colors.text, width: 2),
        ),
        onPressed: () {
          Haptics.tick();
          onTap();
        },
        child: const Icon(Icons.close, size: 20),
      ),
    ),
  );

  Widget _openCard(
    BuildContext context,
    Song song,
    List<SongPart> parts,
    int i,
  ) {
    final colors = context.colors;
    final part = parts[i];
    final gradual = part.gradual || _gradual.contains(part.id);
    void edit(SongPart Function(SongPart) change) => _edit(song, i, change);
    int bpm(int v) =>
        v.clamp(MetronomeController.minBpm, MetronomeController.maxBpm);
    Widget tempo(
      String label,
      int value,
      SongPart Function(int) set, {
      Widget? leading,
    }) => ValueStepper(
      compact: true,
      onSheet: true,
      label: label,
      leading: leading,
      display: '$value',
      editText: '$value',
      onMinus: value > MetronomeController.minBpm
          ? () => edit((_) => set(value - 1))
          : null,
      onPlus: value < MetronomeController.maxBpm
          ? () => edit((_) => set(value + 1))
          : null,
      onTyped: (text) {
        final v = int.tryParse(text);
        if (v != null) edit((_) => set(bpm(v)));
      },
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Name', style: TextStyle(fontSize: 15)),
              ),
              _nameMenu(
                context,
                part,
                (name) => edit((p) => p.copyWith(name: name)),
              ),
            ],
          ),
          // Two rows, one height in both states: only their words swap.
          if (gradual)
            tempo(
              'Starts at',
              part.tempoStart,
              (v) => part.copyWith(tempoStart: v),
            )
          else
            tempo(
              'BPM',
              part.tempoStart,
              (v) => part.copyWith(tempoStart: v, tempoEnd: v),
            ),
          BrightenSwap(
            value: gradual,
            // The taller of the two sets the height, so nothing moves.
            child: IndexedStack(
              index: gradual ? 1 : 0,
              alignment: Alignment.center,
              children: [
                _gradualButton(colors, () {
                  setState(() => _gradual.add(part.id));
                  // The end 10 above the start (below it near the top),
                  // so the change shows at once; the start stays.
                  edit((p) {
                    final up = p.tempoStart + 10;
                    return p.copyWith(
                      tempoEnd: up > MetronomeController.maxBpm
                          ? p.tempoStart - 10
                          : up,
                    );
                  });
                }),
                tempo(
                  'Ends at',
                  part.tempoEnd,
                  (v) => part.copyWith(tempoEnd: v),
                  leading: _steadyButton(colors, () {
                    setState(() => _gradual.remove(part.id));
                    edit((p) => p.copyWith(tempoEnd: p.tempoStart));
                  }),
                ),
              ],
            ),
          ),
          _barsStepper(part.bars, label: 'Length', edit: edit),
          Row(
            children: [
              const Expanded(
                child: Text('Rhythm', style: TextStyle(fontSize: 15)),
              ),
              OutlinedButton(
                key: PartsPage.rhythmKey,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: colors.border, width: 2),
                ),
                onPressed: () => _rhythm(context, song, i),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      part.pattern.timeSignature,
                      style: const TextStyle(
                        fontFamily: MetraFonts.condensed,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SubdivisionIcon(part.pattern.stepsPerBeat, size: 20),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: colors.disabledText,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _accents(colors, part.pattern, (beat) {
            Haptics.tick();
            edit((p) => p.copyWith(pattern: p.pattern.cycleBeat(beat)));
          }),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton.icon(
                key: PartsPage.playFromKey,
                style: TextButton.styleFrom(foregroundColor: colors.text),
                onPressed: () {
                  Haptics.medium();
                  _metronome.playFrom(i);
                },
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text(
                  'Play from here',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                key: PartsPage.duplicateKey,
                style: TextButton.styleFrom(foregroundColor: colors.muted),
                onPressed: () => _duplicate(song, i),
                child: const Text(
                  'Duplicate',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A lifted card: scaled to 1.02 with a shadow over ~100ms.
  Widget _lifted(Animation<double> animation, Widget child) => AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final colors = context.colors;
      final reduced = MetraMotion.reduced(context);
      final t = reduced
          ? 1.0
          : Curves.easeOut.transform(
              (animation.value * 250 / MetraMotion.lift.inMilliseconds).clamp(
                0.0,
                1.0,
              ),
            );
      return Transform.scale(
        scale: 1 + 0.02 * t,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(
                  colors.shadow.withAlpha(0),
                  colors.shadow,
                  t,
                )!,
                blurRadius: 16 * t,
                offset: Offset(0, 4 * t),
              ),
            ],
          ),
          child: child,
        ),
      );
    },
    child: Material(type: MaterialType.transparency, child: child),
  );

  /// "128", or "128 → 140" with a vector arrow.
  Widget _tempo(MetraColors colors, SongPart part) {
    const style = TextStyle(
      fontFamily: MetraFonts.condensed,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    );
    if (!part.gradual) return Text('${part.tempoStart}', style: style);
    return Semantics(
      label: '${part.tempoStart} to ${part.tempoEnd}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${part.tempoStart}', style: style),
          Icon(Icons.arrow_forward, size: 18, color: colors.muted),
          Text('${part.tempoEnd}', style: style),
        ],
      ),
    );
  }

  /// The part's beats: tap cycles accent → regular → muted, as on the main
  /// screen.
  Widget _accents(
    MetraColors colors,
    MetronomePattern pattern,
    ValueChanged<int> onTap,
  ) => Row(
    children: [
      for (final (beat, level) in pattern.beatLevels.indexed) ...[
        if (beat > 0) const SizedBox(width: 4),
        Expanded(
          child: Semantics(
            button: true,
            label:
                'Beat ${beat + 1}, ${switch (level) {
                  StepLevel.silent => 'muted',
                  StepLevel.accent => 'accented',
                  _ => 'regular',
                }}',
            onTapHint: 'change',
            excludeSemantics: true,
            child: GestureDetector(
              key: PartsPage.accentKey(beat),
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(beat),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Container(
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: switch (level) {
                      StepLevel.accent => colors.accentResting,
                      StepLevel.silent => colors.mutedFill,
                      _ => colors.beatResting,
                    },
                  ),
                  child: level == StepLevel.silent
                      ? CustomPaint(painter: MutedLine(colors.mutedLine))
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );

  Widget _nameMenu(
    BuildContext context,
    SongPart part,
    ValueChanged<String> onName,
  ) {
    final colors = context.colors;
    return PopupMenuButton<String>(
      key: PartsPage.partNameKey,
      tooltip: 'Part name',
      onSelected: (name) async {
        if (name != PartsPage.customName) return onName(name);
        final typed = await _askName(context, 'Part name', part.name);
        if (typed != null) onName(typed);
      },
      itemBuilder: (_) => [
        for (final name in [...partNames, PartsPage.customName])
          PopupMenuItem(value: name, child: Text(name)),
      ],
      child: _menuBox(colors, part.name),
    );
  }

  /// The look of a dropdown on this page (the part's Name, "When the song
  /// ends"): [text] and ⌄ in a 40px outline, in a 48dp row.
  Widget _menuBox(MetraColors colors, String text) => Container(
    constraints: const BoxConstraints(minWidth: 150, minHeight: 48),
    alignment: Alignment.center,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.controlOutline, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 100, maxWidth: 160),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.expand_more, size: 20, color: colors.muted),
        ],
      ),
    ),
  );

  static const _endNames = {
    SongEnd.stop: 'Stop',
    SongEnd.loopSong: 'Loop song',
    SongEnd.loopLastPart: 'Loop last part',
  };

  /// "+ Add part" (dashed) and "At the end" (when the song ends).
  Widget _footer(BuildContext context, Song song, List<SongPart> parts) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          painter: DashedOutline(colors.beatResting, radius: 8, width: 2),
          child: InkWell(
            key: PartsPage.addKey,
            borderRadius: BorderRadius.circular(8),
            onTap: () => _add(song),
            child: const SizedBox(
              height: 48,
              child: Center(
                child: Text(
                  '+ Add part',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          // One line at any text size: the label, then the current choice
          // as a dropdown like the part's Name.
          child: Row(
            children: [
              const Expanded(
                child: Text('At the end', style: TextStyle(fontSize: 15)),
              ),
              PopupMenuButton<SongEnd>(
                key: PartsPage.endKey,
                tooltip: 'At the end',
                onSelected: (end) => _set(parts, end: end),
                itemBuilder: (_) => [
                  for (final MapEntry(key: end, value: name)
                      in _endNames.entries)
                    CheckedPopupMenuItem(
                      value: end,
                      checked: end == _metronome.songEnd,
                      child: Text(name),
                    ),
                ],
                child: _menuBox(colors, _endNames[_metronome.songEnd]!),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _undoBar(BuildContext context, Song song, SongPart part) {
    final colors = context.colors;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.only(left: 16, right: 8),
        decoration: BoxDecoration(
          color: colors.divider,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Removed ${part.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colors.tickSounding),
              ),
            ),
            TextButton(
              key: PartsPage.undoKey,
              style: TextButton.styleFrom(foregroundColor: colors.text),
              onPressed: () => _undo(song),
              child: const Text(
                'Undo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Discard asks first: it throws away work (and isn't Undo).
  Future<void> _discard(BuildContext context, Song song) async {
    final sure = await confirmDelete(
      context,
      title: 'Discard changes to ${song.name}?',
      body: 'The song goes back to how it was last saved.',
      cancelLabel: 'Keep editing',
      confirmLabel: 'Discard',
    );
    if (!sure) return;
    _gradual.clear();
    _library.revertSong(_metronome);
  }

  /// Play / Stop, full width at the bottom, one size in both states: Play
  /// outlined, Stop filled like the main Start/Stop.
  Widget _playButton(BuildContext context) {
    final colors = context.colors;
    final playing = _metronome.isPlaying;
    const label = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
    void tap() {
      Haptics.medium();
      playing ? _metronome.stop() : _metronome.playFrom(0);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SizedBox(
        height: 56,
        child: playing
            ? FilledButton.icon(
                key: PartsPage.playKey,
                onPressed: tap,
                icon: const Icon(Icons.stop, size: 24),
                label: const Text('Stop', style: label),
              )
            : OutlinedButton.icon(
                key: PartsPage.playKey,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.text,
                  side: BorderSide(color: colors.text, width: 2),
                ),
                onPressed: tap,
                icon: const Icon(Icons.play_arrow, size: 24),
                label: const Text('Play', style: label),
              ),
      ),
    );
  }

  /// The Rhythm panel's controls for part [i], in a bottom sheet.
  Future<void> _rhythm(BuildContext context, Song song, int i) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.colors.sheet,
        builder: (_) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TimeSignatureSheet(
            rhythm: _PartRhythm(_metronome, () => _parts(song)[i], (p) {
              _edit(song, i, (_) => p);
            }),
          ),
        ),
      );

  Future<void> _rename(BuildContext context, Song song) async {
    final name = await _askName(
      context,
      'Song name',
      song.name,
      taken: (n) => _library.songNameTaken(n, exceptId: song.id),
    );
    if (name != null) _library.renameSong(song.id, name);
  }

  /// A name typed in a dialog, or null when cancelled.
  Future<String?> _askName(
    BuildContext context,
    String title,
    String initial, {
    bool Function(String)? taken,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial, taken: taken),
  );
}

/// The Rhythm panel's target for one part: edits go through the page.
class _PartRhythm implements RhythmTarget {
  _PartRhythm(this._metronome, this._part, this._set);

  final MetronomeController _metronome;
  final SongPart Function() _part;
  final ValueChanged<SongPart> _set;

  SongPart get _now => _part();

  @override
  MetronomePattern get pattern => _now.pattern;

  @override
  void setMeter(int beatsPerBar, int beatUnit) => _set(
    _now.copyWith(pattern: pattern.withBeats(beatsPerBar, beatUnit: beatUnit)),
  );

  @override
  void setSubdivision(int stepsPerBeat) =>
      _set(_now.copyWith(pattern: pattern.withSubdivision(stepsPerBeat)));

  @override
  void setPolyrhythm(int n) =>
      _set(_now.copyWith(pattern: pattern.withPolyrhythm(n)));

  @override
  void addListener(VoidCallback listener) => _metronome.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _metronome.removeListener(listener);
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial, this.taken});

  final String title;
  final String initial;
  final bool Function(String)? taken;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  String get _name => _field.text.trim();
  bool get _taken => widget.taken?.call(_name) ?? false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _field,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        errorText: _taken ? 'Another song has this name' : null,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _name.isEmpty || _taken ? null : _done,
        child: const Text('Done'),
      ),
    ],
  );

  void _done() {
    if (_name.isEmpty || _taken) return;
    Navigator.pop(context, _name);
  }
}

/// The Rhythm panel's last row (ui-spec.md "The parts page" → "Getting
/// there"): "Song parts ›" with the count, opening the parts page; in Free
/// play "Save as a song to add parts", which saves first. [opener] is the
/// main screen's context (the panel closes before the page opens).
class SongPartsRow extends StatelessWidget {
  const SongPartsRow({
    super.key,
    required this.library,
    required this.metronome,
    required this.opener,
  });

  final LibraryController library;
  final MetronomeController metronome;
  final BuildContext opener;

  static const rowKey = Key('song-parts-row');
  static const saveFirst = 'Save as a song to add parts';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final song = library.currentSong;
    final count = (metronome.parts ?? song?.parts ?? const []).length;
    return InkWell(
      key: rowKey,
      onTap: () async {
        TopPanel.close();
        if (library.currentSong == null &&
            !await showSaveAsNewSong(opener, library, metronome)) {
          return;
        }
        if (opener.mounted) await openPartsPage(opener, library, metronome);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                song == null ? saveFirst : 'Song parts',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (song != null)
              Text(
                count == 1 ? '1 part' : '$count parts',
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 22, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

/// A new card grows in (height and fade, ~200ms, "arrive").
class _Arrive extends StatelessWidget {
  const _Arrive({required this.arriving, required this.child});

  final bool arriving;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: arriving ? 0 : 1, end: 1),
    duration: MetraMotion.of(context, MetraMotion.arrive),
    curve: MetraMotion.arriveCurve,
    builder: (context, t, child) => t == 1
        ? child!
        : ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: t,
              child: Opacity(opacity: t, child: child),
            ),
          ),
    child: child,
  );
}

/// An opened card's body fades in, from ~40ms over 120ms.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = MetraMotion.cardFadeDelay + MetraMotion.cardFade;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MetraMotion.of(context, total),
      curve: Interval(
        MetraMotion.cardFadeDelay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOut,
      ),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}

/// A card's body opening or closing in one height change; with Remove
/// animations, at once.
class _Expand extends StatelessWidget {
  const _Expand({required this.child, this.instant = false});

  final Widget child;
  final bool instant;

  @override
  Widget build(BuildContext context) => instant || MetraMotion.reduced(context)
      ? child
      : AnimatedSize(
          duration: MetraMotion.cardExpand,
          curve: MetraMotion.cardCurve,
          alignment: Alignment.topCenter,
          child: child,
        );
}

/// The playing card's header filled from the left to [progress] (0–1).
/// Repaints with it; nothing is rebuilt.
class _ProgressFill extends CustomPainter {
  _ProgressFill(this.progress, this.color) : super(repaint: progress);

  final ValueListenable<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * progress.value, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProgressFill old) =>
      old.progress != progress || old.color != color;
}
