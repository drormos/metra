import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'library_pick.dart';
import 'play_marker.dart';
import 'song_editor.dart';
import 'theme.dart';

/// The setlist picker sheet (ui-spec.md "Setlist picker"): a set page that
/// both plays and edits a set, below a "What to play" top level for
/// switching sets or going to Free play. Opening it never touches the
/// click; only choosing a song or a set does.
///
/// Opens on the loaded set's page, else on What to play; with [newSet], on
/// the page of a new set (from "Create a setlist").
Future<void> showSetlistPicker(
  BuildContext context, {
  required LibraryController library,
  required MetronomeController metronome,
  bool newSet = false,
}) {
  final height = MediaQuery.sizeOf(context).height;
  final colors = context.colors;
  // Created up front: not while the sheet builds.
  final created = newSet
      ? library.addSetlist(library.newSetlistName()).id
      : null;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // The top ~104px of the main screen stays visible, dimmed.
    constraints: BoxConstraints(maxHeight: height - 104),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      side: BorderSide(color: colors.border),
    ),
    builder: (_) => SetlistPicker(
      library: library,
      metronome: metronome,
      newSetId: created,
    ),
  );
}

/// The picker's What to play view as a full screen (from Settings > Your
/// music > Setlists). Back leaves it; playing something closes it too.
Future<void> openSetlistsScreen(
  BuildContext context, {
  required LibraryController library,
  required MetronomeController metronome,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: context.colors.sheet,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SetlistPicker(
            library: library,
            metronome: metronome,
            fullScreen: true,
          ),
        ),
      ),
    ),
  ),
);

class SetlistPicker extends StatefulWidget {
  const SetlistPicker({
    super.key,
    required this.library,
    required this.metronome,
    this.fullScreen = false,
    this.newSetId,
  });

  final LibraryController library;
  final MetronomeController metronome;

  /// A full screen rather than a sheet: opens on What to play, whose back
  /// chevron leaves the screen.
  final bool fullScreen;

  /// Open on the page of this just-created set.
  final String? newSetId;

  static const backToSetlistsKey = Key('picker-back-to-setlists');
  static const freePlayKey = Key('picker-free-play');
  static const newSetlistKey = Key('picker-new-setlist');
  static const addSongsKey = Key('picker-add-songs');
  static const allSongsKey = Key('picker-all-songs');
  static const renameKey = Key('picker-rename');
  static const deleteKey = Key('picker-delete');
  static const removeKey = Key('picker-remove-marked');
  static const deleteMarkedKey = Key('picker-delete-marked');
  static const removeSongsKey = Key('picker-remove-songs');
  static const deleteSetsKey = Key('picker-delete-sets');
  static const cancelMarksKey = Key('picker-cancel-marks');
  static const titleFieldKey = Key('picker-title-field');

  @override
  State<SetlistPicker> createState() => _SetlistPickerState();
}

class _SetlistPickerState extends State<SetlistPicker> {
  // Navigation inside the picker: the set page shown, or null for What to
  // play. Everything else here is page UI state; the set itself is saved
  // in the library as it changes.
  late String? _pageId =
      widget.newSetId ??
      (widget.fullScreen ? null : widget.library.activeSetlist?.id);
  // The page is for a new set: its title starts as a field.
  bool _isNew = false;
  // A set created here, discarded if it's left with no songs.
  String? _createdId;
  bool _renaming = false;
  final _name = TextEditingController();
  final _search = TextEditingController();
  // "Remove songs" / "Delete setlists" marking, and what's marked (song
  // positions, since a song may appear twice; set ids).
  bool _markingSongs = false;
  bool _markingSets = false;
  final _marked = <int>{};
  // Sets marked for deleting in What to play.
  final _markedSets = <String>{};
  // The picker's own messenger, so the Undo bar shows inside the sheet.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  LibraryController get _library => widget.library;

