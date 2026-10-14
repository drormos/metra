import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../model/library.dart';
import 'editor_scaffold.dart';
import 'library_pick.dart';
import 'theme.dart';

/// Opens the setlist editor (ui-spec.md, `setlist-editor.reference.html`)
/// for [setlist], or a new set when null. A new set is loaded once saved.
/// Editing never touches the click.
Future<void> openSetlistEditor(
  BuildContext context,
  LibraryController library, {
  Setlist? setlist,
  required Future<String?> Function(BuildContext) newSong,
}) => Navigator.push(
  context,
  MaterialPageRoute<void>(
    builder: (_) =>
        SetlistEditor(library: library, setlist: setlist, newSong: newSong),
  ),
);

class SetlistEditor extends StatefulWidget {
  const SetlistEditor({
    super.key,
    required this.library,
    this.setlist,
    required this.newSong,
  });

  final LibraryController library;

  /// Null: a new set.
  final Setlist? setlist;

  /// Creates a song for pick mode's "New song"; returns its id.
  final Future<String?> Function(BuildContext) newSong;

  static const addSongsKey = Key('add-songs');
  static const deleteKey = Key('delete-setlist');

  @override
  State<SetlistEditor> createState() => _SetlistEditorState();
}

class _SetlistEditorState extends State<SetlistEditor> {
  // The draft: nothing is saved until Save. A new set's default name is
  // selected, so typing replaces it and leaving it keeps it.
  late final String _initialName =
      widget.setlist?.name ?? widget.library.newSetlistName();
  late final _name = TextEditingController(text: _initialName)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: _initialName.length,
    );
  late List<String> _songIds = [...?widget.setlist?.songIds];

  LibraryController get _library => widget.library;
  bool get _isNew => widget.setlist == null;

  bool get _dirty =>
      _name.text != _initialName ||
      !_sameIds(_songIds, widget.setlist?.songIds ?? const []);

  static bool _sameIds(List<String> a, List<String> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((same) => same);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final saved = _library.saveSetlist(
      id: widget.setlist?.id,
      name: _name.text.trim(),
      songIds: _songIds,
    );
    if (_isNew) _library.setActiveSetlist(saved.id);
    Navigator.pop(context);
  }

  void _remove(int index) {
    final id = _songIds[index];
    setState(() => _songIds = [..._songIds]..removeAt(index));
    // No confirmation: removing never deletes the song. Undo puts it back.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              if (!mounted) return;
              setState(() => _songIds = [..._songIds]..insert(index, id));
            },
          ),
        ),
      );
  }

  Future<void> _addSongs() async {
    final ids = await pickSongs(
      context,
      _library,
      setName: _name.text.trim().isEmpty ? 'this set' : _name.text.trim(),
      inSet: _songIds.toSet(),
      newSong: widget.newSong,
    );
    if (ids != null && ids.isNotEmpty) {
      setState(() => _songIds = [..._songIds, ...ids]);
    }
  }

  Future<void> _delete() async {
    final name = widget.setlist!.name;
    final ok = await confirm(
      context,
      'Delete “$name”? Its songs stay in your library.',
      'Delete',
    );
    if (!ok || !mounted) return;
    _library.deleteSetlist(widget.setlist!.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final songs = [for (final id in _songIds) ?_library.songById(id)];
    return EditorScaffold(
      title: _isNew ? 'New setlist' : 'Setlist',
      actionLabel: 'Save',
      dirty: _dirty,
      onAction: _name.text.trim().isEmpty ? null : _save,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: 'Name',
                    controller: _name,
                    autofocus: _isNew,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (songs.isEmpty)
                    // Empty state (setlist-new.reference.html).
                    Padding(
                      padding: const EdgeInsets.only(top: 40, bottom: 12),
                      child: Column(
                        children: [
                          const Text(
                            'No songs yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add songs from your library, or create new ones '
                            'as you go.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: colors.muted),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          songs.length == 1
                              ? '1 song'
                              : '${songs.length} songs',
                          style: TextStyle(fontSize: 14, color: colors.muted),
                        ),
                        const Spacer(),
                        if (songs.length > 1)
                          Text(
                            'Drag to reorder',
                            style: TextStyle(fontSize: 13, color: colors.muted),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverReorderableList(
            itemCount: songs.length,
            onReorderItem: (from, to) => setState(() {
              final ids = [..._songIds];
              ids.insert(to, ids.removeAt(from));
              _songIds = ids;
            }),
            itemBuilder: (context, i) => _row(colors, songs[i], i),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // A shortcut for a new, empty set.
                  if (_isNew && _songIds.isEmpty && _library.songs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => setState(
                            () => _songIds = [
                              for (final song in _library.songsAZ) song.id,
                            ],
                          ),
                          child: const Text('Start with all songs'),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      key: SetlistEditor.addSongsKey,
                      // The primary action while the set is empty.
                      style: songs.isEmpty
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: colors.surface,
                              foregroundColor: colors.text,
                            ),
                      onPressed: _addSongs,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text(
                        'Add songs',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                  if (!_isNew) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        key: SetlistEditor.deleteKey,
                        style: TextButton.styleFrom(
                          foregroundColor: colors.accentSounding,
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: _delete,
                        child: const Text(
                          'Delete setlist',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(MetraColors colors, Song song, int index) => Container(
    // Rows are keyed by position: the same song may appear twice.
    key: ValueKey('setlist-row-$index-${song.id}'),
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: colors.background,
      border: Border(bottom: BorderSide(color: colors.divider)),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Remove ${song.name} from setlist',
          color: colors.muted,
          onPressed: () => _remove(index),
          icon: const Icon(Icons.close, size: 20),
        ),
        SizedBox(
          width: 20,
          child: Text(
            '${index + 1}',
            style: TextStyle(fontSize: 15, color: colors.muted),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
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
        ReorderableDragStartListener(
          index: index,
          child: Semantics(
            label: 'Reorder ${song.name}',
            child: SizedBox.square(
              dimension: 44,
              child: Icon(Icons.drag_handle, color: colors.muted),
            ),
          ),
        ),
      ],
    ),
  );
}
