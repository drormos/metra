import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/metronome_controller.dart';
import 'beat_indicator.dart';

/// Main screen: tempo readout, tempo steps and transport. Stateless; all
/// metronome state lives in [controller].
class MetronomeScreen extends StatelessWidget {
  const MetronomeScreen({super.key, required this.controller});

  final MetronomeController controller;

  static const bpmKey = Key('bpm');
  static const playKey = Key('play');
  static const offsetKey = Key('offset');
  static const tapKey = Key('tap');

  @override
  Widget build(BuildContext context) {
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
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune),
                  onPressed: () => _showSettings(context),
                ),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => _content(context),
                  ),
                ),
              ),
            ),
          ),
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

  void _showSettings(BuildContext context) => showModalBottomSheet<void>(
    context: context,
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
          child: Text(
            label,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
  );
}
