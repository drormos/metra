import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'icons.dart';
import 'library_pick.dart';
import 'play_marker.dart';
import 'song_editor.dart';
import 'theme.dart';

/// The setlist pages (ui-spec.md "Setlists"): What to play, the top
/// level for switching sets or going to Free play, and below it a set's
/// page, which both plays and edits the set. Full screen; opening them
/// never touches the click, only choosing a song or a set does.
///
/// Opens on What to play; back steps set page → What to play → where it
/// was opened from (Menu or main screen). With [setId] (long-press in the
/// Setlists dropdown), opens on that set's page alone: back returns
/// straight to the main screen. With [newSet], on a new set's page, What
/// to play behind it.
Future<void> openSetlists(
  BuildContext context, {
  required LibraryController library,
  required MetronomeController metronome,
  String? setId,
  bool newSet = false,
}) {
  // Created up front: creating it while the page builds would notify
  // the library's listeners mid-build.
  final created = newSet ? library.addSetlist(library.newSetlistName()) : null;
  return Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SetlistPicker(
        library: library,
        metronome: metronome,
        setId: setId,
        newSetId: created?.id,
      ),
    ),
  );
}

class SetlistPicker extends StatefulWidget {
  const SetlistPicker({
    super.key,
    required this.library,
    required this.metronome,
    this.setId,
    this.newSetId,
  });

  final LibraryController library;
  final MetronomeController metronome;

  /// Opens on this set's page alone, rather than What to play.
  final String? setId;

  /// Opens on the page of this just-created set, What to play behind it.
  final String? newSetId;

  static const backToSetlistsKey = Key('picker-back-to-setlists');
  static const freePlayKey = Key('picker-free-play');
  static const newSetlistKey = Key('picker-new-setlist');
  static const addSongsKey = Key('picker-add-songs');
  static const emptyActionKey = Key('picker-empty-action');
  static const renameKey = Key('picker-rename');
  static const deleteKey = Key('picker-delete');
  static const removeKey = Key('picker-remove-marked');
  static const deleteMarkedKey = Key('picker-delete-marked');
  static const removeSongsKey = Key('picker-remove-songs');
  static const deleteSetsKey = Key('picker-delete-sets');
  static const cancelMarksKey = SelectionBar.cancelKey;
  static const titleFieldKey = Key('picker-title-field');

  @override
  State<SetlistPicker> createState() => _SetlistPickerState();
}

class _SetlistPickerState extends State<SetlistPicker> {
  // Navigation inside the picker: the set page shown, or null for What to
  // play. Everything else here is page UI state; the set itself is saved
  // in the library as it changes.
  late String? _pageId = widget.setId;
  // Opened on a set's page with no What to play behind it: back leaves.
  late bool _alone = widget.setId != null;
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
  // The picker's own messenger, so the Undo bar shows on this page.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  LibraryController get _library => widget.library;

