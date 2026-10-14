import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';

/// Songs and setlists: pick a setlist, tap a song to load it (while
/// playing it takes over at the next bar line), save the current settings
/// as a song. Shown as a side panel on wide screens, a sheet on phones.
class LibraryPanel extends StatelessWidget {
  const LibraryPanel({
    super.key,
    required this.library,
    required this.metronome,
  });

  final LibraryController library;
  final MetronomeController metronome;

  static const _allSongs = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final setlist = library.selectedSetlist;
        final songs = library.visibleSongs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, setlist),
            const Divider(height: 1),
            Expanded(
              child: songs.isEmpty
                  ? _empty(context, setlist)
                  : setlist == null
                  ? ListView(
                      children: [
                        for (final (i, song) in songs.indexed)
                          _songTile(context, song, i, null),
                      ],
                    )
                  : ReorderableListView(
                      buildDefaultDragHandles: true,
                      onReorderItem: (from, to) =>
                          library.reorderSetlist(setlist.id, from, to),
                      children: [
                        for (final (i, song) in songs.indexed)
                          _songTile(context, song, i, setlist),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () => _saveCurrent(context),
                icon: const Icon(Icons.add),
                label: const Text('Save current as song'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, Setlist? setlist) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              key: const Key('setlist-picker'),
              isExpanded: true,
              underline: const SizedBox.shrink(),
              value: setlist?.id ?? _allSongs,
              items: [
                const DropdownMenuItem(
                  value: _allSongs,
                  child: Text('All songs'),
                ),
                for (final list in library.setlists)
                  DropdownMenuItem(value: list.id, child: Text(list.name)),
              ],
              onChanged: (id) =>
                  library.selectSetlist(id == _allSongs ? null : id),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Setlist actions',
            onSelected: (action) => switch (action) {
              'new' => _newSetlist(context),
              'rename' => _renameSetlist(context, setlist!),
              _ => _deleteSetlist(context, setlist!),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('New setlist')),
              if (setlist != null) ...[
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename setlist'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete setlist'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, Setlist? setlist) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        setlist == null
            ? 'No songs yet. Set a tempo, then save it as a song.'
            : 'This setlist is empty. Add songs from “All songs”, or save '
                  'the current tempo here.',
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _songTile(BuildContext context, Song song, int index, Setlist? list) {
    return ListTile(
      key: ValueKey('${song.id}-$index'),
      selected: library.currentIndex == index,
      title: Text(song.name),
      subtitle: Text('${song.bpm} BPM · ${song.pattern.beatsPerBar} beats'),
      onTap: () => library.playSong(song, metronome, index: index),
      trailing: PopupMenuButton<String>(
        tooltip: 'Song actions',
        onSelected: (action) => switch (action) {
          'update' => library.updateSongFromMetronome(song, metronome),
          'rename' => _renameSong(context, song),
          'add' => _addToSetlist(context, song),
          'remove' => library.removeFromSetlist(list!.id, index),
          _ => _deleteSong(context, song),
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'update',
            child: Text('Use current tempo'),
          ),
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (library.setlists.isNotEmpty)
            const PopupMenuItem(value: 'add', child: Text('Add to setlist')),
          if (list != null)
            const PopupMenuItem(
              value: 'remove',
              child: Text('Remove from setlist'),
            ),
          const PopupMenuItem(value: 'delete', child: Text('Delete song')),
        ],
      ),
    );
  }

  Future<void> _saveCurrent(BuildContext context) async {
    final name = await _askName(
      context,
      title: 'Save as song',
      initial: '${metronome.bpm} BPM',
    );
    if (name != null) library.saveCurrentAsSong(name, metronome);
  }

  Future<void> _renameSong(BuildContext context, Song song) async {
    final name = await _askName(context, title: 'Rename', initial: song.name);
    if (name != null) library.updateSong(song.copyWith(name: name));
  }

  Future<void> _deleteSong(BuildContext context, Song song) async {
    if (await _confirm(context, 'Delete “${song.name}”?')) {
      library.deleteSong(song.id);
    }
  }

  Future<void> _addToSetlist(BuildContext context, Song song) async {
    final id = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add to setlist'),
        children: [
          for (final list in library.setlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, list.id),
              child: Text(list.name),
            ),
        ],
      ),
    );
    if (id != null) library.addToSetlist(id, song.id);
  }

  Future<void> _newSetlist(BuildContext context) async {
    final name = await _askName(context, title: 'New setlist', initial: '');
    if (name != null) library.selectSetlist(library.addSetlist(name).id);
  }

  Future<void> _renameSetlist(BuildContext context, Setlist list) async {
    final name = await _askName(context, title: 'Rename', initial: list.name);
    if (name != null) library.updateSetlist(list.copyWith(name: name));
  }

  Future<void> _deleteSetlist(BuildContext context, Setlist list) async {
    final ok = await _confirm(
      context,
      'Delete setlist “${list.name}”? Its songs are kept.',
    );
    if (ok) library.deleteSetlist(list.id);
  }
}

/// A trimmed, non-empty name, or null if cancelled.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  required String initial,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(title: title, initial: initial),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  // Owned here so it outlives the dialog's closing animation.
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: const Text('Save'),
      ),
    ],
  );
}

Future<bool> _confirm(BuildContext context, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;
