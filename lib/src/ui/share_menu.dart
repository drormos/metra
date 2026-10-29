import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/share_export.dart';
import '../model/share_text.dart';
import 'free_play_guard.dart';
import 'haptics.dart';
import 'theme.dart';

/// One item of a share menu: a semibold [name] with a muted [line] under
/// it saying who it's for (ui-spec.md "Sharing sets and songs").
typedef ShareItem<T> = ({T value, String name, String line});

/// The share menu, the "At the end" menu's style, dropping from the button
/// at [anchor]: the chosen item's value, or null.
Future<T?> showShareMenu<T>(BuildContext anchor, List<ShareItem<T>> items) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero, ancestor: overlay),
    box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
  );
  final colors = anchor.colors;
  return showMenu<T>(
    context: anchor,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          key: ValueKey('share-${item.value}'),
          value: item.value,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                item.line,
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
            ],
          ),
        ),
    ],
  );
}

/// The menus' lines (ui-spec.md "The share menu").
abstract final class ShareMenus {
  static const forImport =
      'From a Metra export someone sent you (copy their message first)';
  static const nothing = 'Nothing to add';
  static const nothingLine = 'Copy the whole Metra message, then try again.';
}

/// Imports the Metra export in [text] (null: the clipboard, read only now):
/// the check dialog, then the songs and set are added and what was shared
/// loads. True when something was loaded (the caller closes its panel).
Future<bool> importShared(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome, {
  String? text,
}) async {
  text ??= (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  if (!context.mounted) return false;
  final plan = library.planImport(text);
  final shared = plan?.shared;
  if (plan == null || shared == null || shared.songs.isEmpty) {
    await _notice(
      context,
      ShareMenus.nothing,
      shared == null
          ? ShareMenus.nothingLine
          : '${_songs(shared.skipped)} ${shared.skipped == 1 ? 'needs' : 'need'} '
                'a newer Metra.',
    );
    return false;
  }
  // Everything is already here: it simply opens.
  final same = shared.isSet ? plan.sameSet != null : plan.newSongs.isEmpty;
  if (same) {
    await _notice(
      context,
      shared.isSet ? 'You already have this set' : 'You already have this song',
      'Opening "${plan.sameSet?.name ?? library.songById(plan.ids.first)!.name}".',
    );
  } else if (!await _check(context, plan) || !context.mounted) {
    return false;
  }
  if (!context.mounted || !await leaveFreePlay(context, library, metronome)) {
    return false;
  }
  Haptics.medium();
  library.applyImport(plan, metronome);
  return true;
}

String _songs(int n) => n == 1 ? '1 song' : '$n songs';

/// The check before adding (ui-spec.md "The check before adding").
Future<bool> _check(BuildContext context, ImportPlan plan) async {
  final shared = plan.shared;
  final set = plan.newSet;
  final title = shared.isSet
      ? 'Add "${shared.setName}"?'
      : 'Add "${shared.songs.single.name}"?';
  final lines = [
    if (shared.isSet)
      '${_songs(shared.order.length)}'
          '${plan.withParts == 0 ? '' : ', ${plan.withParts} with parts'}.'
    else
      '${songShareLine(shared.songs.single)}.',
    if (plan.existing > 0)
      '${_songs(plan.existing)} you already have, '
          '${plan.newSongs.length} new.',
    for (final (from, to) in plan.renamed.take(3))
      '"$from" is different from yours: added as "$to".',
    if (plan.renamed.length > 3)
      'And ${plan.renamed.length - 3} more added as "(shared)".',
    if (set != null && set.name != shared.setName)
      'You have another set with this name: added as "${set.name}".',
    if (shared.skipped > 0)
      '${_songs(shared.skipped)} ${shared.skipped == 1 ? 'needs' : 'need'} '
          'a newer Metra.',
  ];
  final add = await showDialog<bool>(
    context: context,
    builder: (context) => _ShareDialog(
      title: title,
      lines: lines,
      actions: [
        (ShareDialogKeys.cancel, 'Cancel', false, false),
        (
          ShareDialogKeys.add,
          shared.isSet ? 'Add set' : 'Add song',
          true,
          true,
        ),
      ],
    ),
  );
  return add ?? false;
}

Future<void> _notice(BuildContext context, String title, String line) =>
    showDialog<void>(
      context: context,
      builder: (context) => _ShareDialog(
        title: title,
        lines: [line],
        actions: const [(ShareDialogKeys.ok, 'OK', null, true)],
      ),
    );

/// The dialogs' buttons, for tests.
abstract final class ShareDialogKeys {
  static const cancel = Key('share-dialog-cancel');
  static const add = Key('share-dialog-add');
  static const ok = Key('share-dialog-ok');
}

/// The leave dialog's look: a title, muted lines, then the buttons
/// (the filled one last), stacked when they don't fit on one line.
class _ShareDialog extends StatelessWidget {
  const _ShareDialog({
    required this.title,
    required this.lines,
    required this.actions,
  });

  final String title;
  final List<String> lines;

  /// Key, label, the value it closes with, and whether it's filled.
  final List<(Key, String, bool?, bool)> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const label = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            for (final line in lines) ...[
              const SizedBox(height: 8),
              Text(
                line,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colors.muted,
                ),
              ),
            ],
            const SizedBox(height: 18),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                for (final (key, text, value, filled) in actions)
                  filled
                      ? FilledButton(
                          key: key,
                          style: FilledButton.styleFrom(
                            foregroundColor: colors.background,
                            backgroundColor: colors.text,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => Navigator.pop(context, value),
                          child: Text(text, style: label),
                        )
                      : TextButton(
                          key: key,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.muted,
                            minimumSize: const Size(48, 48),
                          ),
                          onPressed: () => Navigator.pop(context, value),
                          child: Text(text, style: label),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
