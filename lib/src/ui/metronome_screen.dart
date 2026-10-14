import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import 'beat_indicator.dart';
import 'library_panel.dart';

/// Main screen: tempo readout, tempo steps and transport, plus the song
/// panel (beside it on wide screens, in a sheet on phones). Stateless; all
/// metronome state lives in [controller].
class MetronomeScreen extends StatelessWidget {
  const MetronomeScreen({super.key, required this.controller, this.library});

  final MetronomeController controller;

  /// Null when storage is unavailable: no song panel then.
  final LibraryController? library;

  // Lifted off the black screen so a sheet's edge is visible.
  static const _sheetColor = Color(0xFF1C1C1C);

  /// From this width the song panel sits beside the metronome.
  static const sidePanelWidth = 800.0;

  static const bpmKey = Key('bpm');
  static const playKey = Key('play');
  static const offsetKey = Key('offset');
  static const tapKey = Key('tap');
  static const songNameKey = Key('song-name');

  @override
  Widget build(BuildContext context) {
    final library = this.library;
    final wide = MediaQuery.sizeOf(context).width >= sidePanelWidth;
    final metronome = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, ?library]),
              builder: (context, _) => _content(context),
            ),
          ),
        ),
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): controller.toggle,
        const SingleActivator(LogicalKeyboardKey.keyT): controller.tap,
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            controller.nudge(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            controller.nudge(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            controller.nudge(10),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            controller.nudge(-10),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            actions: [
              if (library != null && !wide)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Songs',
                    icon: const Icon(Icons.queue_music),
                    onPressed: () => _showSongs(context, library),
                  ),
                ),
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _showSettings(context),
                ),
              ),
            ],
          ),
          body: library != null && wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: metronome),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: 340,
                      child: SafeArea(
                        child: LibraryPanel(
                          library: library,
                          metronome: controller,
                        ),
                      ),
                    ),
                  ],
                )
              : metronome,
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final bpm = controller.bpm;
    final error = controller.audioError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (library?.currentSong case final song?)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              song.name,
              key: songNameKey,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
          ),
        BeatIndicator(controller: controller),
        const SizedBox(height: 24),
        // Shrinks to fit short windows (landscape phones, small desktops).
        Flexible(
          child: FittedBox(
            child: Text(
              '$bpm',
              key: bpmKey,
              style: theme.textTheme.displayLarge?.copyWith(
                fontSize: 160,
                fontWeight: FontWeight.w700,
                // Fixed-width digits so the readout doesn't shift as it changes.
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1,
              ),
            ),
          ),
        ),
        Text(
          'BPM',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 4),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            _step('-10', -10, bpm > MetronomeController.minBpm),
            _step('-1', -1, bpm > MetronomeController.minBpm),
            _step('+1', 1, bpm < MetronomeController.maxBpm),
            _step('+10', 10, bpm < MetronomeController.maxBpm),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // Tap registers on pointer down: tap-up timing varies with
                // how long the finger rests, which skews the tempo.
                child: Listener(
                  onPointerDown: (_) => controller.tap(),
                  child: OutlinedButton(
                    key: tapKey,
                    onPressed: () {},
                    child: const Text(
                      'Tap',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: playKey,
                  onPressed: controller.toggle,
                  child: Text(
                    controller.isPlaying ? 'Stop' : 'Play',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 24),
          Text(
            'Audio problem: $error',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  void _showSongs(BuildContext context, LibraryController library) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: _sheetColor,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.8,
          child: SafeArea(
            child: LibraryPanel(library: library, metronome: controller),
          ),
        ),
      );

  void _showSettings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: _sheetColor,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _offsetControl(Theme.of(context)),
        ),
      ),
    ),
  );

  // Calibrates the flash against what you hear (output latency varies by
  // device, e.g. Bluetooth headphones).
  Widget _offsetControl(ThemeData theme) {
    final ms = controller.visualOffset.inMilliseconds;
    const step = Duration(milliseconds: 10);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Flash offset', style: theme.textTheme.bodyMedium),
        IconButton(
          tooltip: 'Flash earlier',
          onPressed:
              controller.visualOffset > MetronomeController.minVisualOffset
              ? () => controller.setVisualOffset(controller.visualOffset - step)
              : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            '${ms > 0 ? '+' : ''}$ms ms',
            key: offsetKey,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Flash later',
          onPressed:
              controller.visualOffset < MetronomeController.maxVisualOffset
              ? () => controller.setVisualOffset(controller.visualOffset + step)
              : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _step(String label, int delta, bool enabled) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 64,
        child: OutlinedButton(
          onPressed: enabled ? () => controller.nudge(delta) : null,
          // Shrinks instead of wrapping on narrow phones.
          child: FittedBox(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    ),
  );
}
