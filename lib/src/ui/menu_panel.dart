import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import 'about.dart';
import 'settings_screen.dart';
import 'swipe_row.dart';
import 'theme.dart';

/// Opens the Menu (ui-spec.md "Menu", `menu.reference.html`): a 304px
/// panel from the right over the dimmed main screen, a short list of
/// places to go (Settings, Send feedback, About); songs and sets are
/// managed in the main screen's lists. The click keeps playing. Tap outside, swipe right, or back closes
/// it. A row closes it and opens its page from the main screen, so back
/// from that page returns there.
Future<void> showMenuPanel(
  BuildContext context, {
  required MetronomeController metronome,
  LibraryController? library,
}) => Navigator.push(
  context,
  PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierLabel: 'Close menu',
    barrierColor: context.colors.dim,
    transitionDuration: RowGestures.motion(
      context,
      const Duration(milliseconds: 200),
    ),
    reverseTransitionDuration: RowGestures.motion(
      context,
      const Duration(milliseconds: 150),
    ),
    pageBuilder: (_, _, _) =>
        MenuPanel(metronome: metronome, library: library, pages: context),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
      child: child,
    ),
  ),
);

class MenuPanel extends StatefulWidget {
  const MenuPanel({
    super.key,
    required this.metronome,
    required this.pages,
    this.library,
  });

  final MetronomeController metronome;

  /// Null when storage is unavailable.
  final LibraryController? library;

  /// The main screen's context, for the pages the rows open.
  final BuildContext pages;

  static const width = 304.0;

  /// The panel itself (the route around it fills the screen).
  static const surfaceKey = Key('menu-surface');
  static const settingsKey = Key('menu-settings');
  static const feedbackKey = Key('menu-feedback');
  static const aboutKey = Key('menu-about');
  static const versionKey = Key('menu-version');

  @override
  State<MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<MenuPanel> {
  /// Closes the panel, then opens [page] from the main screen.
  void _go(void Function(BuildContext pages) page) {
    Navigator.pop(context);
    page(widget.pages);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = widget.library;
    final metronome = widget.metronome;
    final padding = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.centerRight,
      // Swiped toward the right edge it follows the finger and closes past a
      // third (or on a flick). A screen reader stays inside, reading "Menu".
      child: DragToClose(
        axis: Axis.horizontal,
        onClose: () => Navigator.pop(context),
        child: BlockSemantics(
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: 'Menu',
            child: Material(
              color: colors.sheet,
              child: Container(
                key: MenuPanel.surfaceKey,
                width: MenuPanel.width,
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: colors.border)),
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  padding.top + 8,
                  20,
                  padding.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: 44,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Menu',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          _row(
                            key: MenuPanel.settingsKey,
                            icon: const Icon(Icons.settings_outlined, size: 20),
                            title: 'Settings',
                            detail: 'Sound, volume, theme',
                            onTap: () => _go(
                              (pages) => openSettings(
                                pages,
                                metronome: metronome,
                                library: library,
                              ),
                            ),
                          ),
                          _row(
                            key: MenuPanel.feedbackKey,
                            title: 'Send feedback',
                            detail: "Tell Dror what works and what doesn't",
                            onTap: () => _go(sendFeedback),
                          ),
                          _row(
                            key: MenuPanel.aboutKey,
                            title: 'About Metra',
                            detail: 'Why this app exists',
                            onTap: () => _go(
                              (pages) => Navigator.push(
                                pages,
                                MaterialPageRoute<void>(
                                  builder: (_) => const AboutScreen(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VersionLine(key: MenuPanel.versionKey),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 56px, a 22px icon column (empty without an icon, so labels line up),
  /// the label with an optional muted line, a muted count and ›.
  Widget _row({
    required Key key,
    required String title,
    required VoidCallback onTap,
    Widget? icon,
    String? detail,
    int? count,
  }) {
    final colors = context.colors;
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider)),
        ),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                ],
              ),
            ),
            if (count != null) ...[
              Text(
                '$count',
                style: TextStyle(fontSize: 14, color: colors.muted),
              ),
              const SizedBox(width: 10),
            ],
            Icon(Icons.chevron_right, size: 22, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