  Setlist? get _page {
    for (final list in _library.setlists) {
      if (list.id == _pageId) return list;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final page = _page;
    if (widget.newSetId != null && page != null) {
      _isNew = true;
      _createdId = page.id;
      _startEditingName(page.name);
    }
  }

  @override
  void dispose() {
    // Not during dispose: deleting notifies listeners mid-teardown.
    final abandoned = _abandonedNewSet();
    if (abandoned != null) {
      scheduleMicrotask(() => _library.deleteSetlist(abandoned));
    }
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  /// The id of a set created here and being left empty: it's discarded.
  String? _abandonedNewSet() {
    final page = _page;
    return page != null && page.id == _createdId && page.songIds.isEmpty
        ? page.id
        : null;
  }

  void _openNewSet() {
    final created = _library.addSetlist(_library.newSetlistName());
    _pageId = created.id;
    _isNew = true;
    _createdId = created.id;
    _startEditingName(created.name);
  }

  void _startEditingName(String name) {
    _name
      ..text = name
      ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);
  }

  /// Saves a valid typed name; an empty or taken one keeps the old name.
  void _commitName() {
    final page = _page;
    if (page == null || !(_isNew || _renaming)) return;
    final name = _name.text.trim();
    if (name.isEmpty || _library.setlistNameTaken(name, exceptId: page.id)) {
      return;
    }
    if (name != page.name) _library.updateSetlist(page.copyWith(name: name));
    setState(() {
      _renaming = false;
      _isNew = false;
    });
  }

  String? get _nameError {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Give the set a name';
    return _library.setlistNameTaken(name, exceptId: _pageId)
        ? 'Another setlist already has this name'
        : null;
  }

  void _showWhatToPlay() {
    if (_isNew || _renaming) _commitName();
    final abandoned = _abandonedNewSet();
    if (abandoned != null) _library.deleteSetlist(abandoned);
    setState(() {
      _pageId = null;
      _isNew = false;
      _createdId = null; // kept now: only new sets are discarded
      _renaming = false;
      _endMarking();
    });
  }

  void _openPage(Setlist setlist) => setState(() {
    _pageId = setlist.id;
    _endMarking();
  });

  void _endMarking() {
    _markingSongs = false;
    _markingSets = false;
    _marked.clear();
    _markedSets.clear();
  }

  /// Closes the sheet (or the full screen from Settings).
  void _close() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) => PopScope(
    // The back gesture ends marking before it closes anything.
    canPop: !_markingSongs && !_markingSets,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(_endMarking);
    },
    child: ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        backgroundColor: context.colors.sheet,
        body: ListenableBuilder(
          listenable: _library,
          builder: (context, _) {
            final page = _page;
            return page == null ? _whatToPlayView(context) : _setPage(page);
          },
        ),
      ),
    ),
  );

  // Set page

  Widget _setPage(Setlist setlist) {
    final colors = context.colors;
    final songs = [for (final id in setlist.songIds) ?_library.songById(id)];
    final loaded = setlist.id == _library.activeSetlist?.id;
    final current = loaded ? _library.currentIndex : -1;
    final editingName = _isNew || _renaming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // "‹ Setlists" goes up a level; "Free play" leaves the set.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                key: SetlistPicker.backToSetlistsKey,
                style: TextButton.styleFrom(
                  foregroundColor: colors.text,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
                ),
                onPressed: _showWhatToPlay,
                icon: const Icon(Icons.chevron_left, size: 22),
                label: const Text(
                  'Setlists',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ),
              const Spacer(),
              FreePlayButton(library: _library, closes: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: editingName
              ? TextField(
                  key: SetlistPicker.titleFieldKey,
                  controller: _name,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _commitName(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    errorText: _nameError,
                    errorStyle: TextStyle(color: colors.accentSounding),
                  ),
                )
              : SizedBox(
                  height: 48,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      setlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            _count(songs.length),
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ),
        Divider(height: 1, color: colors.divider),
        Expanded(
          child: songs.isEmpty
              ? _emptyState(colors, setlist)
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: songs.length,
                  // Long-press and drag reorders; long-press does nothing
                  // else.
                  onReorderStart: (_) => Haptics.medium(),
                  onReorderItem: (from, to) {
                    _library.reorderSetlist(setlist.id, from, to);
                    _remapMarks(from, to);
                  },
                  footer: _pageFooter(colors, setlist),
                  itemBuilder: (context, i) =>
                      _row(colors, setlist, songs[i], i, current: i == current),
                ),
        ),
        if (_markingSongs)
          _markingBar(colors, setlist)
        else
          _bottomBar(colors, [
            Expanded(
              child: FilledButton.icon(
                key: SetlistPicker.addSongsKey,
                // The primary action while the set is empty.
                style: songs.isEmpty
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: colors.surface,
                        foregroundColor: colors.text,
                      ),
                onPressed: () => _addSongs(setlist),
                icon: const Icon(Icons.add, size: 20),
                label: const FittedBox(
                  child: Text('Add songs', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: SetlistPicker.removeSongsKey,
                onPressed: songs.isEmpty
                    ? null
                    : () => setState(() => _markingSongs = true),
                child: const FittedBox(
                  child: Text('Remove songs', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ]),
      ],
    );
  }

  Widget _emptyState(MetraColors colors, Setlist setlist) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
    children: [
      const Text(
        'No songs yet',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(
        'Add songs from your library, or create new ones as you go.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: colors.muted),
      ),
      if (_library.songs.isNotEmpty) ...[
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton(
            key: SetlistPicker.allSongsKey,
            // Every song in the library, A–Z, to trim down.
            onPressed: () => _library.updateSetlist(
              setlist.copyWith(
                songIds: [for (final song in _library.songsAZ) song.id],
              ),
            ),
            child: const Text('Start with all songs'),
          ),
        ),
      ],
      if (!_isNew) _pageFooter(colors, setlist),
    ],
  );

  /// After the last row, so it's never in the way on stage.
  Widget _pageFooter(MetraColors colors, Setlist setlist) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      children: [
        if (!_isNew)
          TextButton(
            key: SetlistPicker.renameKey,
            style: TextButton.styleFrom(
              foregroundColor: colors.muted,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => setState(() {
              _renaming = true;
              _startEditingName(setlist.name);
            }),
            child: const Text('Rename setlist', style: TextStyle(fontSize: 15)),
          ),
        TextButton(
          key: SetlistPicker.deleteKey,
          style: TextButton.styleFrom(
            foregroundColor: colors.accentSounding,
            minimumSize: const Size(0, 44),
          ),
          onPressed: () => _delete(setlist),
          child: const Text('Delete setlist', style: TextStyle(fontSize: 15)),
        ),
      ],
    ),
  );

  Widget _row(
    MetraColors colors,
    Setlist setlist,
    Song song,
    int index, {
    required bool current,
  }) {
    final marking = _markingSongs;
    final marked = _marked.contains(index);
    final highlighted = marking ? marked : current;
    return _QuickDragStartListener(
      // Keyed by position: the same song may appear twice.
      key: ValueKey('picker-row-$index-${song.id}'),
      index: index,
      child: Material(
        color: highlighted ? colors.selectedRow : colors.sheet,
        child: InkWell(
          key: ValueKey('picker-song-$index'),
          onTap: marking
              ? () => _toggleMark(index)
              : () => _play(setlist, song, index),
          child: Ink(
            height: 60,
            padding: const EdgeInsets.only(left: 24),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: marking
                      ? MarkCircle(checked: marked)
                      : PlayMarker(current: current),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${song.bpm}',
                  style: TextStyle(
                    fontFamily: MetraFonts.condensed,
                    fontSize: 24,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 30,
                  child: Text(
                    song.pattern.timeSignature,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 14, color: colors.muted),
                  ),
                ),
                // Hidden while marking; the slot keeps the layout.
                SizedBox(
                  width: 52,
                  height: 60,
                  child: marking
                      ? null
                      : IconButton(
                          key: ValueKey('picker-edit-$index'),
                          tooltip: 'Edit ${song.name}',
                          color: colors.muted,
                          onPressed: () => openSongEditor(
                            context,
                            _library,
                            widget.metronome,
                            song: song,
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Loads the song (and this set, if it isn't the loaded one) with the
  /// next/previous rules, then closes.
  void _play(Setlist setlist, Song song, int index) {
    Haptics.medium(); // the song changed
    if (setlist.id != _library.activeSetlist?.id) {
      _library.setActiveSetlist(setlist.id);
    }
    _library.playSong(song, widget.metronome, index: index);
    _close();
  }

  void _toggleMark(int index) {
    Haptics.tick();
    setState(
      () =>
          _marked.contains(index) ? _marked.remove(index) : _marked.add(index),
    );
  }

  /// Marks follow their rows when a row is dragged.
  void _remapMarks(int from, int to) {
    if (_marked.isEmpty) return;
    final order = [for (var i = 0; i <= max(from, to); i++) i];
    order.insert(to, order.removeAt(from));
    setState(() {
      final moved = {
        for (final m in _marked) m > max(from, to) ? m : order.indexOf(m),
      };
      _marked
        ..clear()
        ..addAll(moved);
    });
  }

  Widget _markingBar(MetraColors colors, Setlist setlist) => _selectionBar(
    colors,
    count: _marked.length,
    action: 'Remove',
    actionKey: SetlistPicker.removeKey,
    onAction: () => _remove(setlist, {..._marked}),
    onCancel: () => setState(_endMarking),
  );

  /// "N selected · Cancel" and a red [action], replacing the bottom buttons
  /// while rows are marked.
  Widget _selectionBar(
    MetraColors colors, {
    required int count,
    required String action,
    required Key actionKey,
    required VoidCallback onAction,
    required VoidCallback onCancel,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.divider)),
    ),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count selected',
              style: TextStyle(fontSize: 15, color: colors.muted),
            ),
          ),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              key: SetlistPicker.cancelMarksKey,
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: TextButton(
              key: actionKey,
              style: TextButton.styleFrom(
                foregroundColor: colors.accentSounding,
                minimumSize: const Size(0, 44),
              ),
              onPressed: count == 0 ? null : onAction,
              // Shrinks rather than overflowing on narrow phones.
              child: FittedBox(
                child: Text(
                  action,
                  style: const TextStyle(
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
  );

  /// Out of this set only (the songs stay in the library); Undo for ~5 s.
  void _remove(Setlist setlist, Set<int> indices) {
    final before = _library.removeEntries(setlist.id, indices);
    setState(_endMarking);
    _messenger.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            indices.length == 1 ? 'Removed' : '${indices.length} removed',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _library.updateSetlist(before),
          ),
        ),
      );
  }

  Future<void> _addSongs(Setlist setlist) async {
    final ids = await pickSongs(
      context,
      _library,
      setName: setlist.name,
      inSet: setlist.songIds.toSet(),
      newSong: (context) async =>
          (await openSongEditor(context, _library, widget.metronome))?.id,
    );
    final latest = _page;
    if (ids == null || ids.isEmpty || latest == null) return;
    _library.updateSetlist(
      latest.copyWith(songIds: [...latest.songIds, ...ids]),
    );
  }

  Future<void> _delete(Setlist setlist) async {
    final ok = await confirm(
      context,
      'Delete “${setlist.name}”? Its songs stay in your library.',
      'Delete',
    );
    if (!ok || !mounted) return;
    _library.deleteSetlist(setlist.id);
    setState(() {
      _pageId = null;
      _isNew = false;
      _renaming = false;
    });
  }

  // What to play view

  /// The picker's top level: no back, except full screen from Settings,
  /// where ‹ returns there.
  Widget _whatToPlayView(BuildContext context) {
    final colors = context.colors;
    final query = _search.text.trim().toLowerCase();
    final sets = [
      for (final set in _library.setlistsRecentlyPlayed)
        if (query.isEmpty || set.name.toLowerCase().contains(query)) set,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(widget.fullScreen ? 12 : 24, 0, 24, 12),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                if (widget.fullScreen)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: _close,
                    icon: const Icon(Icons.chevron_left, size: 28),
                  ),
                const Text(
                  'What to play',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        // A mode, not a setlist: framed and set apart from the list.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: SizedBox(
            height: 72,
            child: OutlinedButton(
              key: SetlistPicker.freePlayKey,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () {
                // Detaches any song; the click keeps going as it is.
                Haptics.medium();
                _library.detachSong();
                _close();
              },
              child: Row(
                children: [
                  const _MetronomeIcon(),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Free play',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'No setlist, any tempo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Setlists',
                  style: TextStyle(fontSize: 14, color: colors.muted),
                ),
              ),
              Text(
                'Recently played',
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: SearchField(
            controller: _search,
            hint: 'Search setlists',
            onChanged: (_) => setState(() {}),
          ),
        ),
        Divider(height: 1, color: colors.divider),
        Expanded(
          child: ListView(
            children: [for (final setlist in sets) _setRow(colors, setlist)],
          ),
        ),
        if (_markingSets)
          _selectionBar(
            colors,
            count: _markedSets.length,
            action: 'Delete',
            actionKey: SetlistPicker.deleteMarkedKey,
            onAction: () => _deleteSets({..._markedSets}),
            onCancel: () => setState(_endMarking),
          )
        else
          _bottomBar(colors, [
            Expanded(
              child: FilledButton.icon(
                key: SetlistPicker.newSetlistKey,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.surface,
                  foregroundColor: colors.text,
                ),
                onPressed: () => setState(_openNewSet),
                icon: const Icon(Icons.add, size: 20),
                label: const FittedBox(
                  child: Text('New setlist', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: SetlistPicker.deleteSetsKey,
                onPressed: _library.setlists.isEmpty
                    ? null
                    : () => setState(() => _markingSets = true),
                child: const FittedBox(
                  child: Text(
                    'Delete setlists',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ),
            ),
          ]),
      ],
    );
  }

  /// Tap = load the set at song 1 and close (every row, the loaded one
  /// too); the pencil opens its page without loading it. While "Delete
  /// setlists" is marking, a tap marks instead.
  Widget _setRow(MetraColors colors, Setlist setlist) {
    final marking = _markingSets;
    final marked = _markedSets.contains(setlist.id);
    return Material(
      key: ValueKey('picker-set-row-${setlist.id}'),
      color: marked ? colors.selectedRow : colors.sheet,
      child: InkWell(
        key: ValueKey('picker-set-${setlist.id}'),
        onTap: marking
            ? () => _toggleSetMark(setlist.id)
            : () {
                Haptics.medium(); // the set (and song) changes
                _library.loadSetlist(setlist.id, widget.metronome);
                _close();
              },
        child: Ink(
          height: 64,
          padding: const EdgeInsets.only(left: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: marking
                    ? MarkCircle(checked: marked)
                    : Icon(Icons.notes, size: 18, color: colors.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      setlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _count(setlist.songIds.length),
                      style: TextStyle(fontSize: 13, color: colors.muted),
                    ),
                  ],
                ),
              ),
              // Hidden while marking; the slot keeps the layout.
              SizedBox(
                width: 52,
                height: 64,
                child: marking
                    ? null
                    : IconButton(
                        key: ValueKey('picker-set-edit-${setlist.id}'),
                        tooltip: 'Open ${setlist.name}',
                        color: colors.muted,
                        onPressed: () => _openPage(setlist),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSetMark(String id) {
    Haptics.tick();
    setState(
      () => _markedSets.contains(id)
          ? _markedSets.remove(id)
          : _markedSets.add(id),
    );
  }

  /// Asks first; never deletes songs. Deleting the loaded set switches to
  /// Free play. Returns whether the sets were deleted.
  Future<bool> _deleteSets(Set<String> ids) async {
    final names = [
      for (final set in _library.setlists)
        if (ids.contains(set.id)) set.name,
    ];
    final ok = await confirm(
      context,
      names.length == 1
          ? 'Delete ${names.single}? The songs stay in your library.'
          : 'Delete ${names.length} setlists? The songs stay in your library.',
      'Delete',
    );
    if (!ok || !mounted) return false;
    _library.deleteSetlists(ids);
    setState(_endMarking);
    return true;
  }

  // Shared pieces

  Widget _bottomBar(MetraColors colors, List<Widget> buttons) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.divider)),
    ),
    child: SizedBox(height: 56, child: Row(children: buttons)),
  );

  static String _count(int n) => n == 1 ? '1 song' : '$n songs';
}

/// The Free play icon from set-switcher.reference.html: a metronome body
/// with its pendulum.
class _MetronomeIcon extends StatelessWidget {
  const _MetronomeIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(26, 26),
    painter: _MetronomePainter(IconTheme.of(context).color!),
  );
}

class _MetronomePainter extends CustomPainter {
  _MetronomePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 26, size.height / 26);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(9, 3)
          ..lineTo(17, 3)
          ..lineTo(22, 23)
          ..lineTo(4, 23)
          ..close(),
        stroke,
      )
      ..drawLine(const Offset(13, 19), const Offset(18, 6), stroke)
      ..drawLine(const Offset(8, 19), const Offset(18, 19), stroke);
  }

  @override
  bool shouldRepaint(_MetronomePainter old) => old.color != color;
}

/// "Free play" (ui-spec.md "Detaching a song"): detaches the song and any
/// setlist, keeping the click as it sounds; [closes] also closes the
/// sheet or screen it sits on.
class FreePlayButton extends StatelessWidget {
  const FreePlayButton({super.key, required this.library, this.closes = false});

  static const buttonKey = Key('free-play-button');

  final LibraryController library;
  final bool closes;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: OutlinedButton(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: const Size(0, 40),
      ),
      onPressed: () {
        Haptics.medium(); // the song detached
        library.detachSong();
        if (closes) Navigator.pop(context);
      },
      child: const Text(
        'Free play',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    ),
  );
}

/// Long-press to lift a song row, a little quicker than the platform's
/// long-press (500 ms) so reordering feels responsive.
class _QuickDragStartListener extends ReorderableDelayedDragStartListener {
  const _QuickDragStartListener({
    super.key,
    required super.child,
    required super.index,
  });

  static const delay = Duration(milliseconds: 300);

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(debugOwner: this, delay: delay);
}
