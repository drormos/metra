import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../controller/rhythm_target.dart';
import '../model/library.dart';
import '../model/metronome_pattern.dart';
import '../model/on_start.dart';
import 'beat_indicator.dart' show MutedLine;
import 'choices.dart';
import 'dashed_outline.dart';
import 'editor_scaffold.dart' show confirmDelete;
import 'haptics.dart';
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
  static const lengthKindKey = Key('parts-length-kind');
  static const tempoKindKey = Key('parts-tempo-kind');
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

  /// What an open part that stops being the last one gets.
  static const defaultBars = 8;

  static const customName = 'Custom name…';

  @override
  State<PartsPage> createState() => _PartsPageState();
}

class _PartsPageState extends State<PartsPage> {
  LibraryController get _library => widget.library;
  MetronomeController get _metronome => widget.metronome;

  String? _openId;
  // Parts the user set to Gradual whose ends are (still) equal: the chips
  // stay on Gradual while From and To pass each other.
  final _gradual = <String>{};
  final _cardKeys = <String, GlobalKey>{};
  ({SongPart part, int index})? _removed;
  Timer? _undoTimer;
  int _idCounter = 0;
  // The card of the part playing, checked while playing (a part change
  // with the same tempo and pattern notifies nothing).
  Timer? _follow;
  int? _playing;

  @override
  void initState() {
    super.initState();
    _metronome.addListener(_onMetronome);
    _onMetronome();
  }

  @override
  void dispose() {
    _metronome.removeListener(_onMetronome);
    _undoTimer?.cancel();
    _follow?.cancel();
    _closing?.cancel();
    super.dispose();
  }

