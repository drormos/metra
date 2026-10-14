import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/click_sound.dart';
import '../model/click_volumes.dart';
import '../model/metronome_pattern.dart';
import 'editor_scaffold.dart';
import 'meter_control.dart';
import 'segmented.dart';
import 'theme.dart';

/// Opens settings (ui-spec.md "Settings", `settings.reference.html`).
/// Changes apply at once. Leaving stops a visual offset test that started
/// the click.
Future<void> openSettings(
  BuildContext context, {
  required MetronomeController metronome,
  LibraryController? library,
  VoidCallback? onSetlists,
  VoidCallback? onSongLibrary,
}) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        metronome: metronome,
        library: library,
        onSetlists: onSetlists,
        onSongLibrary: onSongLibrary,
      ),
    ),
  );
  metronome.endOffsetTest();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.metronome,
    this.library,
    this.onSetlists,
    this.onSongLibrary,
  });

  final MetronomeController metronome;

  /// Null when storage is unavailable: no Your music, theme or vibration.
  final LibraryController? library;
  final VoidCallback? onSetlists;
  final VoidCallback? onSongLibrary;

  static const vibrateKey = Key('settings-vibrate');
  static const resetKey = Key('settings-volume-reset');
  static const offsetKey = Key('settings-offset');
  static const testKey = Key('settings-offset-test');

  static const _themes = {
    ThemeMode.system: 'System',
    ThemeMode.dark: 'Dark',
    ThemeMode.light: 'Light',
  };

  @override
  Widget build(BuildContext context) {
    final library = this.library;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackBar(title: 'Settings'),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([metronome, ?library]),
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  children: [
                    if (library != null) ...[
                      _section(context, 'Your music', _yourMusic(context)),
                      _section(
                        context,
                        'Theme',
                        Segmented(
                          options: _themes,
                          selected: library.themeMode,
                          onSelected: library.setThemeMode,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    _section(context, 'Click sound', _clickSound(context)),
                    if (library != null)
                      _section(context, 'Vibration', _vibration(context)),
                    _volumeSection(context),
                    _section(context, 'Visual offset', _offset(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    Widget child, {
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: action == null ? null : 44,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 14, color: context.colors.muted),
                ),
              ),
              ?action,
            ],
          ),
        ),
        SizedBox(height: action == null ? 12 : 2),
        child,
      ],
    ),
  );

  Widget _yourMusic(BuildContext context) {
    final colors = context.colors;
    final library = this.library!;
    String count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
    Widget row(String title, String detail, VoidCallback? onTap, bool last) =>
        InkWell(
          onTap: onTap,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: last
                  ? null
                  : Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        detail,
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: colors.muted),
              ],
            ),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            row(
              'Setlists',
              count(library.setlists.length, 'setlist'),
              onSetlists,
              false,
            ),
            row(
              'Song library',
              count(library.songs.length, 'song'),
              onSongLibrary,
              true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _clickSound(BuildContext context) {
    final colors = context.colors;
    final sounds = ClickSound.values;
    Widget button(ClickSound sound) {
      final selected = metronome.clickSound == sound;
      return SizedBox(
        height: 48,
        child: OutlinedButton(
          key: ValueKey('sound-${sound.name}'),
          style: OutlinedButton.styleFrom(
            backgroundColor: selected ? colors.text : null,
            foregroundColor: selected ? colors.background : colors.text,
            side: selected ? BorderSide.none : null,
          ),
          // Plays a short sample while stopped.
          onPressed: () => metronome.setClickSound(sound),
          child: Text(
            sound.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sounds.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(child: button(sounds[i])),
                const SizedBox(width: 8),
                Expanded(child: button(sounds[i + 1])),
              ],
            ),
          ),
        Text(
          'Tapping a sound selects it and plays a short sample.',
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
      ],
    );
  }

  Widget _vibration(BuildContext context) {
    final colors = context.colors;
    final library = this.library!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.divider, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: SwitchListTile(
        key: vibrateKey,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        title: const Text(
          'Vibrate on touch',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          "Only when vibration is on in your phone's settings",
          style: TextStyle(fontSize: 13, color: colors.muted),
        ),
        value: library.vibrate,
        onChanged: library.setVibrate,
      ),
    );
  }

  Widget _volumeSection(BuildContext context) {
    final volumes = metronome.volumes;
    Widget slider(
      String label,
      double value,
      ClickVolumes Function(double) update,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(fontSize: 16, color: context.colors.muted),
            ),
          ],
        ),
        Slider(
          value: value,
          divisions: 100,
          label: '${(value * 100).round()}%',
          semanticFormatterCallback: (v) => '${(v * 100).round()}%',
          onChanged: (v) => metronome.setVolumes(update(v)),
        ),
      ],
    );
    return _section(
      context,
      'Volume',
      Column(
        children: [
          slider('Accent', volumes.accent, (v) => volumes.copyWith(accent: v)),
          slider('Beat', volumes.beat, (v) => volumes.copyWith(beat: v)),
          slider(
            'Subdivision',
            volumes.subdivision,
            (v) => volumes.copyWith(subdivision: v),
          ),
        ],
      ),
      action: TextButton(
        key: resetKey,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.text,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        // Only the three volumes.
        onPressed: () => metronome.setVolumes(ClickVolumes.defaults),
        child: const Text(
          'Reset',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _offset(BuildContext context) {
    final colors = context.colors;
    final ms = metronome.visualOffset.inMilliseconds;
    const step = Duration(milliseconds: 10);
    final playing = metronome.isPlaying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OffsetFlash(metronome: metronome),
        const SizedBox(height: 12),
        Row(
          children: [
            Tooltip(
              message: 'Flash earlier',
              child: StepButton(
                '−',
                size: 52,
                fontSize: 28,
                accelerate: false,
                onPressed:
                    metronome.visualOffset > MetronomeController.minVisualOffset
                    ? () => metronome.setVisualOffset(
                        metronome.visualOffset - step,
                      )
                    : null,
              ),
            ),
            Expanded(
              child: Text(
                '${ms > 0 ? '+' : ''}$ms ms',
                key: offsetKey,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Tooltip(
              message: 'Flash later',
              child: StepButton(
                '+',
                size: 52,
                fontSize: 28,
                accelerate: false,
                onPressed:
                    metronome.visualOffset < MetronomeController.maxVisualOffset
                    ? () => metronome.setVisualOffset(
                        metronome.visualOffset + step,
                      )
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: testKey,
            onPressed: playing ? metronome.stop : metronome.startOffsetTest,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow, size: 20),
            label: Text(
              playing ? 'Stop test' : 'Start test',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'For Bluetooth headphones, whose sound arrives late: adjust until '
          'the flash lands on the click. It only moves the flash; the sound '
          "doesn't change.",
          style: TextStyle(fontSize: 13, color: colors.muted, height: 1.5),
        ),
      ],
    );
  }
}

/// A large block that flashes on every click, shifted by the visual
/// offset, read from the engine clock once per frame (like the beat
/// blocks).
class _OffsetFlash extends StatefulWidget {
  const _OffsetFlash({required this.metronome});

  final MetronomeController metronome;

  @override
  State<_OffsetFlash> createState() => _OffsetFlashState();
}

class _OffsetFlashState extends State<_OffsetFlash>
    with SingleTickerProviderStateMixin {
  static const _flash = Duration(milliseconds: 80);

  late final Ticker _ticker = createTicker(_onTick);

  // Display-only, derived from the engine clock every frame.
  int? _lastStep;
  Duration _litUntil = Duration.zero;
  bool _lit = false;

  MetronomeController get _metronome => widget.metronome;

  @override
  void initState() {
    super.initState();
    _metronome.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _metronome.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  // Tick only while playing.
  void _sync() {
    if (_metronome.isPlaying) {
      if (!_ticker.isActive) {
        _metronome.resetVisualClock(); // ticker elapsed restarts at zero
        _ticker.start();
      }
    } else {
      _ticker.stop();
      _lastStep = null;
      if (_lit) setState(() => _lit = false);
    }
  }

  void _onTick(Duration elapsed) {
    final ScheduledStep? step = _metronome.visualStepAt(elapsed);
    if (step != null && step.index != _lastStep) {
      _lastStep = step.index;
      if (step.level != StepLevel.silent) _litUntil = elapsed + _flash;
    }
    final lit = elapsed < _litUntil;
    if (lit != _lit) setState(() => _lit = lit);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: _lit ? colors.text : colors.surface,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        'Flashes on every click',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _lit ? colors.background : colors.muted,
        ),
      ),
    );
  }
}
