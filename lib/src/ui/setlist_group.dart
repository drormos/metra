import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import 'theme.dart';

/// The framed setlist group at the bottom of the main screen (ui-spec.md).
/// Identical size and position in both modes, so no control ever moves:
/// a 44px header, a 14px gap, a 68px button row.
class SetlistGroup extends StatelessWidget {
  const SetlistGroup({
    super.key,
    required this.library,
    required this.metronome,
    required this.onOpenPicker,
    required this.onNewSetlist,
  });

  final LibraryController library;
  final MetronomeController metronome;
  final VoidCallback onOpenPicker;
  final VoidCallback onNewSetlist;

  static const headerKey = Key('setlist-header');
  static const previousKey = Key('previous-song');
  static const nextKey = Key('next-song');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final setlist = library.activeSetlist;
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
            child: setlist == null
                ? _freePlayHeader(colors)
                : _setlistHeader(colors, setlist),
          ),
          // Keeps a thumb aiming for previous/next off the header.
          const SizedBox(height: 14),
          SizedBox(
            height: 68,
            child: setlist == null ? _freePlayRow(colors) : _stepRow(colors),
          ),
        ],
      ),
    );
  }

  Widget _freePlayHeader(MetraColors colors) => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: Row(
      children: [
        Icon(Icons.notes, size: 18),
        SizedBox(width: 10),
        Text('Free play', style: TextStyle(fontSize: 16)),
      ],
    ),
  );

  /// An outlined dropdown-style control: it must look tappable.
  Widget _setlistHeader(MetraColors colors, Setlist setlist) {
    final index = library.currentIndex;
    final position = index < 0 ? '–' : '${index + 1}';
    return OutlinedButton(
      key: headerKey,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: onOpenPicker,
      child: Row(
        children: [
          const Icon(Icons.notes, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              setlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            '$position of ${library.visibleSongs.length}',
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

  /// Quieter than previous/next: outlined and 52px tall, vertically
  /// centred in the 68px row.
  Widget _freePlayRow(MetraColors colors) {
    if (library.setlists.isEmpty) {
      return Center(
        child: SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onNewSetlist,
            child: const Text(
              'Create your first setlist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }
    return Center(
      child: SizedBox(
        height: 52,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: onOpenPicker,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Choose a setlist',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 18, color: colors.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Tooltip(
                message: 'New setlist',
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: onNewSetlist,
                  child: const Icon(Icons.add, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            onPressed: () => library.previousSong(metronome),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _stepButton(
            key: nextKey,
            colors: colors,
            song: next,
            forward: true,
            onPressed: () => library.nextSong(metronome),
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
