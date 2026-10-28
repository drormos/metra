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
    // Save as song is the only filled button; Discard is red text, Cancel
    // muted text (ui-spec.md "Parts in Free play" › "Button look").
    final buttons = [
      (cancelKey, 'Cancel', _Leave.cancel, colors.muted, null),
      (discardKey, 'Discard', _Leave.discard, colors.accent, null),
      (saveKey, 'Save as song', _Leave.save, colors.background, colors.text),
    ];
    const pad = 18.0, gap = 8.0;
    Widget button((Key, String, _Leave, Color, Color?) b, {bool wide = false}) {
      final (key, label, value, color, fill) = b;
      final style =
          (fill == null ? TextButton.styleFrom : FilledButton.styleFrom)(
            foregroundColor: color,
            backgroundColor: fill,
            minimumSize: Size(wide ? double.infinity : 48, 48),
            padding: const EdgeInsets.symmetric(horizontal: pad),
          );
      void tap() => Navigator.pop(context, value);
      final text = Text(label, style: _label);
      return fill == null
          ? TextButton(key: key, style: style, onPressed: tap, child: text)
          : FilledButton(key: key, style: style, onPressed: tap, child: text);
    }

    // One line when the three fit; otherwise all three full width, the
    // filled one first (never two and one).
    final actions = LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final base = DefaultTextStyle.of(context).style.merge(_label);
        var width = gap * (buttons.length - 1);
        for (final (_, label, _, _, _) in buttons) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: base),
            textScaler: scaler,
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          width += painter.width + 2 * pad;
          painter.dispose();
        }
        if (width <= box.maxWidth) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final (i, b) in buttons.indexed) ...[
                if (i > 0) const SizedBox(width: gap),
                button(b),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, b) in buttons.reversed.indexed) ...[
              if (i > 0) const SizedBox(height: gap),
              button(b, wide: true),
            ],
          ],
        );
      },
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
            actions,
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
