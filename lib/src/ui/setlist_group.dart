import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'haptics.dart';
import 'icons.dart';
import 'quick_pick.dart';
import 'save_as_new_dialog.dart';
import 'setlist_picker.dart';
import 'subdivision_icon.dart';
import 'theme.dart';

/// The framed setlist group at the bottom of the main screen (ui-spec.md).
/// Identical size and position in both modes, so no control ever moves:
/// a 44px header, a 14px gap, a 68px button row.
class SetlistGroup extends StatelessWidget {
  const SetlistGroup({
    super.key,
    required this.library,
    required this.metronome,
  });

  final LibraryController library;
  final MetronomeController metronome;

  static const headerKey = Key('setlist-header');
  static const previousKey = Key('previous-song');
  static const nextKey = Key('next-song');
  static const setlistsKey = Key('free-play-setlists');
  static const songsKey = Key('free-play-songs');
  static const saveAsSongKey = Key('free-play-save-as-song');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final setlist = library.activeSetlist;
    // Each ⌄ opens its dropdown just above this group.
    void pick(QuickPickKind kind) => showQuickPick(
      context,
      kind: kind,
      library: library,
      metronome: metronome,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: setlist != null
                ? _setlistHeader(
                    colors,
                    setlist,
                    pick,
                    // Long-press = that set's page; back returns here.
                    () {
                      Haptics.medium();
                      openSetlists(
                        context,
                        library: library,
                        metronome: metronome,
                        setId: setlist.id,
                      );
                    },
                  )
                : library.singleSong
                ? _singleSongHeader(colors)
                : _freePlayHeader(colors),
          ),
          // Keeps a thumb aiming for previous/next off the header.
          const SizedBox(height: 14),
          SizedBox(
            height: 68,
            child: setlist == null
                ? _freePlayRow(colors, pick)
                : _stepRow(colors),
          ),
        ],
      ),
    );
  }

  /// "Save as song" sits where Single song has "Free play": an option,
  /// not pushed.
  Widget _freePlayHeader(MetraColors colors) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Row(
      children: [
        const MetronomeIcon(size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Free play', style: TextStyle(fontSize: 16)),
        ),
        Builder(
          builder: (context) => SizedBox.fromSize(
            size: FreePlayButton.size,
            child: OutlinedButton(
              key: saveAsSongKey,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: FreePlayButton.size,
              ),
              onPressed: () => showSaveAsNewSong(context, library, metronome),
              child: const Text(
                'Save as song',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  /// Plain text naming the source (the song's name is the top title), and
  /// "Free play" to detach it: no confirmation, nothing is deleted.
  Widget _singleSongHeader(MetraColors colors) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Row(
      children: [
        const SubdivisionIcon(1, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Single song', style: TextStyle(fontSize: 16)),
        ),
        FreePlayButton(library: library),
      ],
    ),
  );

  /// An outlined dropdown-style control: it must look tappable.
  Widget _setlistHeader(
    MetraColors colors,
    Setlist setlist,
    void Function(QuickPickKind) pick,
    VoidCallback openPage,
  ) {
    final index = library.currentIndex;
    return OutlinedButton(
      key: headerKey,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        // Our own haptic on long-press, gated by "Vibrate on touch".
        enableFeedback: false,
      ),
      onPressed: () => pick(QuickPickKind.set),
      onLongPress: openPage,
      child: Row(
        children: [
          const SetlistIcon(),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              setlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          // No current song (an empty set, or the song was removed from it):
          // no position.
          if (index >= 0)
            Text(
              '${index + 1} of ${library.visibleSongs.length}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colors.muted,
              ),
            ),
          const SizedBox(width: 10),
          const Icon(Icons.expand_more, size: 20),
        ],
      ),
    );
  }

  /// Two equal outlined buttons, quieter than previous/next (52px tall,
  /// centred in the 68px row), each opening its dropdown: the main-screen
  /// way to play a single song or switch to a set.
  Widget _freePlayRow(MetraColors colors, void Function(QuickPickKind) pick) {
    return Center(
      child: SizedBox(
        height: 52,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _freePlayButton(
                colors,
                key: setlistsKey,
                icon: const SetlistIcon(),
                label: 'Setlists',
                onPressed: () => pick(QuickPickKind.sets),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _freePlayButton(
                colors,
                key: songsKey,
                icon: const SubdivisionIcon(1, size: 18),
                label: 'Songs',
                onPressed: () => pick(QuickPickKind.songs),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freePlayButton(
    MetraColors colors, {
    required Key key,
    required Widget icon,
    required String label,
    required VoidCallback onPressed,
  }) => OutlinedButton(
    key: key,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14),
    ),
    onPressed: onPressed,
    child: Row(
      children: [
        icon,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        Icon(Icons.expand_more, size: 18, color: colors.muted),
      ],
    ),
  );

  /// Previous and next show the neighbouring song (no words), filled,
  /// disabled at the ends of the list.
  Widget _stepRow(MetraColors colors) {
    final songs = library.visibleSongs;
    final index = library.currentIndex;
    // With no current song in the set, "next" is its first song.
    final previous = library.hasPrevious ? songs[index - 1] : null;
    final next = library.hasNext ? songs[index + 1] : null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _stepButton(
            key: previousKey,
            colors: colors,
            song: previous,
            forward: false,
            onPressed: () {
              Haptics.medium();
              library.previousSong(metronome);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stepButton(
            key: nextKey,
            colors: colors,
            song: next,
            forward: true,
            onPressed: () {
              Haptics.medium();
              library.nextSong(metronome);
            },
          ),
        ),
      ],
    );
  }

  Widget _stepButton({
    required Key key,
    required MetraColors colors,
    required Song? song,
    required bool forward,
    required VoidCallback onPressed,
  }) {
    final align = forward ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final label = Flexible(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: align,
        children: [
          if (song != null) ...[
            Text(
              song.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            Text(
              '${song.bpm} bpm',
              style: TextStyle(fontSize: 13, color: colors.muted),
            ),
          ],
        ],
      ),
    );
    final chevron = Icon(
      forward ? Icons.chevron_right : Icons.chevron_left,
      size: 26,
    );
    return Semantics(
      label: song == null
          ? (forward ? 'No next song' : 'No previous song')
          : '${forward ? 'Next' : 'Previous'} song: ${song.name}',
      excludeSemantics: true,
      button: true,
      enabled: song != null,
      child: FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: colors.surface,
          foregroundColor: colors.text,
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: song == null ? null : onPressed,
        child: Row(
          mainAxisAlignment: forward
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: forward
              ? [label, const SizedBox(width: 8), chevron]
              : [chevron, const SizedBox(width: 8), label],
        ),
      ),
    );
  }
}
