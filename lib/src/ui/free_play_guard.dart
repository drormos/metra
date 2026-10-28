import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import 'save_as_new_dialog.dart';
import 'theme.dart';

/// Before leaving Free play for a song or a set (ui-spec.md "Parts in Free
/// play" › "Nothing is lost by accident"): when Free play has parts (2+, a
/// Gradual one, or an end other than Loop last part), asks "Save your song
/// parts?". Save as song saves them through the New song dialog, Discard
/// drops them (one plain part again); either way it's true, go on. Cancel
/// (or closing the dialog) is false: stay. Without parts, true at once.
Future<bool> leaveFreePlay(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome,
) async {
  final parts = metronome.parts;
  if (library.currentSong != null || parts == null || !metronome.playsParts) {
    return true;
  }
  final choice = await showDialog<_Leave>(
    context: context,
    builder: (context) => _LeaveDialog(count: parts.length),
  );
  switch (choice) {
    case _Leave.save:
      return context.mounted &&
          await showSaveAsNewSong(context, library, metronome);
    case _Leave.discard:
      metronome.dropParts();
      return true;
    case _Leave.cancel || null:
      return false;
  }
}

enum _Leave { cancel, discard, save }

class _LeaveDialog extends StatelessWidget {
  const _LeaveDialog({required this.count});

  final int count;

  static const cancelKey = Key('leave-free-play-cancel');
  static const discardKey = Key('leave-free-play-discard');
  static const saveKey = Key('leave-free-play-save');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget button(Key key, String label, _Leave value, {Color? fill}) =>
        SizedBox(
          height: 48,
          child: fill == null
              ? OutlinedButton(
                  key: key,
                  onPressed: () => Navigator.pop(context, value),
                  child: Text(label, style: _label),
                )
              : FilledButton(
                  key: key,
                  style: FilledButton.styleFrom(
                    backgroundColor: fill,
                    foregroundColor: colors.background,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  onPressed: () => Navigator.pop(context, value),
                  child: Text(label, style: _label),
                ),
        );
    return Dialog(
      backgroundColor: colors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Save your song parts?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              count == 1
                  ? 'Free play has 1 part that isn\'t saved.'
                  : 'Free play has $count parts that aren\'t saved.',
              style: TextStyle(fontSize: 14, height: 1.45, color: colors.muted),
            ),
            const SizedBox(height: 18),
            // Wraps rather than overflowing (long labels, large text).
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                button(cancelKey, 'Cancel', _Leave.cancel),
                button(
                  discardKey,
                  'Discard',
                  _Leave.discard,
                  fill: colors.accent,
                ),
                button(saveKey, 'Save as song', _Leave.save, fill: colors.text),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const _label = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
}

/// The dialog's buttons, for tests.
abstract final class LeaveFreePlayKeys {
  static const cancel = _LeaveDialog.cancelKey;
  static const discard = _LeaveDialog.discardKey;
  static const save = _LeaveDialog.saveKey;
}
