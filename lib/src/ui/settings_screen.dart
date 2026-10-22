import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/click_scheduler.dart';
import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/click_sound.dart';
import '../model/click_volumes.dart';
import '../model/metronome_pattern.dart';
import '../model/whats_new.dart';
import 'about.dart';
import 'editor_scaffold.dart';
import 'meter_control.dart';
import 'segmented.dart';
import 'theme.dart';

/// Opens Settings (ui-spec.md "Settings", `settings.reference.html`),
/// from the gear button. Changes apply at once. Opening clears the gear's
/// update dot; leaving stops a visual offset test that started the click.
Future<void> openSettings(
  BuildContext context, {
  required MetronomeController metronome,
  LibraryController? library,
}) async {
  WhatsNew.settingsOpened(library);
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(metronome: metronome, library: library),
    ),
  );
  metronome.endOffsetTest();
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.metronome, this.library});

  final MetronomeController metronome;

  /// Null when storage is unavailable: no theme or vibration.
  final LibraryController? library;

  static const vibrateKey = Key('settings-vibrate');
  static const resetKey = Key('settings-volume-reset');
  static const offsetKey = Key('settings-offset');
  static const testKey = Key('settings-offset-test');
  static const whatsNewKey = Key('settings-whats-new');
  static const allUpdatesKey = Key('settings-all-updates');
  static const gotItKey = Key('settings-got-it');
  static const feedbackKey = Key('settings-feedback');
  static const allUpdatesRowKey = Key('settings-all-updates-row');
  static const aboutKey = Key('settings-about');
  static const versionKey = Key('settings-version');

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
                    if (WhatsNew.showBlock(library))
                      if (WhatsNew.latest case final latest?)
                        _whatsNew(context, latest, library!),
                    if (library != null) ...[
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
                    _about(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// After an update, at the top: "New in 1.4.0", up to 3 lines, and two
  /// quiet buttons, "All updates ›" and "Got it" (hides it until the next
  /// update).
  Widget _whatsNew(
    BuildContext context,
    Release latest,
    LibraryController library,
  ) {
    final colors = context.colors;
    ButtonStyle quiet(Color color) => TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
    return Container(
      key: whatsNewKey,
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
      decoration: BoxDecoration(
        color: colors.sheet,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New in ${latest.version}',
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
          for (final line in latest.lines.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(line, style: const TextStyle(fontSize: 15)),
            ),
          // Wraps rather than overflowing with large text.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: allUpdatesKey,
                style: quiet(colors.muted),
                onPressed: () => openAllUpdates(context),
                child: const Text('All updates ›'),
              ),
              TextButton(
                key: gotItKey,
                style: quiet(colors.text),
                onPressed: () => WhatsNew.markSeen(library),
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The last section: Send feedback, All updates, About Metra, then the
  /// version line (long-press copies it).
  Widget _about(BuildContext context) {
    final colors = context.colors;
    Widget row(Key key, String title, VoidCallback onTap, {String? detail}) =>
        InkWell(
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
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16)),
                      if (detail != null)
                        Text(
                          detail,
                          style: TextStyle(fontSize: 12, color: colors.muted),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 22, color: colors.muted),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'About',
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ),
        row(
          feedbackKey,
          'Send feedback',
          () => sendFeedback(context),
          detail: "Tell Dror what works and what doesn't",
        ),
        row(allUpdatesRowKey, 'All updates', () => openAllUpdates(context)),
        row(
          aboutKey,
          'About Metra',
          () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
          ),
          detail: 'Why this app exists',
        ),
        const SizedBox(height: 6),
        const VersionLine(key: versionKey),
      ],
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
          height: action == null ? null : 48,
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
          slider(
            'Polyrhythm',
            volumes.polyrhythm,
            (v) => volumes.copyWith(polyrhythm: v),
          ),
        ],
      ),
      action: TextButton(
        key: resetKey,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.text,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
        // Only the four volumes.
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
