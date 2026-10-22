import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared frame for full-screen editors (setlist, song, library pick):
/// a top bar with a text "Cancel" on the left, a centred title and an
/// optional small primary action on the right, a divider, then [body].
/// With [dirty] changes, Cancel and system back ask to discard first.
class EditorScaffold extends StatelessWidget {
  const EditorScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.dirty = false,
    this.bottom,
  });

  final String title;
  final Widget body;
  final String? actionLabel;

  /// Null disables the action (e.g. Save with an empty name).
  final VoidCallback? onAction;
  final bool dirty;

  /// Pinned under the body, above a divider.
  final Widget? bottom;

  static const cancelKey = Key('editor-cancel');
  static const actionKey = Key('editor-action');

  Future<void> _cancel(BuildContext context) async {
    if (!dirty || await confirm(context, 'Discard your changes?', 'Discard')) {
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.divider)),
                ),
                child: SizedBox(
                  height: 44,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: cancelKey,
                          onPressed: () => _cancel(context),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      if (actionLabel != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            height: 44,
                            child: FilledButton(
                              key: actionKey,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                              ),
                              onPressed: onAction,
                              child: Text(
                                actionLabel!,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: body),
              if (bottom != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.divider)),
                  ),
                  child: bottom,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A yes/no dialog; true when [confirmLabel] is chosen.
Future<bool> confirm(
  BuildContext context,
  String message,
  String confirmLabel,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

/// "Delete …?" before a swipe deletes your own work (ui-spec.md "Delete
/// asks, remove undoes", `delete-confirm.reference.html`): the title, an
/// optional muted line, Cancel (outlined) and Delete (red, filled). True
/// when Delete was chosen.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  String? body,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = context.colors;
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
                if (body != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: colors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        key: deleteCancelKey,
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        key: deleteConfirmKey,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.accent,
                          foregroundColor: colors.background,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ) ??
    false;

const deleteCancelKey = Key('delete-cancel');
const deleteConfirmKey = Key('delete-confirm');

/// An outlined text field with a small muted label above it.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.style,
    this.autofocus = false,
    this.onChanged,
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final TextStyle? style;
  final bool autofocus;
  final ValueChanged<String>? onChanged;

  /// Shown under the field, which turns red.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: colors.border, width: 2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: colors.muted)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          autofocus: autofocus,
          onChanged: onChanged,
          style: style,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: colors.text, width: 2),
            ),
            errorText: error,
            errorStyle: TextStyle(color: colors.accentSounding, fontSize: 13),
            errorBorder: border.copyWith(
              borderSide: BorderSide(color: colors.accentSounding, width: 2),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: BorderSide(color: colors.accentSounding, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// The outlined search field (song library, What to play, the dropdown
/// lists): a white border while focused, × clears what's typed.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    this.onChanged,
    this.hint = 'Search songs',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hint;

  static const clearKey = Key('search-clear');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: colors.controlOutline, width: 2),
    );
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        // The search key closes the keyboard; the results stay.
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search, color: colors.muted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: clearKey,
                  tooltip: 'Clear',
                  icon: Icon(Icons.close, color: colors.muted),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: colors.text, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Top bar of full screens that apply changes at once (song library,
/// settings): a back chevron and a title, [centered] or after the chevron.
class BackBar extends StatelessWidget {
  const BackBar({
    super.key,
    required this.title,
    this.centered = false,
    this.onBack,
  });

  final String title;
  final bool centered;

  /// Instead of popping this page.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Container(
    // The row is 48dp (the touch minimum for ‹); the padding gives back
    // the 4px, so the bar looks the same.
    padding: const EdgeInsets.fromLTRB(4, 6, 16, 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.divider)),
    ),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: centered ? TextAlign.center : TextAlign.start,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          // Balances the chevron so the title sits in the middle.
          if (centered) const SizedBox(width: 48),
        ],
      ),
    ),
  );
}

/// The two side-by-side buttons at the bottom of a list ("New song ·
/// Delete songs" and the like).
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.colors.divider)),
    ),
    child: SizedBox(height: 56, child: Row(children: children)),
  );
}

/// "N selected · Cancel" and a red [action], replacing a [BottomBar]
/// while rows are marked (removing songs, deleting sets or songs).
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.action,
    required this.actionKey,
    required this.onAction,
    required this.onCancel,
  });

  static const cancelKey = Key('selection-cancel');

  final int count;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return BottomBar(
      children: [
        Expanded(
          child: Text(
            '$count selected',
            style: TextStyle(fontSize: 15, color: colors.muted),
          ),
        ),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            key: cancelKey,
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: TextButton(
            key: actionKey,
            style: TextButton.styleFrom(
              foregroundColor: colors.accentSounding,
              minimumSize: const Size(0, 44),
            ),
            onPressed: count == 0 ? null : onAction,
            // Shrinks rather than overflowing on narrow phones.
            child: FittedBox(
              child: Text(
                action,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An empty list (ui-spec.md "Empty lists"): a title, a hint, and the
/// list's main action as a big filled button in the middle, while the
/// bottom bar is hidden. [below] goes under it (e.g. a set's footer).
class EmptyListState extends StatelessWidget {
  const EmptyListState({
    super.key,
    required this.title,
    required this.hint,
    required this.action,
    required this.actionKey,
    required this.onAction,
    this.below,
  });

  final String title;
  final String hint;
  final String action;
  final Key actionKey;
  final VoidCallback onAction;
  final Widget? below;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.hasBoundedHeight
        // Centred, yet scrolls when the keyboard leaves too little room.
        ? SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: _content(context),
            ),
          )
        // Already inside a list.
        : _content(context),
  );

  Widget _content(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: context.colors.muted,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            key: actionKey,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32),
            ),
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 20),
            label: Text(action, style: const TextStyle(fontSize: 17)),
          ),
        ),
        ?below,
      ],
    ),
  );
}
