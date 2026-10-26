import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import 'haptics.dart';
import 'theme.dart';

/// "Save as new song" (ui-spec.md, `save-as-new.reference.html`): from
/// "Save as new" under the BPM, or "+ New song" in Free play (titled "New
/// song" there).
/// Saves what the click plays now as a new library song and loads it; the
/// click carries on unchanged.
/// True once saved.
Future<bool> showSaveAsNewSong(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _SaveAsNewDialog(library: library, metronome: metronome),
    ) ??
    false;

class _SaveAsNewDialog extends StatefulWidget {
  const _SaveAsNewDialog({required this.library, required this.metronome});

  final LibraryController library;
  final MetronomeController metronome;

  @override
  State<_SaveAsNewDialog> createState() => _SaveAsNewDialogState();
}

class _SaveAsNewDialogState extends State<_SaveAsNewDialog> {
  late final _song = widget.library.currentSong;

  // The set choice exists only in setlist mode.
  late final _set = _song == null ? null : widget.library.activeSetlist;
  late final _name = () {
    final name = _song == null
        ? widget.library.newSongName()
        : widget.library.copyName(_song);
    return TextEditingController(text: name)
      ..selection = TextSelection(baseOffset: 0, extentOffset: name.length);
  }();
  SongPlacement _placement = SongPlacement.replace;

  // Outside setlist mode: "Add to a setlist" (ui-spec.md "Adding songs to
  // sets", `new-song-dialog.reference.html`). A set id, [_newSet], or
  // [_none]; open in place once tapped, "More setlists" shows the rest.
  static const _none = '';
  static const _newSet = '+new';
  String _target = _none;
  bool _choosing = false;
  bool _more = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _error {
    final name = _name.text.trim();
    if (name.isEmpty) return 'Give the song a name';
    return widget.library.songNameTaken(name)
        ? 'Another song already has this name'
        : null;
  }

  void _save() {
    if (_error != null) return;
    Haptics.tick();
    final library = widget.library;
    final song = library.saveAsNewSong(
      _name.text.trim(),
      widget.metronome,
      placement: _set == null ? SongPlacement.none : _placement,
      // Free play's "+ New song from this" is a new song, not a copy.
      fresh: _song == null,
    );
    // At the end of the chosen set; the app stays where it is.
    if (_target != _none) {
      final setId = _target == _newSet ? library.createSetlist().id : _target;
      library.addToSetlist(setId, song.id);
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final song = _song;
    final set = _set;
    return AlertDialog(
      // From Free play it's simply a new song from what's sounding.
      title: Text(song == null ? 'New song' : 'Save as new song'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Name', style: TextStyle(fontSize: 14, color: colors.muted)),
            const SizedBox(height: 8),
            TextField(
              key: SaveAsNewKeys.name,
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              style: const TextStyle(
                fontFamily: MetraFonts.condensed,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                errorText: _error,
                errorStyle: TextStyle(color: colors.accentSounding),
              ),
            ),
            if (set == null) ..._addToSet(colors),
            if (set != null && song != null) ...[
              const SizedBox(height: 20),
              Text(
                'In ${set.name}',
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
              RadioGroup<SongPlacement>(
                groupValue: _placement,
                onChanged: (value) => setState(() => _placement = value!),
                child: Column(
                  children: [
                    _option(
                      SongPlacement.replace,
                      'Replace ${song.name}',
                      'The new song takes its place',
                    ),
                    _option(
                      SongPlacement.addAfter,
                      'Add after ${song.name}',
                      'Both stay in the set',
                    ),
                    _option(
                      SongPlacement.none,
                      "Don't add",
                      'Leaves the set; plays as a single song',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: SaveAsNewKeys.save,
          onPressed: _error == null ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// "Add to a setlist": a closed field showing the choice; tapped, the
  /// choices open in place (None, the 3 most recently played sets, "More
  /// setlists ⌄" for the rest, "+ New setlist").
  List<Widget> _addToSet(MetraColors colors) {
    final library = widget.library;
    final sets = library.setlistsRecentlyPlayed;
    final label = Text(
      'Add to a setlist',
      style: TextStyle(fontSize: 14, color: colors.muted),
    );
    if (!_choosing) {
      final chosen = switch (_target) {
        _none => 'None',
        _newSet => library.newSetlistName(),
        final id => sets.firstWhere((s) => s.id == id).name,
      };
      return [
        const SizedBox(height: 20),
        label,
        const SizedBox(height: 8),
        InkWell(
          key: SaveAsNewKeys.addToSet,
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _choosing = true),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: colors.controlOutline, width: 2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chosen,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                Icon(Icons.expand_more, color: colors.muted),
              ],
            ),
          ),
        ),
      ];
    }
    final shown = _more ? sets : sets.take(3);
    String count(int n) => n == 1 ? '1 song' : '$n songs';
    return [
      const SizedBox(height: 20),
      label,
      RadioGroup<String>(
        groupValue: _target,
        onChanged: (value) => setState(() => _target = value!),
        child: Column(
          children: [
            _setOption(_none, 'None', 'Just save the song'),
            for (final s in shown)
              _setOption(
                s.id,
                s.name,
                _target == s.id
                    ? 'Added at the end · ${count(s.songIds.length)}'
                    : count(s.songIds.length),
              ),
            if (!_more && sets.length > 3)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: SaveAsNewKeys.moreSets,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.expand_more, size: 20),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.muted,
                    padding: const EdgeInsets.only(left: 32, right: 12),
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () => setState(() => _more = true),
                  label: const Text(
                    'More setlists',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            _setOption(
              _newSet,
              '+ New setlist',
              'Named ${library.newSetlistName()}; rename it later',
            ),
          ],
        ),
      ),
    ];
  }

  Widget _setOption(String value, String title, String detail) =>
      RadioListTile<String>(
        key: ValueKey('add-to-set-$value'),
        value: value,
        contentPadding: EdgeInsets.zero,
        activeColor: context.colors.accent,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          detail,
          style: TextStyle(fontSize: 13, color: context.colors.muted),
        ),
      );

  Widget _option(SongPlacement value, String title, String detail) =>
      RadioListTile<SongPlacement>(
        key: ValueKey('placement-${value.name}'),
        value: value,
        contentPadding: EdgeInsets.zero,
        activeColor: context.colors.accent,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          detail,
          style: TextStyle(fontSize: 13, color: context.colors.muted),
        ),
      );
}

abstract final class SaveAsNewKeys {
  static const name = Key('save-as-new-name');
  static const save = Key('save-as-new-save');
  static const addToSet = Key('save-as-new-add-to-set');
  static const moreSets = Key('save-as-new-more-sets');
  static const newSet = ValueKey('add-to-set-+new');
  static const noSet = ValueKey('add-to-set-');
}
