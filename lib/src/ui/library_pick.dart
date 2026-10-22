import 'package:flutter/material.dart';

import 'search_match.dart';
import 'song_editor.dart';

import '../controller/metronome_controller.dart';

import '../controller/library_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'theme.dart';

/// The song library in pick mode (ui-spec.md, `library-pick.reference.html`):
/// check songs to add to [setName]. Returns the checked ids in library
/// order, or null if cancelled. Songs [inSet] say so but can still be added.
Future<List<String>?> pickSongs(
  BuildContext context,
  LibraryController library, {
  required String setName,
  required Set<String> inSet,
  required Future<String?> Function(BuildContext) newSong,
}) => Navigator.push(
  context,
  MaterialPageRoute<List<String>>(
    builder: (_) => LibraryPick(
      library: library,
      setName: setName,
      inSet: inSet,
      newSong: newSong,
    ),
  ),
);

/// The library in pick mode for set [setId] (the set panel, an empty set's
/// context row); the picked songs go to the end of the set.
Future<void> addSongsToSet(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome,
  String setId,
) async {
  final list = library.setlists.where((s) => s.id == setId).firstOrNull;
  if (list == null) return;
  final ids = await pickSongs(
    context,
    library,
    setName: list.name,
    inSet: list.songIds.toSet(),
    newSong: (context) async =>
        (await openSongEditor(context, library, metronome))?.id,
  );
  final latest = library.setlists.where((s) => s.id == setId).firstOrNull;
  if (ids == null || ids.isEmpty || latest == null) return;
  library.updateSetlist(latest.copyWith(songIds: [...latest.songIds, ...ids]));
}

class LibraryPick extends StatefulWidget {
  const LibraryPick({
    super.key,
    required this.library,
    required this.setName,
    required this.inSet,
    required this.newSong,
  });

  final LibraryController library;
  final String setName;
  final Set<String> inSet;
  final Future<String?> Function(BuildContext) newSong;

  static const addKey = Key('pick-add');
  static const newSongKey = Key('pick-new-song');
  static const selectAllKey = Key('pick-select-all');
  static const emptyNewSongKey = Key('pick-empty-new-song');

  @override
  State<LibraryPick> createState() => _LibraryPickState();
}

class _LibraryPickState extends State<LibraryPick> {
  final _checked = <String>{};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// With no songs to pick from, a new song goes straight into the set.
  Future<void> _newSongIntoSet() async {
    final id = await widget.newSong(context);
    if (id != null && mounted) Navigator.pop(context, [id]);
  }

  Future<void> _newSong() async {
    final id = await widget.newSong(context);
    if (id != null && mounted) setState(() => _checked.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final query = _search.text;
    final songs = [
      for (final song in widget.library.songsAZ)
        if (matchesSearch(song.name, query)) song,
    ];
    final count = _checked.length;
    return EditorScaffold(
      title: 'Add to ${widget.setName}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
            child: SearchField(
              controller: _search,
              onChanged: (_) => setState(() {}),
            ),
          ),
          Divider(height: 1, color: colors.divider),
          Expanded(
            child: widget.library.songs.isEmpty
                ? EmptyListState(
                    title: 'No songs yet',
                    hint:
                        'Create the first song. It goes into your library '
                        'and this set.',
                    action: 'New song',
                    actionKey: LibraryPick.emptyNewSongKey,
                    onAction: _newSongIntoSet,
                  )
                : songs.isEmpty
                ? NoMatches('songs', query, color: colors.muted)
                : ListView(
                    children: [
                      _selectAll(colors, songs),
                      for (final song in songs) _row(colors, song),
                    ],
                  ),
          ),
        ],
      ),
      // Hidden while empty: "New song" is in the middle.
      bottom: widget.library.songs.isEmpty
          ? null
          : SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: OutlinedButton.icon(
                      key: LibraryPick.newSongKey,
                      onPressed: _newSong,
                      icon: const Icon(Icons.add, size: 20),
                      label: const FittedBox(
                        child: Text('New song', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 7, // 1 : 1.4, as in library-pick.reference.html
                    child: FilledButton(
                      key: LibraryPick.addKey,
                      onPressed: count == 0
                          ? null
                          : () => Navigator.pop(context, [
                              // Library order, as listed.
                              for (final song in widget.library.songsAZ)
                                if (_checked.contains(song.id)) song.id,
                            ]),
                      child: FittedBox(
                        child: Text(
                          count == 0
                              ? 'Add songs'
                              : 'Add $count ${count == 1 ? 'song' : 'songs'}',
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Checks every song shown (respecting the search), or unchecks them
  /// all when they're all checked.
  Widget _selectAll(MetraColors colors, List<Song> shown) {
    final all = shown.every((song) => _checked.contains(song.id));
    return Semantics(
      checked: all,
      child: InkWell(
        key: LibraryPick.selectAllKey,
        onTap: () => setState(() {
          final ids = shown.map((song) => song.id);
          all ? _checked.removeAll(ids) : _checked.addAll(ids);
        }),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              _checkbox(colors, all),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Select all',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                shown.length == 1 ? '1 song' : '${shown.length} songs',
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _checkbox(MetraColors colors, bool checked) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: checked ? colors.accent : null,
      borderRadius: BorderRadius.circular(4),
      border: checked
          ? null
          : Border.all(color: colors.controlOutline, width: 2),
    ),
    child: checked
        ? Icon(Icons.check, size: 18, color: colors.onPrimary)
        : null,
  );

  Widget _row(MetraColors colors, Song song) {
    final checked = _checked.contains(song.id);
    return Semantics(
      checked: checked,
      child: InkWell(
        key: ValueKey('pick-${song.id}'),
        onTap: () => setState(
          () => checked ? _checked.remove(song.id) : _checked.add(song.id),
        ),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.divider)),
          ),
          child: Row(
            children: [
              _checkbox(colors, checked),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchName(
                      song.name,
                      query: _search.text,
                      matchColor: colors.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    if (widget.inSet.contains(song.id))
                      Text(
                        'Already in this set',
                        // A warning, not a block: it can still be added.
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: colors.accentSounding,
                        ),
                      ),
                  ],
                ),
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}
