import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
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
  static const sortKey = Key('library-sort');

  /// The muted line under a song's name: which setlists use it.
  static String usage(List<Setlist> sets) => switch (sets.length) {
    0 => 'Not in a setlist',
    1 || 2 => sets.map((l) => l.name).join(', '),
    final n => '$n setlists',
  };

  @override
  State<SongLibrary> createState() => _SongLibraryState();
}

class _SongLibraryState extends State<SongLibrary> {
  final _search = TextEditingController();
  bool _recent = false; // sort: A–Z (default) or recently edited

  LibraryController get _library => widget.library;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _edit([Song? song]) =>
      openSongEditor(context, _library, widget.metronome, song: song);

  /// Same as a picker row: while playing, restarts on beat 1. A song in
  /// the loaded set takes its position there; any other shows "– of N".
  void _load(Song song) {
    Haptics.medium(); // the song changed
    _library.playSong(song, widget.metronome);
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
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
                  child: songs.isEmpty
                      ? Center(
                          child: Text(
                            _library.songs.isEmpty
                                ? 'No songs yet. Use New song.'
                                : 'No songs match.',
                            style: TextStyle(color: colors.muted),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final song in songs) _row(colors, song),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _topBar(MetraColors colors) => Container(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.divider)),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left, size: 28),
        ),
        const Expanded(
          child: Text(
            'Song library',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            key: SongLibrary.newSongKey,
            onPressed: _edit,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New song', style: TextStyle(fontSize: 15)),
          ),
        ),
      ],
    ),
  );

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

  Widget _row(MetraColors colors, Song song) => InkWell(
    key: ValueKey('library-${song.id}'),
    onTap: () => _load(song),
    child: Container(
      height: 64,
      padding: const EdgeInsets.only(left: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
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
          SizedBox(
            width: 52,
            height: 64,
            child: IconButton(
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
  );
}
