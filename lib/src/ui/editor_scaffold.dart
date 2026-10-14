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

/// The outlined "Search songs" field of the song library screens.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: BorderSide(color: colors.border, width: 2),
    );
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search songs',
        prefixIcon: Icon(Icons.search, color: colors.muted),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: border,
        enabledBorder: border,
      ),
    );
  }
}

/// Top bar of full screens that apply changes at once (song library,
/// settings): a back chevron, a title, an optional [trailing] action.
class BackBar extends StatelessWidget {
  const BackBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.divider)),
    ),
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.chevron_left, size: 28),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}