  Setlist? get _page {
    for (final list in _library.setlists) {
      if (list.id == _pageId) return list;
    }
    return null;
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

  @override
  void initState() {
    super.initState();
    final id = widget.newSetId;
    if (id != null) _showNew(_library.setlists.firstWhere((l) => l.id == id));
  }

  void _openNewSet() =>
      _showNew(_library.addSetlist(_library.newSetlistName()));

  void _showNew(Setlist created) {
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
      _alone = false;
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

  bool get _keyboardUp => MediaQuery.viewInsetsOf(context).bottom > 0;

  void _endMarking() {
    _markingSongs = false;
    _markingSets = false;
    _marked.clear();
    _markedSets.clear();
  }

  /// After loading something: always back on the main screen, closing
  /// Settings too when opened from there.
  void _close() => Navigator.popUntil(context, (route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final marking = _markingSongs || _markingSets;
    return PopScope(
      // Back ends marking first, then steps from a set's page to What to
      // play, and only then leaves.
      canPop: !marking && (_page == null || _alone),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (marking) {
          setState(_endMarking);
        } else {
          _showWhatToPlay();
        }
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          body: SafeArea(
            child: ListenableBuilder(
              listenable: _library,
              builder: (context, _) {
                final page = _page;
                return page == null ? _whatToPlayView(context) : _setPage(page);
              },
            ),
          ),
        ),
      ),
    );
  }

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
              : CustomScrollView(
                  slivers: [
                    // Dashed slots behind the rows show only where a gap
                    // opens: the drop slot while a row is dragged.
                    DecoratedSliver(
                      decoration: _DropSlots(colors.slot),
                      sliver: SliverReorderableList(
                        itemCount: songs.length,
                        // Long-press and drag reorders; long-press does
                        // nothing else.
                        onReorderStart: (_) => Haptics.medium(),
                        onReorderEnd: (_) => Haptics.tick(), // settles
                        onReorderItem: (from, to) {
                          _library.reorderSetlist(setlist.id, from, to);
                          _remapMarks(from, to);
                        },
                        proxyDecorator: _liftedRow,
                        itemBuilder: (context, i) => _row(
                          colors,
                          setlist,
                          songs[i],
                          i,
                          current: i == current,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(child: _pageFooter(colors, setlist)),
                  ],
                ),
        ),
        // The keyboard (naming the set) leaves no room for the buttons.
        // Hidden while the set is empty: its action is in the middle.
        if (_keyboardUp || songs.isEmpty)
          const SizedBox.shrink()
        else if (_markingSongs)
          _markingBar(colors, setlist)
        else
          BottomBar(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: SetlistPicker.addSongsKey,
                  style: FilledButton.styleFrom(
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
                  onPressed: () => setState(() => _markingSongs = true),
                  child: const FittedBox(
                    child: Text('Remove songs', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// "Add songs" in the middle; "New song" if the library is empty too.
  Widget _emptyState(MetraColors colors, Setlist setlist) {
    final noLibrary = _library.songs.isEmpty;
    return EmptyListState(
      title: 'No songs yet',
      hint: noLibrary
          ? 'Create the first song. It goes into your library and this set.'
          : 'Pick songs from your library. You can reorder them later.',
      action: noLibrary ? 'New song' : 'Add songs',
      actionKey: SetlistPicker.emptyActionKey,
      onAction: noLibrary
          ? () => _newSongInto(setlist)
          : () => _addSongs(setlist),
      below: _isNew ? null : _pageFooter(colors, setlist),
    );
  }

  /// Creates a song and adds it to [setlist].
  Future<void> _newSongInto(Setlist setlist) async {
    final song = await openSongEditor(context, _library, widget.metronome);
    final latest = _page;
    if (song == null || latest == null) return;
    _library.updateSetlist(
      latest.copyWith(songIds: [...latest.songIds, song.id]),
    );
  }

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
      child: Builder(
        builder: (context) => Material(
          color: _LiftedRow.of(context)
              ? colors.lifted
              : highlighted
              ? colors.selectedRow
              : colors.background,
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
      ),
    );
  }

  /// The row while dragged (setlist-drag.reference.html): picked up for
  /// the whole drag, with an outline, a deep shadow and ~103% scale.
  Widget _liftedRow(Widget child, int index, Animation<double> animation) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Transform.scale(
        scale: 1 + 0.03 * Curves.easeOut.transform(animation.value),
        child: child,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.text, width: 2),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              offset: const Offset(0, 10),
              blurRadius: 28,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _LiftedRow(child: child),
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

  Widget _markingBar(MetraColors colors, Setlist setlist) => SelectionBar(
    count: _marked.length,
    action: 'Remove',
    actionKey: SetlistPicker.removeKey,
    onAction: () => _remove(setlist, {..._marked}),
    onCancel: () => setState(_endMarking),
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
      _alone = false;
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
    // ‹ leaves for wherever this was opened from; nothing was loaded.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BackBar(title: 'What to play', centered: true),
        Expanded(
          // Free play scrolls with the list, so the search still fits when
          // the keyboard is up.
          child: ListView(
            children: [
              // A mode, not a setlist: framed and set apart from the list.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
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
                        const MetronomeIcon(),
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
              if (_library.setlists.isEmpty)
                EmptyListState(
                  title: 'No setlists yet',
                  hint: 'A setlist keeps songs in the order you play them.',
                  action: 'New setlist',
                  actionKey: SetlistPicker.emptyActionKey,
                  onAction: () => setState(_openNewSet),
                )
              else ...[
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
                for (final setlist in sets) _setRow(colors, setlist),
              ],
            ],
          ),
        ),
        // Hidden with no sets: "New setlist" is in the middle.
        if (_keyboardUp || _library.setlists.isEmpty)
          const SizedBox.shrink()
        else if (_markingSets)
          SelectionBar(
            count: _markedSets.length,
            action: 'Delete',
            actionKey: SetlistPicker.deleteMarkedKey,
            onAction: () => _deleteSets({..._markedSets}),
            onCancel: () => setState(_endMarking),
          )
        else
          BottomBar(
            children: [
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
                  onPressed: () => setState(() => _markingSets = true),
                  child: const FittedBox(
                    child: Text(
                      'Delete setlists',
                      style: TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
      color: marked ? colors.selectedRow : colors.background,
      child: InkWell(
        key: ValueKey('picker-set-${setlist.id}'),
        // Long-press = the pencil (Long-press rule); nothing while marking.
        onLongPress: marking
            ? null
            : () {
                Haptics.medium();
                _openPage(setlist);
              },
        enableFeedback: false, // Our own haptic, gated by the setting.
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
                    : SetlistIcon(color: colors.muted),
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

  static String _count(int n) => n == 1 ? '1 song' : '$n songs';
}

/// Tells a song row it's the dragged copy, so it paints the lifted color.
class _LiftedRow extends InheritedWidget {
  const _LiftedRow({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiftedRow>() != null;

  @override
  bool updateShouldNotify(_LiftedRow old) => false;
}

/// A dashed slot behind every 60px row of a set's page. The rows cover
/// them, so one shows only where a dragged row will land.
class _DropSlots extends Decoration {
  const _DropSlots(this.color);

  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DropSlotsPainter(color);
}

class _DropSlotsPainter extends BoxPainter {
  _DropSlotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var top = 0.0; top + 60 <= size.height + 0.5; top += 60) {
      final slot = RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx + 7, offset.dy + top + 1, size.width - 14, 58),
        const Radius.circular(6),
      );
      for (final metric in (Path()..addRRect(slot)).computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 10) {
          canvas.drawPath(metric.extractPath(d, d + 6), paint);
        }
      }
    }
  }
}

/// "Free play" (ui-spec.md "Detaching a song"): detaches the song and any
/// setlist, keeping the click as it sounds; [closes] also closes the
/// page it sits on (and Settings, if that's in the stack).
class FreePlayButton extends StatelessWidget {
  const FreePlayButton({super.key, required this.library, this.closes = false});

  static const buttonKey = Key('free-play-button');

  final LibraryController library;
  final bool closes;

  /// Fixed, and the same as "Save as song", so swapping modes never
  /// changes a header's layout.
  static const size = Size(128, 40);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size,
    child: OutlinedButton(
      key: buttonKey,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: size,
      ),
      onPressed: () {
        Haptics.medium(); // the song detached
        library.detachSong();
        // Back on the main screen (past Settings, if opened from there).
        if (closes) Navigator.popUntil(context, (route) => route.isFirst);
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