  void _onMetronome() {
    if (_metronome.isPlaying) {
      _follow ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _checkPlaying(),
      );
    } else {
      _follow?.cancel();
      _follow = null;
    }
    _checkPlaying();
  }

  void _checkPlaying() {
    final at = _metronome.isPlaying
        ? (_metronome.partPosition?.part ?? 0)
        : null;
    if (at != _playing && mounted) setState(() => _playing = at);
  }

  /// The loaded song's parts as they play now: a plain one-part song's
  /// one part from the click itself.
  List<SongPart> _parts(Song song) =>
      _metronome.parts ??
      [
        SongPart.steady(
          id: song.parts.first.id,
          name: song.parts.first.name,
          bars: null,
          bpm: _metronome.startBpm,
          pattern: _metronome.pattern,
        ),
      ];

  SongEnd get _end =>
      _metronome.parts == null ? SongEnd.stop : _metronome.songEnd;

  /// Applies [parts]: only the last part may run until you stop (an earlier
  /// open one gets [PartsPage.defaultBars]), and an open part is steady.
  void _set(List<SongPart> parts, {SongEnd? end}) {
    _metronome.setParts([
      for (final (i, p) in parts.indexed)
        p.open && i < parts.length - 1
            ? p.copyWith(bars: PartsPage.defaultBars)
            : p.open
            ? p.copyWith(tempoEnd: p.tempoStart)
            : p,
    ], end: end);
  }

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

  void _closeBeforeLift(String id) {
    _heldClosed = false;
    _closing?.cancel();
    _closing = Timer(
      RowGestures.liftPress - const Duration(milliseconds: 40),
      () {
        if (mounted && _openId == id) {
          _heldClosed = true;
          setState(() => _openId = null);
        }
      },
    );
  }

  void _open(String id, {bool scroll = false}) {
    if (_heldClosed) {
      _heldClosed = false;
      return;
    }
    setState(() => _openId = _openId == id ? null : id);
    if (scroll && _openId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _cardKeys[id]?.currentContext;
        if (context != null && context.mounted) {
          Scrollable.ensureVisible(
            context,
            duration: MetraMotion.reduced(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
          );
        }
      });
    }
  }

  void _add(Song song) {
    final parts = _parts(song);
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
    _set([...parts, added]);
    _open(added.id, scroll: true);
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
    _set([...parts]..insert(i + 1, copy));
    _open(copy.id, scroll: true);
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          partsSummary(parts),
                          key: PartsPage.summaryKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Save / Discard with unsaved changes; their room is kept
            // either way, so the title never moves.
            Visibility(
              visible: changed,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
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
                            padding: const EdgeInsets.symmetric(horizontal: 10),
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
          ],
        ),
      ),
    );
  }

  /// The whole song to scale: blocks proportional to bars (an open part a
  /// fading block with "∞"); the open card's block is filled. Tap a block:
  /// its card opens and scrolls into view.
  Widget _strip(BuildContext context, List<SongPart> parts) {
    final colors = context.colors;
    final closed = [for (final p in parts) ?p.bars];
    final average = closed.isEmpty
        ? 8
        : (closed.reduce((a, b) => a + b) / closed.length).ceil();
    return Row(
      children: [
        for (final (i, part) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            flex: part.bars ?? average,
            child: Semantics(
              button: true,
              label: '${part.name}, ${partLine(part)}',
              excludeSemantics: true,
              child: GestureDetector(
                key: PartsPage.stripKey(i),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_openId != part.id) _open(part.id, scroll: true);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: _block(colors, part, selected: part.id == _openId),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _block(MetraColors colors, SongPart part, {required bool selected}) {
    final fill = selected ? colors.text : colors.tickResting;
    return Container(
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: part.open ? null : fill,
        gradient: part.open
            ? LinearGradient(
                colors: [fill, fill, fill.withAlpha(0)],
                stops: const [0, 0.55, 1],
              )
            : null,
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
          // An open part runs until you stop.
          if (part.open) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.all_inclusive,
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
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: parts.length,
          onReorderStart: (_) => Haptics.medium(),
          onReorderItem: (from, to) => _reorder(song, from, to),
          proxyDecorator: (child, _, _) =>
              Material(type: MaterialType.transparency, child: child),
          footer: _footer(context, song, parts),
          itemBuilder: (context, i) {
            final part = parts[i];
            return KeyedSubtree(
              key: ValueKey(part.id),
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
        color: _playing == i ? colors.selectedRow : colors.sheet,
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
          if (open) _openCard(context, song, parts, i),
        ],
      ),
    );
  }

  Widget _openCard(
    BuildContext context,
    Song song,
    List<SongPart> parts,
    int i,
  ) {
    final colors = context.colors;
    final part = parts[i];
    final last = i == parts.length - 1;
    final gradual = part.gradual || _gradual.contains(part.id);
    void edit(SongPart Function(SongPart) change) => _edit(song, i, change);
    int bpm(int v) =>
        v.clamp(MetronomeController.minBpm, MetronomeController.maxBpm);
    Widget tempo(String label, int value, SongPart Function(int) set) =>
        ValueStepper(
          label: label,
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
          if (!part.open)
            Choices<bool>(
              key: PartsPage.tempoKindKey,
              label: 'Tempo',
              options: const {false: 'Steady', true: 'Gradual'},
              selected: gradual,
              onSelected: (on) {
                setState(
                  () => on ? _gradual.add(part.id) : _gradual.remove(part.id),
                );
                edit((p) {
                  if (!on) return p.copyWith(tempoEnd: p.tempoStart);
                  // From the previous part's tempo, to this one's.
                  final from = i > 0 ? parts[i - 1].tempoEnd : p.tempoStart;
                  var to = p.tempoStart;
                  if (to == from) {
                    to = from + 10 > MetronomeController.maxBpm
                        ? from - 10
                        : from + 10;
                  }
                  return p.copyWith(tempoStart: from, tempoEnd: to);
                });
              },
            ),
          if (gradual && !part.open) ...[
            tempo('From', part.tempoStart, (v) => part.copyWith(tempoStart: v)),
            tempo('To', part.tempoEnd, (v) => part.copyWith(tempoEnd: v)),
          ] else
            tempo(
              'BPM',
              part.tempoStart,
              (v) => part.copyWith(tempoStart: v, tempoEnd: v),
            ),
          if (last)
            Choices<bool>(
              key: PartsPage.lengthKindKey,
              label: 'Length',
              options: const {false: 'Bars', true: 'Until you stop'},
              selected: part.open,
              onSelected: (open) => edit(
                (p) => open
                    ? p.copyWith(bars: null, tempoEnd: p.tempoStart)
                    : p.copyWith(bars: PartsPage.defaultBars),
              ),
            ),
          if (part.bars case final bars?)
            ValueStepper(
              label: last ? 'Bars' : 'Length',
              display: bars == 1 ? '1 bar' : '$bars bars',
              editText: '$bars',
              onMinus: bars > SongPart.minBars
                  ? () => edit(
                      (p) => p.copyWith(
                        bars: OnStart.stepDown(
                          bars,
                          OnStart.barsGrid,
                          SongPart.minBars,
                        ),
                      ),
                    )
                  : null,
              onPlus: bars < SongPart.maxBars
                  ? () => edit(
                      (p) => p.copyWith(
                        bars: OnStart.stepUp(
                          bars,
                          OnStart.barsGrid,
                          SongPart.maxBars,
                        ),
                      ),
                    )
                  : null,
              onTyped: (text) {
                final v = int.tryParse(text);
                if (v == null) return;
                edit(
                  (p) => p.copyWith(
                    bars: OnStart.clampInt(
                      v,
                      SongPart.minBars,
                      SongPart.maxBars,
                    ),
                  ),
                );
              },
            ),
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
      child: Container(
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
                  part.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.expand_more, size: 20, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }

  /// "+ Add part" (dashed) and "When the song ends" (not when the last part
  /// runs until you stop).
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
        if (!parts.last.open)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Choices<SongEnd>(
              key: PartsPage.endKey,
              label: 'When the song ends',
              options: const {SongEnd.stop: 'Stop', SongEnd.loop: 'Loop'},
              selected: _end,
              onSelected: (end) => _set(parts, end: end),
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
