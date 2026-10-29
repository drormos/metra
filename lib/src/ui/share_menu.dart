import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/share_export.dart';
import '../model/share_text.dart';
import 'free_play_guard.dart';
import 'haptics.dart';
import 'panel_motion.dart';
import 'theme.dart';

/// One item of a share menu: a semibold [name] with a muted [line] under
/// it saying who it's for (ui-spec.md "Sharing sets and songs").
typedef ShareItem<T> = ({T value, String name, String line});

/// The share menu (ui-spec.md "The share menu"): opens upward from the
/// button at [anchor], centred on it, its bottom edge 8px above the
/// button and 16px inside the screen edges; it grows out of the button
/// and shrinks back into it, with the panels' motion. The chosen item's
/// value, or null.
Future<T?> showShareMenu<T>(BuildContext anchor, List<ShareItem<T>> items) {
  final navigator = Navigator.of(anchor);
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final button = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return navigator.push(
    _ShareMenuRoute<T>(
      button: button,
      items: items,
      reduced: MetraMotion.reduced(anchor),
    ),
  );
}

/// The menu itself, for tests.
const shareMenuKey = Key('share-menu');

class _ShareMenuRoute<T> extends PopupRoute<T> {
  _ShareMenuRoute({
    required this.button,
    required this.items,
    required this.reduced,
  });

  final Rect button;
  final List<ShareItem<T>> items;
  final bool reduced;

  static const gap = 8.0, inset = 16.0, maxWidth = 340.0;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Close menu';

  // The panels' open and close (PanelMotion).
  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : PanelMotion.settle;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final colors = context.colors;
    final menu = Material(
      key: shareMenuKey,
      color: colors.sheet,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items)
                InkWell(
                  key: ValueKey('share-${item.value}'),
                  onTap: () => Navigator.pop(context, item.value),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
                ),
            ],
          ),
        ),
      ),
    );
    final top = MediaQuery.paddingOf(context).top + inset;
    return CustomSingleChildLayout(delegate: _Above(button, top), child: menu);
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final size = MediaQuery.sizeOf(context);
    // Scaled about the button's top centre: out of it, back into it.
    final origin = Alignment(
      button.center.dx / size.width * 2 - 1,
      button.top / size.height * 2 - 1,
    );
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: origin,
        scale: Tween(begin: PanelMotion.openScale, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// Above [button], centred on it, within the screen's 16px margins and
/// below [top] (taller menus scroll).
class _Above extends SingleChildLayoutDelegate {
  _Above(this.button, this.top);

  final Rect button;
  final double top;

  static const gap = _ShareMenuRoute.gap, inset = _ShareMenuRoute.inset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 2 * inset).clamp(
          0,
          _ShareMenuRoute.maxWidth,
        ),
        maxHeight: (button.top - gap - top).clamp(0, double.infinity),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (button.center.dx - child.width / 2).clamp(
      inset,
      size.width - inset - child.width,
    );
    return Offset(x, button.top - gap - child.height);
  }

  @override
  bool shouldRelayout(_Above old) => old.button != button || old.top != top;
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
