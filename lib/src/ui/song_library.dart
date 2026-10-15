import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'play_marker.dart';
import 'song_editor.dart';
import 'theme.dart';

/// Opens the song library in browse mode (ui-spec.md "Song library",
/// `song-library.reference.html`): every song, searchable, A–Z or recently
/// edited. Tapping a row loads that song (the picker's rules, mode kept)
/// and returns to the main screen; its pencil opens the song editor. The
/// way to play a single song without a setlist.
Future<void> openSongLibrary(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome,
) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) => SongLibrary(library: library, metronome: metronome),
  ),
);

class SongLibrary extends StatefulWidget {
  const SongLibrary({
    super.key,
    required this.library,
    required this.metronome,
  });

  final LibraryController library;

  /// For the song editor (saving the loaded song applies to it).
  final MetronomeController metronome;

  static const newSongKey = Key('library-new-song');
  static const deleteSongsKey = Key('library-delete-songs');
  static const deleteMarkedKey = Key('library-delete-marked');
  static const emptyNewSongKey = Key('library-empty-new-song');
  static const sortKey = Key('library-sort');

  /// The muted line under a song's name: which setlists use it.
  static String usage(List<Setlist> sets) => switch (sets.length) {
    0 => 'Not in a setlist',
    1 || 2 => sets.map((l) => l.name).join(', '),
    final n => '$n setlists',
  };

  /// The delete confirmation, naming the sets it affects, since songs are
  /// shared.
  static String deleteMessage(List<Song> songs, List<Setlist> sets) {
    final what = songs.length == 1
        ? 'Delete ${songs.single.name}?'
        : 'Delete ${songs.length} songs?';
    if (sets.isEmpty) return what;
    final where = sets.length <= 2
        ? sets.map((l) => l.name).join(' and ')
        : '${sets.length} setlists';
    return songs.length == 1
        ? '$what It will also be removed from $where.'
        : '$what They will also be removed from $where.';
  }

  @override
  State<SongLibrary> createState() => _SongLibraryState();
}

class _SongLibraryState extends State<SongLibrary> {
  final _search = TextEditingController();
  bool _recent = false; // sort: A–Z (default) or recently edited
  // "Delete songs" marking: the marked song ids.
  bool _marking = false;
  final _marked = <String>{};

  LibraryController get _library => widget.library;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _edit([Song? song]) =>
      openSongEditor(context, _library, widget.metronome, song: song);

  /// Always Single song mode, from any mode; any setlist is unloaded.
  /// While playing, restarts on beat 1, like a picker row.
  void _load(Song song) {
    Haptics.medium(); // the song changed
    _library.playSingleSong(song, widget.metronome);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  void _endMarking() {
    _marking = false;
    _marked.clear();
  }

  void _toggleMark(String id) {
    Haptics.tick();
    setState(() => _marked.contains(id) ? _marked.remove(id) : _marked.add(id));
  }

  /// Asks first, naming the sets the songs leave. Deleting the loaded song
  /// switches to Free play.
  Future<void> _deleteMarked() async {
    final ids = {..._marked};
    final songs = [
      for (final song in _library.songsAZ)
        if (ids.contains(song.id)) song,
    ];
    final sets = [
      for (final list in _library.setlists)
        if (list.songIds.any(ids.contains)) list,
    ];
    final ok = await confirm(
      context,
      SongLibrary.deleteMessage(songs, sets),
      'Delete',
    );
    if (!ok || !mounted) return;
    _library.deleteSongs(ids);
    setState(_endMarking);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // The back gesture ends marking before it leaves.
    canPop: !_marking,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(_endMarking);
    },
    child: _screen(context),
  );

  Widget _screen(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        // Saving or deleting in the editor changes the list.
        child: ListenableBuilder(
          listenable: _library,
          builder: (context, _) {
            final query = _search.text.trim().toLowerCase();
            final songs = [
              for (final song
                  in _recent ? _library.songsRecentlyEdited : _library.songsAZ)
                if (query.isEmpty || song.name.toLowerCase().contains(query))
                  song,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _topBar(colors),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: SearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _library.songs.length == 1
                              ? '1 song'
                              : '${_library.songs.length} songs',
                          style: TextStyle(fontSize: 14, color: colors.muted),
                        ),
                      ),
                      _sortControl(colors),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.divider),
                Expanded(
                  child: _library.songs.isEmpty
                      ? EmptyListState(
                          title: 'No songs yet',
                          hint:
                              'Save a tempo and meter as a song to play '
                              'it again or put it in a setlist.',
                          action: 'New song',
                          actionKey: SongLibrary.emptyNewSongKey,
                          onAction: _edit,
                        )
                      : songs.isEmpty
                      ? Center(
                          child: Text(
                            'No songs match.',
                            style: TextStyle(color: colors.muted),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final song in songs) _row(colors, song),
                          ],
                        ),
                ),
                // Hidden while empty: "New song" is in the middle.
                if (_library.songs.isEmpty)
                  const SizedBox.shrink()
                else if (_marking)
                  SelectionBar(
                    count: _marked.length,
                    action: 'Delete',
                    actionKey: SongLibrary.deleteMarkedKey,
                    onAction: _deleteMarked,
                    onCancel: () => setState(_endMarking),
                  )
                else
                  BottomBar(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: SongLibrary.newSongKey,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.surface,
                            foregroundColor: colors.text,
                          ),
                          onPressed: _edit,
                          icon: const Icon(Icons.add, size: 20),
                          label: const FittedBox(
                            child: Text(
                              'New song',
                              style: TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: SongLibrary.deleteSongsKey,
                          onPressed: () => setState(() => _marking = true),
                          child: const FittedBox(
                            child: Text(
                              'Delete songs',
                              style: TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(MetraColors colors) =>
      const BackBar(title: 'Song library', centered: true);

  Widget _sortControl(MetraColors colors) => PopupMenuButton<bool>(
    key: SongLibrary.sortKey,
    tooltip: 'Sort',
    initialValue: _recent,
    onSelected: (recent) => setState(() => _recent = recent),
    itemBuilder: (_) => const [
      PopupMenuItem(value: false, child: Text('A–Z')),
      PopupMenuItem(value: true, child: Text('Recently edited')),
    ],
    child: SizedBox(
      height: 44,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _recent ? 'Recently edited' : 'A–Z',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 18, color: colors.muted),
          const SizedBox(width: 12),
        ],
      ),
    ),
  );

  Widget _row(MetraColors colors, Song song) {
    final marked = _marked.contains(song.id);
    return Material(
      color: marked ? colors.selectedRow : colors.background,
      child: InkWell(
        key: ValueKey('library-${song.id}'),
        onTap: _marking ? () => _toggleMark(song.id) : () => _load(song),
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
                child: _marking
                    ? MarkCircle(checked: marked)
                    : PlayMarker(current: song.id == _library.currentSong?.id),
              ),
              const SizedBox(width: 14),
              Expanded(
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
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      SongLibrary.usage(_library.setlistsUsing(song.id)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${song.bpm}',
                style: const TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
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
                height: 64,
                child: _marking
                    ? null
                    : IconButton(
                        key: ValueKey('library-edit-${song.id}'),
                        tooltip: 'Edit ${song.name}',
                        color: colors.muted,
                        onPressed: () => _edit(song),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
