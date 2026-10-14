import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/click_sound.dart';
import '../model/tempo_name.dart';
import 'beat_indicator.dart';
import 'haptics.dart';
import 'library_panel.dart';
import 'repeat_button.dart';
import 'setlist_editor.dart';
import 'setlist_group.dart';
import 'setlist_picker.dart';
import 'subdivision_icon.dart';
import 'tempo_ruler.dart';
import 'theme.dart';

/// Main screen (ui-spec.md), the same phone layout on every platform.
/// Stateless; all metronome state lives in [controller].
class MetronomeScreen extends StatelessWidget {
  const MetronomeScreen({super.key, required this.controller, this.library});

  final MetronomeController controller;

  /// Null when storage is unavailable: no song panel then.
  final LibraryController? library;

  static const bpmKey = Key('bpm');
  static const playKey = Key('play');
  static const offsetKey = Key('offset');
  static const tapKey = Key('tap');
  static const titleKey = Key('title');
  static const tempoNameKey = Key('tempo-name');
  static const meterKey = Key('meter');
  static const subdivisionKey = Key('subdivision');

  @override
  Widget build(BuildContext context) {
    final library = this.library;
    final metronome = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
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
        // Bluetooth page-turner pedals send Page Up/Down or the arrows.
        if (library != null) ...{
          const SingleActivator(LogicalKeyboardKey.pageDown): () =>
              library.nextSong(controller),
          const SingleActivator(LogicalKeyboardKey.pageUp): () =>
              library.previousSong(controller),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              library.nextSong(controller),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              library.previousSong(controller),
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            controller.nudge(1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            controller.nudge(-1),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            controller.nudge(5),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            controller.nudge(-5),
      },
      child: Focus(autofocus: true, child: Scaffold(body: metronome)),
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    final bpm = controller.bpm;
    final error = controller.audioError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topRow(context),
        const SizedBox(height: 16),
        BeatIndicator(controller: controller),
        // The BPM area takes all the free height and shrinks first on
        // small phones.
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          // An invisible twin of "bpm" balances the visible
                          // one, so the number alone is centred and "bpm"
                          // hangs off its right side.
                          ExcludeSemantics(
                            child: Visibility.maintain(
                              visible: false,
                              child: Text(
                                'bpm',
                                style: TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$bpm',
                            key: bpmKey,
                            style: const TextStyle(
                              fontFamily: MetraFonts.condensed,
                              fontSize: 172,
                              fontWeight: FontWeight.w700,
                              height: 0.85,
                              // Fixed-width digits: the readout doesn't shift.
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'bpm',
                            style: TextStyle(fontSize: 18, color: colors.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tempoName(bpm),
                        key: tempoNameKey,
                        style: TextStyle(fontSize: 16, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TempoRuler(controller: controller),
            ],
          ),
        ),
        Row(
          children: [
            _step('−5', -5, bpm > MetronomeController.minBpm),
            const SizedBox(width: 8),
            _step('−1', -1, bpm > MetronomeController.minBpm),
            const SizedBox(width: 8),
            _step('+1', 1, bpm < MetronomeController.maxBpm),
            const SizedBox(width: 8),
            _step('+5', 5, bpm < MetronomeController.maxBpm),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: playKey,
                  onPressed: () {
                    Haptics.medium();
                    controller.toggle();
                  },
                  icon: Icon(
                    controller.isPlaying ? Icons.stop : Icons.play_arrow,
                    size: 24,
                  ),
                  label: Text(
                    controller.isPlaying ? 'Stop' : 'Start',
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                // Tap registers on pointer down: tap-up timing varies with
                // how long the finger rests, which skews the tempo.
                child: Listener(
                  onPointerDown: (_) {
                    Haptics.tick();
                    controller.tap();
                  },
                  child: OutlinedButton(
                    key: tapKey,
                    onPressed: () {},
                    child: const Text('Tap', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (library case final library?) ...[
          const SizedBox(height: 12),
          SetlistGroup(
            library: library,
            metronome: controller,
            onOpenPicker: () => showSetlistPicker(
              context,
              library: library,
              metronome: controller,
              onEditSetlist: () => openSetlistEditor(
                context,
                library,
                setlist: library.activeSetlist,
                newSong: (context) => _newSong(context, library),
              ),
              // The old song panel stands in for the song library until
              // Phase 5.
              onSongLibrary: () => _showSongs(context, library),
              onNewSetlist: () => _newSetlist(context, library),
            ),
            onNewSetlist: () => _newSetlist(context, library),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            'Audio problem: $error',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.accentSounding),
          ),
        ],
      ],
    );
  }

  /// Song title, then subdivision, time signature and settings buttons.
  Widget _topRow(BuildContext context) {
    final pattern = controller.pattern;
    return Row(
      children: [
        Expanded(
          child: Text(
            library?.currentSong?.name ?? '',
            key: titleKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: MetraFonts.condensed,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _squareButton(
          key: subdivisionKey,
          tooltip: 'Subdivision: ${_subdivisionNames[pattern.stepsPerBeat]}',
          // Cycles 1 → 2 → 3 → 4 → 1; while playing, from the next beat.
          onPressed: () {
            Haptics.tick();
            controller.setSubdivision(pattern.stepsPerBeat % 4 + 1);
          },
          child: SubdivisionIcon(pattern.stepsPerBeat),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: Builder(
            builder: (context) => OutlinedButton(
              key: meterKey,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(44, 44),
              ),
              onPressed: () => _showMeterPicker(context),
              child: Text(
                pattern.timeSignature,
                style: const TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Builder(
          builder: (context) => _squareButton(
            tooltip: 'Settings',
            onPressed: () => _showSettings(context),
            child: const Icon(Icons.tune, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _squareButton({
    Key? key,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget child,
  }) => Tooltip(
    message: tooltip,
    child: SizedBox.square(
      dimension: 44,
      child: OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(44),
        ),
        onPressed: onPressed,
        child: child,
      ),
    ),
  );

  static const _subdivisionNames = {
    1: 'quarter notes',
    2: 'eighth notes',
    3: 'triplets',
    4: 'sixteenth notes',
  };

  static const _meters = [
    (2, 4),
    (3, 4),
    (4, 4),
    (5, 4),
    (6, 8),
    (7, 8),
    (9, 8),
    (12, 8),
  ];

  /// Plain picker (the spec leaves it undesigned). Changing the time
  /// signature resets custom accents; while playing, the next beat starts a
  /// bar in the new meter.
  void _showMeterPicker(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (beats, unit) in _meters)
                ChoiceChip(
                  label: Text('$beats/$unit'),
                  selected: controller.pattern.timeSignature == '$beats/$unit',
                  onSelected: (_) {
                    Haptics.tick();
                    controller.setMeter(beats, unit);
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _newSetlist(BuildContext context, LibraryController library) =>
      openSetlistEditor(
        context,
        library,
        newSong: (context) => _newSong(context, library),
      );

  // Until the song editor (Phase 5): saves the current tempo and pattern
  // under a name. Returns the new song's id.
  Future<String?> _newSong(
    BuildContext context,
    LibraryController library,
  ) async {
    final name = await askName(
      context,
      title: 'New song',
      initial: '${controller.bpm} BPM',
    );
    if (name == null) return null;
    return library
        .addSong(name: name, bpm: controller.bpm, pattern: controller.pattern)
        .id;
  }

  void _showSongs(BuildContext context, LibraryController library) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
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
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ListenableBuilder(
          listenable: Listenable.merge([controller, ?library]),
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (library case final library?) ...[
                _themePicker(Theme.of(context), library),
                const SizedBox(height: 16),
              ],
              _soundPicker(Theme.of(context)),
              const SizedBox(height: 16),
              _offsetControl(Theme.of(context)),
            ],
          ),
        ),
      ),
    ),
  );

  static const _themeModes = {
    ThemeMode.system: 'System',
    ThemeMode.dark: 'Dark',
    ThemeMode.light: 'Light',
  };

  Widget _themePicker(ThemeData theme, LibraryController library) => Column(
    children: [
      Text('Theme', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          for (final MapEntry(key: mode, value: label) in _themeModes.entries)
            ChoiceChip(
              label: Text(label),
              selected: library.themeMode == mode,
              onSelected: (_) => library.setThemeMode(mode),
            ),
        ],
      ),
    ],
  );

  Widget _soundPicker(ThemeData theme) => Column(
    children: [
      Text('Click sound', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final sound in ClickSound.values)
            ChoiceChip(
              label: Text(sound.label),
              selected: controller.clickSound == sound,
              onSelected: (_) => controller.setClickSound(sound),
            ),
        ],
      ),
    ],
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
    child: SizedBox(
      height: 60,
      child: Builder(
        // Holding repeats (ui-spec.md).
        builder: (context) => RepeatButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.surface,
            foregroundColor: context.colors.text,
            padding: EdgeInsets.zero,
          ),
          onPressed: enabled
              ? () {
                  Haptics.tick();
                  controller.nudge(delta);
                }
              : null,
          // Shrinks instead of wrapping on narrow phones.
          child: FittedBox(
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: MetraFonts.condensed,
                fontSize: 28,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
