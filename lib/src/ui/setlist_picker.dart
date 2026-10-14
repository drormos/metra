import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'haptics.dart';
import 'song_editor.dart';
import 'theme.dart';

/// The setlist picker sheet (ui-spec.md, `setlist-picker` and
/// `set-switcher` references): a songs view for the loaded set and a "What
/// to play" view for switching sets or going to Free play. Opening it never
/// touches the click; only choosing a song or a set does.
///
/// Opens on the songs view with a setlist loaded, else on "What to play".
Future<void> showSetlistPicker(
  BuildContext context, {
  required LibraryController library,
  required MetronomeController metronome,
  required VoidCallback onEditSetlist,
  required VoidCallback onSongLibrary,
  required VoidCallback onNewSetlist,
}) {
  final height = MediaQuery.sizeOf(context).height;
  final colors = context.colors;
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
      onEditSetlist: onEditSetlist,
      onSongLibrary: onSongLibrary,
      onNewSetlist: onNewSetlist,
    ),
  );
}

class SetlistPicker extends StatefulWidget {
  const SetlistPicker({
    super.key,
    required this.library,
    required this.metronome,
    required this.onEditSetlist,
    required this.onSongLibrary,
    required this.onNewSetlist,
  });

  final LibraryController library;
  final MetronomeController metronome;
  final VoidCallback onEditSetlist;
  final VoidCallback onSongLibrary;
  final VoidCallback onNewSetlist;

  static const setNameKey = Key('picker-set-name');
  static const freePlayKey = Key('picker-free-play');

  @override
  State<SetlistPicker> createState() => _SetlistPickerState();
}

class _SetlistPickerState extends State<SetlistPicker> {
  // Which view is showing; navigation inside the sheet only.
  late bool _whatToPlay = widget.library.activeSetlist == null;

  LibraryController get _library => widget.library;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _library,
    builder: (context, _) {
      final setlist = _library.activeSetlist;
      return _whatToPlay || setlist == null
          ? _whatToPlayView(context, canGoBack: setlist != null)
          : _songsView(context, setlist);
    },
  );

  // Songs view

  Widget _songsView(BuildContext context, Setlist setlist) {
    final colors = context.colors;
    final songs = _library.visibleSongs;
    final current = _library.currentIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: SetlistPicker.setNameKey,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => setState(() => _whatToPlay = true),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
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
                        const SizedBox(width: 10),
                        const Icon(Icons.expand_more, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: widget.onEditSetlist,
                  child: const Text('Edit', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No songs in this set yet. Use Edit to add some.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
                )
              // Long-press and drag reorders the set, saved at once;
              // playback is unaffected.
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: songs.length,
                  onReorderStart: (_) => Haptics.medium(),
                  onReorderItem: (from, to) =>
                      _library.reorderSetlist(setlist.id, from, to),
                  itemBuilder: (context, i) =>
                      ReorderableDelayedDragStartListener(
                        // Keyed by position: the same song may appear twice.
                        key: ValueKey('picker-row-$i-${songs[i].id}'),
                        index: i,
                        child: _songRow(
                          colors,
                          songs[i],
                          i,
                          current: i == current,
                        ),
                      ),
                ),
        ),
        _bottomBar(colors, [Expanded(child: _songLibraryButton())]),
      ],
    );
  }

  Widget _songRow(
    MetraColors colors,
    Song song,
    int index, {
    required bool current,
  }) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: ValueKey('picker-song-$index'),
      onTap: () {
        // Same rules as next/previous; the sheet closes after.
        Haptics.medium();
        _library.playSong(song, widget.metronome, index: index);
        Navigator.pop(context);
      },
      child: Ink(
        height: 60,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: current ? colors.selectedRow : null,
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: current
                  ? Icon(Icons.play_arrow, size: 18, color: colors.accent)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(fontSize: 15, color: colors.muted),
                    ),
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
            SizedBox(
              width: 52,
              height: 60,
              child: IconButton(
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
  );

  // What to play view

  Widget _whatToPlayView(BuildContext context, {required bool canGoBack}) {
    final colors = context.colors;
    final active = _library.activeSetlist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 24, 12),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                if (canGoBack)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => setState(() => _whatToPlay = false),
                    icon: const Icon(Icons.chevron_left, size: 28),
                  )
                else
                  const SizedBox(width: 12),
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
                // Only the mode changes; the click keeps going as it is.
                _library.setActiveSetlist(null);
                Navigator.pop(context);
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
          child: Text(
            'Setlists',
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ),
        Divider(height: 1, color: colors.divider),
        Expanded(
          child: ListView(
            children: [
              for (final setlist in _library.setlists)
                _setRow(colors, setlist, current: setlist.id == active?.id),
            ],
          ),
        ),
        _bottomBar(colors, [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.surface,
                foregroundColor: colors.text,
              ),
              onPressed: widget.onNewSetlist,
              icon: const Icon(Icons.add, size: 20),
              label: const FittedBox(
                child: Text('New setlist', style: TextStyle(fontSize: 17)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _songLibraryButton(icon: false)),
        ]),
      ],
    );
  }

  Widget _setRow(
    MetraColors colors,
    Setlist setlist, {
    required bool current,
  }) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: ValueKey('picker-set-${setlist.id}'),
      onTap: () {
        // Loads the set at its first song, then shows its songs.
        _library.setActiveSetlist(setlist.id);
        final songs = _library.visibleSongs;
        if (songs.isNotEmpty) {
          Haptics.medium(); // the song changes
          _library.playSong(songs.first, widget.metronome, index: 0);
        }
        setState(() => _whatToPlay = false);
      },
      child: Ink(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: current ? colors.selectedRow : null,
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
                    setlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  Text(
                    _count(setlist.songIds.length),
                    style: TextStyle(fontSize: 14, color: colors.muted),
                  ),
                ],
              ),
            ),
            if (current) Icon(Icons.check, size: 22, color: colors.accent),
          ],
        ),
      ),
    ),
  );

  // Shared pieces

  Widget _songLibraryButton({bool icon = true}) => OutlinedButton.icon(
    onPressed: widget.onSongLibrary,
    icon: icon ? const Icon(Icons.library_music_outlined, size: 20) : null,
    // Shrinks rather than overflowing beside "New setlist" on narrow phones.
    label: const FittedBox(
      child: Text('Song library', style: TextStyle(fontSize: 17)),
    ),
  );

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
