import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/on_start.dart';
import '../model/tempo_name.dart';
import '../model/whats_new.dart';
import 'beat_indicator.dart';
import 'fit_text.dart';
import 'haptics.dart';
import 'motion.dart';
import 'on_start_sheet.dart';
import 'parts_page.dart';
import 'poly_lane.dart';
import 'setlist_group.dart';
import 'save_as_new_dialog.dart';
import 'settings_screen.dart';
import 'icons.dart';
import 'subdivision_icon.dart';
import 'tempo_controls.dart';
import 'tempo_ruler.dart';
import 'time_signature_sheet.dart';
import 'top_panel.dart';
import 'theme.dart';

/// Main screen (ui-spec.md), the same phone layout on every platform.
/// Stateless; all metronome state lives in [controller].
class MetronomeScreen extends StatelessWidget {
  const MetronomeScreen({
    super.key,
    required this.controller,
    this.library,
    this.libraryProblem,
  });

  final MetronomeController controller;

  /// Null when storage is unavailable: no song panel then.
  final LibraryController? library;

  /// Why [library] is null, for the user; null when there's nothing to say.
  final String? libraryProblem;

  static const saveFailedNotice =
      "Couldn't save your changes. Metra tries again with your next change.";

  static const bpmKey = Key('bpm');
  static const playKey = Key('play');
  static const tapKey = Key('tap');
  static const titleKey = Key('title');
  static const tempoNameKey = Key('tempo-name');
  static const meterKey = Key('meter');
  static const onStartKey = Key('on-start');
  static const meterLabelKey = Key('meter-label');

  /// The "4/4" label: one line exactly the font size tall, its leading
  /// split evenly above and below.
  static const meterLabelStyle = TextStyle(
    fontFamily: MetraFonts.condensed,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const _meterStrut = StrutStyle(
    fontFamily: MetraFonts.condensed,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    forceStrutHeight: true,
  );
  static const _meterLine = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const countInLineKey = Key('count-in-line');
  static const revertKey = Key('revert');
  static const firstChangeKey = Key('first-change-line');
  static const settingsKey = Key('settings-button');
  static const updateDotKey = Key('update-dot');
  static const saveToSongKey = Key('save-to-song');
  static const saveAsNewKey = Key('save-as-new');
  static const subtitleKey = Key('subtitle');
  static const titleBlockKey = Key('title-block');

  // The polyrhythm lane plus its gap, kept free above the BPM.
  static const _laneSpace = PolyLane.height + 2;

  /// The most the main screen's text grows with the system font size.
  static const maxTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final library = this.library;
    // The tabs sit above the system navigation / gesture area: where the
    // home gesture reaches past the safe area, keep the tabs clear of it.
    final gestureGap = math.max(
      0.0,
      MediaQuery.systemGestureInsetsOf(context).bottom -
          MediaQuery.viewPaddingOf(context).bottom,
    );
    final metronome = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          // Large system fonts grow the text only so far: the stage
          // layout (fixed-height buttons, the bottom bar) must stay intact.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: maxTextScale,
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, ?library]),
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        8,
                        24,
                        library == null ? 16 : 0,
                      ),
                      child: _content(context),
                    ),
                  ),
                  // Edge to edge (the mode tabs); the context row pads
                  // itself to the content width.
                  if (library != null) ...[
                    const SizedBox(height: 12),
                    SetlistGroup(library: library, metronome: controller),
                    SizedBox(height: gestureGap),
                  ],
                ],
              ),
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
      child: Focus(
        autofocus: true,
        child: Scaffold(
          // No text fields here; a sheet's keyboard mustn't squeeze it.
          resizeToAvoidBottomInset: false,
          body: _Announcer(
            controller: controller,
            library: library,
            child: metronome,
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final colors = context.colors;
    final bpm = controller.bpm;
    final error = controller.audioError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(key: TopPanel.topRowKey, child: _topRow(context)),
        const SizedBox(height: 16),
        BeatIndicator(controller: controller),
        // Two groups (ui-spec.md "Vertical layout"): the BPM number alone
        // centred in the free space, the tempo line hanging under it (an
        // empty twin above balances it, as "bpm" is balanced); then the
        // controls, at fixed spacing.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // Small phones: the BPM shrinks first; the empty twin gives
              // way before the number drops under ~60px, and a last-resort
              // scale-down keeps the tempo line from overflowing. The twin
              // never goes below the polyrhythm lane's height, so the lane
              // (drawn over it) never moves the BPM, on or off.
              final twin = (box.maxHeight - 44 - 60)
                  .clamp(_laneSpace, 44.0)
                  .toDouble();
              final bpmArea = Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: box.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: twin),
                        // Sized for three digits from the area, never the value;
                        // the number is large already, so no text scaling.
                        // Read as part of the tempo control (the ruler).
                        MediaQuery.withNoTextScaling(
                          child: ExcludeSemantics(
                            child: BpmReadout(
                              bpm: bpm,
                              fontSize: BpmReadout.fit(
                                context,
                                Size(box.maxWidth, box.maxHeight - twin - 44),
                              ),
                              unitSize: 18,
                              numberKey: bpmKey,
                            ),
                          ),
                        ),
                        // Fixed height: the tempo name, or Revert / Save to song.
                        SizedBox(
                          height: 44,
                          child: RunLine(
                            controller: controller,
                            child: _TempoLine(
                              controller: controller,
                              library: library,
                              bpm: bpm,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              // The lane hangs 2px under the subdivision strip (the beat
              // row's tap padding is 6px), over the empty twin.
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: bpmArea),
                  if (controller.pattern.polyrhythm > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: -4,
                      child: PolyLane(controller: controller),
                    ),
                ],
              );
            },
          ),
        ),
        TempoRuler(bpm: bpm, onChanged: controller.setBpm),
        const SizedBox(height: 18), // 6px + the normal 12px gap
        TempoSteps(
          bpm: bpm,
          // Each step says the new tempo to a screen reader.
          onStep: (delta) {
            controller.nudge(delta);
            SemanticsService.sendAnnouncement(
              View.of(context),
              '${controller.bpm} BPM',
              TextDirection.ltr,
            );
          },
          height: 60,
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
                    child: Semantics(
                      label: 'Tap tempo',
                      excludeSemantics: true,
                      child: const Text('Tap', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final notice in [
          if (error != null) 'Audio problem: $error',
          ?libraryProblem,
          if (library?.saveFailed ?? false) saveFailedNotice,
        ]) ...[
          const SizedBox(height: 12),
          Text(
            notice,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.accentSounding),
          ),
        ],
      ],
    );
  }

  /// Fixed 54px in every mode, so nothing shifts: the song title over the
  /// set's name (an empty line in Single song); empty in Free play. Taps do nothing, so a stray touch on stage never leaves the
  /// main screen; long-presses are shortcuts (Long-press rule).
  Widget _titleBlock(BuildContext context) {
    final colors = context.colors;
    final library = this.library;
    final song = library?.currentSong;
    // Free play: empty (saving is the context row's "+ New song from
    // this").
    if (library != null && song == null && library.activeSetlist == null) {
      return const SizedBox.shrink();
    }
    final set = library?.activeSetlist;
    void longPress(VoidCallback open) {
      Haptics.medium();
      open();
    }

    // One 54px long-press target (at least the 48dp minimum): the parts
    // page, a shortcut to the Rhythm panel's "Song parts ›" (ui-spec.md
    // "The parts page"). No song: nothing.
    final VoidCallback? onLongPress = library == null || song == null
        ? null
        : () => longPress(() {
            TopPanel.close();
            openPartsPage(context, library, controller);
          });
    return GestureDetector(
      key: titleBlockKey,
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 34px, shrinking to 22px for long names; ellipsis only below.
          // A fixed 34px line box, the name at its bottom: a shrunk title
          // never moves the subtitle.
          SizedBox(
            height: 34,
            // A new name snaps in and brightens (only what changed), sized
            // to fit first; every size sits on one baseline at the left
            // edge, where the full-size name's baseline is.
            child: Align(
              alignment: Alignment.topLeft,
              child: BrightenText(
                song?.name ?? '',
                textKey: titleKey,
                minFontSize: 22,
                style: _titleStyle,
                baseline: _baselineOf(context, _titleStyle),
              ),
            ),
          ),
          const SizedBox(height: 3),
          // Always 17px; with the 34px title box it fills the 54px block,
          // so the subtitle sits on the block's bottom in every mode.
          SizedBox(
            height: 17,
            child: Align(
              alignment: Alignment.centerLeft,
              child: BrightenText(
                set?.name ?? '',
                textKey: subtitleKey,
                style: TextStyle(
                  fontSize: 14,
                  height: 17 / 14,
                  color: colors.muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _titleStyle = TextStyle(
    fontFamily: MetraFonts.condensed,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1,
  );

  /// Where [style]'s baseline sits below the top of its line.
  static double _baselineOf(BuildContext context, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag',
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    painter.dispose();
    return baseline;
  }

  Widget _topRow(BuildContext context) {
    final pattern = controller.pattern;
    final library = this.library;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 54,
            // Fixed height; the 34px title is large text already.
            child: MediaQuery.withNoTextScaling(child: _titleBlock(context)),
          ),
        ),
        const SizedBox(width: 4),
        // Red while anything in it is on, so Start never does something
        // you can't see.
        Builder(
          builder: (context) => _squareButton(
            key: onStartKey,
            tooltip: _onStartTooltip(controller.onStart),
            lit: controller.onStart.anyOn,
            onPressed: () => showOnStartSheet(context, controller),
            child: const StopwatchIcon(),
          ),
        ),
        const SizedBox(width: 4),
        // The same visible 44px box as the square buttons (only wider), its
        // 48dp touch target invisible padding around it: centred, so the
        // 48px row never stretches the outline.
        SizedBox(
          height: 48,
          child: Center(
            child: Builder(
              builder: (context) => OutlinedButton(
                key: meterKey,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(44, 44),
                  fixedSize: const Size.fromHeight(44),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: () => showTimeSignatureSheet(
                  context,
                  controller,
                  footer: library == null
                      ? null
                      : SongPartsRow(
                          library: library,
                          metronome: controller,
                          opener: context,
                        ),
                ),
                child: Semantics(
                  label: [
                    'Rhythm ${pattern.timeSignature}',
                    if (pattern.stepsPerBeat > 1)
                      TimeSignatureSheet.subdivisionNames[pattern.stepsPerBeat]!
                          .toLowerCase(),
                    if (pattern.polyrhythm > 0)
                      'polyrhythm ${pattern.polyrhythm}',
                  ].join(', '),
                  excludeSemantics: true,
                  // "4/4 ♪♪ · 3": the note only off quarters. One fixed line
                  // that shrinks rather than growing the box.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    // A symmetric line box: the font's ascent (1.135 em) is
                    // much taller than its descent (0.439), so proportional
                    // leading set the digits ~0.12 em above centre; even
                    // leading centres their cap height (0.688) within
                    // 0.004 em. The note icon is centred on the same line.
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pattern.timeSignature,
                          key: meterLabelKey,
                          style: meterLabelStyle,
                          strutStyle: _meterStrut,
                          textHeightBehavior: _meterLine,
                        ),
                        if (pattern.stepsPerBeat > 1) ...[
                          const SizedBox(width: 5),
                          SubdivisionIcon(pattern.stepsPerBeat, size: 20),
                        ],
                        if (pattern.polyrhythm > 0)
                          Text(
                            ' · ${pattern.polyrhythm}',
                            style: meterLabelStyle,
                            strutStyle: _meterStrut,
                            textHeightBehavior: _meterLine,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Builder(
          builder: (context) => _squareButton(
            key: settingsKey,
            tooltip: WhatsNew.showDot(library)
                ? 'Settings, new update'
                : 'Settings',
            onPressed: () {
              TopPanel.close();
              openSettings(context, metronome: controller, library: library);
            },
            // After an update, until Settings is opened (ui-spec.md
            // "What's new").
            dot: WhatsNew.showDot(library),
            child: const Icon(Icons.settings_outlined, size: 22),
          ),
        ),
      ],
    );
  }

  /// "When I press Start: count-in 1 bar, speed up, stop after".
  static String _onStartTooltip(OnStart on) {
    final parts = [
      if (on.countIn > 0) 'count-in ${OnStart.barsLabel(on.countIn)}',
      if (on.speedUp) 'speed up',
      if (on.stopAfter != StopAfter.off) 'stop after',
    ];
    return parts.isEmpty
        ? 'When I press Start'
        : 'When I press Start: ${parts.join(', ')}';
  }

  Widget _squareButton({
    Key? key,
    required String tooltip,
    required VoidCallback onPressed,
    required Widget child,
    bool dot = false,
    bool lit = false,
  }) => Tooltip(
    message: tooltip,
    // Read once, as the button's own label.
    excludeFromSemantics: true,
    // 44px to see, 48dp to touch: the button is drawn 44 inside a padded
    // tap target (the row's gaps are 4px narrower to match).
    child: SizedBox.square(
      dimension: 48,
      child: Stack(
        children: [
          Positioned.fill(
            child: _squareButtonBody(key, tooltip, onPressed, child, lit),
          ),
          // An 8px red dot in the drawn button's top-right corner.
          if (dot)
            Positioned(
              key: updateDotKey,
              top: 5,
              right: 5,
              child: IgnorePointer(
                child: Builder(
                  builder: (context) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.colors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _squareButtonBody(
    Key? key,
    String tooltip,
    VoidCallback onPressed,
    Widget child,
    bool lit,
  ) => Center(
    child: Builder(
      builder: (context) => OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          // Lit: red outline and icon.
          foregroundColor: lit ? context.colors.accent : null,
          side: lit ? BorderSide(color: context.colors.accent, width: 2) : null,
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(44),
          fixedSize: const Size.square(44),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: onPressed,
        child: Semantics(label: tooltip, child: child),
      ),
    ),
  );
}

/// What a screen reader hears unasked (ui-spec.md "Accessibility"): only
/// Start / Stop and song changes, never anything per click.
class _Announcer extends StatefulWidget {
  const _Announcer({
    required this.controller,
    required this.library,
    required this.child,
  });

  final MetronomeController controller;
  final LibraryController? library;
  final Widget child;

  @override
  State<_Announcer> createState() => _AnnouncerState();
}

class _AnnouncerState extends State<_Announcer> {
  late bool _playing = widget.controller.isPlaying;
  late String? _songId = widget.library?.currentSong?.id;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_check);
    widget.library?.addListener(_check);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_check);
    widget.library?.removeListener(_check);
    super.dispose();
  }

  void _say(String message) => SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    TextDirection.ltr,
  );

  void _check() {
    if (!mounted) return;
    final playing = widget.controller.isPlaying;
    if (playing != _playing) {
      _playing = playing;
      _say(playing ? 'Playing' : 'Stopped');
    }
    final song = widget.library?.currentSong;
    if (song?.id != _songId) {
      _songId = song?.id;
      if (song != null) _say('${song.name}, ${song.bpm} BPM');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The line under the BPM: the tempo name; while the loaded song has
/// unsaved main-screen changes, Revert · Save · Save as new instead
/// (ui-spec.md "Changes to a loaded song"). It also teaches "edit the
/// song right here" (ui-spec.md "Teaching "edit right here"",
/// `edit-on-main.reference.html`), never moving anything:
/// A, once: "Change anything here, then Save" at the first load ever and
/// the first load of a song "+ New song" made; B, once: at the first
/// change, Save stands out and a muted line floats below; C, every save:
/// a short "✓ Saved ..." confirmation.
class _TempoLine extends StatefulWidget {
  const _TempoLine({
    required this.controller,
    required this.library,
    required this.bpm,
  });

  final MetronomeController controller;
  final LibraryController? library;
  final int bpm;

  /// How long each line stays.
  static const firstLoadFor = Duration(seconds: 4);
  static const firstChangeFor = Duration(seconds: 8);
  static const savedFor = Duration(milliseconds: 1500);

  static const firstLoadTip = 'edit-first-load';
  static const newSongTip = 'edit-new-song';
  static const firstChangeTip = 'edit-first-change';

  static const firstLoadText = 'Change anything here, then Save';
  static const firstChangeText =
      'Playing your changes. Save keeps them in this song.';
  static const savedText = 'Saved to the song';
  static const savedAsNewText = 'Saved as a new song';

  @override
  State<_TempoLine> createState() => _TempoLineState();
}

class _TempoLineState extends State<_TempoLine> {
  late String? _songId = widget.library?.currentSong?.id;

  /// A ("Change anything here...") while true.
  bool _firstLoad = false;

  /// B: Save stands out and the line below shows, while true.
  bool _firstChange = false;

  /// C: the "✓ Saved ..." text, while set.
  String? _saved;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.library?.addListener(_check);
    widget.controller.addListener(_check);
  }

  @override
  void dispose() {
    widget.library?.removeListener(_check);
    widget.controller.removeListener(_check);
    _timer?.cancel();
    super.dispose();
  }

  void _say(String message) => SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    TextDirection.ltr,
  );

  /// Shows one line for [duration]; any other one ends.
  void _show({
    bool firstLoad = false,
    bool firstChange = false,
    String? saved,
  }) {
    _timer?.cancel();
    setState(() {
      _firstLoad = firstLoad;
      _firstChange = firstChange;
      _saved = saved;
    });
    final duration = firstLoad
        ? _TempoLine.firstLoadFor
        : firstChange
        ? _TempoLine.firstChangeFor
        : _TempoLine.savedFor;
    if (firstLoad || firstChange || saved != null) {
      _timer = Timer(duration, () {
        if (mounted) _show();
      });
    }
  }

  void _check() {
    final library = widget.library;
    if (!mounted || library == null) return;
    final song = library.currentSong;
    if (song?.id != _songId) {
      _songId = song?.id;
      if (_firstLoad || _saved != null) _show();
      // A song is loaded (never Free play): the first ever, or the first
      // one "+ New song" made.
      final fresh = song != null && song.id == library.freshSongId;
      final first = !library.tipSeen(_TempoLine.firstLoadTip);
      final firstNew = fresh && !library.tipSeen(_TempoLine.newSongTip);
      if (song != null && (first || firstNew)) {
        library.markTipSeen(_TempoLine.firstLoadTip);
        if (fresh) library.markTipSeen(_TempoLine.newSongTip);
        _show(firstLoad: true);
        _say(_TempoLine.firstLoadText);
        return;
      }
    }
    if (library.songChanged(widget.controller) &&
        !library.tipSeen(_TempoLine.firstChangeTip)) {
      library.markTipSeen(_TempoLine.firstChangeTip);
      _show(firstChange: true);
      _say(_TempoLine.firstChangeText);
    }
  }

  void _confirm(String text) {
    _show(saved: text);
    _say(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final library = widget.library;
    final controller = widget.controller;
    // One state at a time, snapping in and brightening: the tempo name,
    // A, "✓ Saved ...", or the actions.
    if (library == null || !library.songChanged(controller)) {
      final saved = _saved;
      return BrightenSwap(
        value: saved ?? (_firstLoad ? 'first-load' : tempoName(widget.bpm)),
        child: _quiet(colors),
      );
    }
    return BrightenSwap(value: 'actions', child: _actions(colors, library));
  }

  /// The tempo name, A's line, or C's confirmation.
  Widget _quiet(MetraColors colors) {
    final saved = _saved;
    return Center(
      child: saved != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14, color: colors.muted),
                const SizedBox(width: 8),
                Text(
                  saved,
                  style: TextStyle(fontSize: 15, color: colors.muted),
                ),
              ],
            )
          : _firstLoad
          ? Text(
              _TempoLine.firstLoadText,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: colors.text),
            )
          : Text(
              tempoName(widget.bpm),
              key: MetronomeScreen.tempoNameKey,
              style: TextStyle(fontSize: 16, color: colors.muted),
            ),
    );
  }

  /// Revert · Save · Save as new; B's line floats below the first time.
  Widget _actions(MetraColors colors, LibraryController library) {
    final controller = widget.controller;
    // Plain grey text buttons, "Revert · Save · Save as new": quiet, one
    // tap each (ui-spec.md "Changes to a loaded song").
    Widget action(
      Key key,
      String text,
      VoidCallback onPressed, {
      bool lit = false,
    }) => TextButton(
      key: key,
      style: TextButton.styleFrom(
        foregroundColor: lit ? colors.text : colors.muted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: MetraFonts.body,
          fontSize: 15,
          fontWeight: lit ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
    // The dim dot is the resting-beat grey (#3A3A3A).
    final dot = Text(
      '·',
      style: TextStyle(fontSize: 15, color: colors.beatResting),
    );
    // Shrinks rather than overflowing on narrow phones.
    final actions = FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(MetronomeScreen.revertKey, 'Revert', () {
            Haptics.tick();
            _show();
            library.revertSong(controller);
          }),
          dot,
          action(MetronomeScreen.saveToSongKey, 'Save', lit: _firstChange, () {
            Haptics.tick();
            library.saveToSong(controller);
            _confirm(_TempoLine.savedText);
          }),
          dot,
          Builder(
            builder: (context) =>
                action(MetronomeScreen.saveAsNewKey, 'Save as new', () async {
                  _show();
                  if (await showSaveAsNewSong(context, library, controller) &&
                      mounted) {
                    _confirm(_TempoLine.savedAsNewText);
                  }
                }),
          ),
        ],
      ),
    );
    // B's line floats below, over the space above the ruler (nothing
    // moves): it arrives and just fades away.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Center(child: actions),
        Positioned(
          left: -24,
          right: -24,
          top: 40,
          child: ArriveLeave(
            closes: false,
            child: _firstChange
                ? Text(
                    _TempoLine.firstChangeText,
                    key: MetronomeScreen.firstChangeKey,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: colors.muted),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// While a count-in plays, the line under the BPM reads "Count-in · 3 of
/// 4" ("Count-in · 2 · 3 of 4" in bar 2 of 2); during a run, its progress
/// ("↗ +5 every 8 bars · next in 3 · 4:12 left"); otherwise it is [child].
/// Read per frame from the engine clock, like the beat blocks.
/// A run's line with its speed-up arrow ("↗ +5 every 8 bars") drawn as
/// a vector icon: Android shows some arrow glyphs as colored emoji.
Widget _iconLine(BuildContext context, String label) {
  final color = context.colors.text;
  final arrow = switch (label) {
    _ when label.startsWith('↗ ') => Icons.trending_up,
    _ when label.startsWith('↘ ') => Icons.trending_down,
    _ => null,
  };
  return Semantics(
    label: label,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arrow != null) ...[
          Icon(arrow, size: 20, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          arrow == null ? label : label.substring(2),
          key: MetronomeScreen.countInLineKey,
          style: TextStyle(fontSize: 16, color: color),
        ),
      ],
    ),
  );
}

class RunLine extends StatefulWidget {
  const RunLine({super.key, required this.controller, required this.child});

  final MetronomeController controller;
  final Widget child;

  static String? labelFor(MetronomeController controller, Duration? now) {
    final step = now == null ? null : controller.stepAt(now);
    final countIn = step?.countIn;
    if (step == null || countIn == null) {
      // Before its first beat has sounded.
      if (step == null && controller.countingIn) return 'Count-in';
      if (!controller.inRun) return null;
      final start = controller.runStart;
      final elapsed = now == null || start == null || now < start
          ? Duration.zero
          : now - start;
      return controller.onStart.progress(
        bpm: controller.bpm,
        from: controller.startBpm,
        bar: step?.bar ?? -1,
        elapsed: elapsed,
      );
    }
    final beat = '${step.barPosition + 1} of ${step.pattern.beatsPerBar}';
    return countIn.bars > 1
        ? 'Count-in · ${countIn.bar} · $beat'
        : 'Count-in · $beat';
  }

  @override
  State<RunLine> createState() => _RunLineState();
}

class _RunLineState extends State<RunLine> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  String? _label;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _ticker.dispose();
    super.dispose();
  }

  // Ticks only while playing.
  void _sync() {
    if (widget.controller.isPlaying) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      if (_label != null) setState(() => _label = null);
    }
  }

  void _onTick(Duration _) {
    final label = RunLine.labelFor(
      widget.controller,
      widget.controller.visualTimeAt(
        SchedulerBinding.instance.currentFrameTimeStamp,
      ),
    );
    if (label != _label) setState(() => _label = label);
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    // The tempo line stays underneath, keeping its state (its tips).
    return Stack(
      fit: StackFit.expand,
      children: [
        Visibility(
          visible: label == null,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: widget.child,
        ),
        if (label != null)
          Center(
            // Shrinks rather than overflowing on narrow phones.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _iconLine(context, label),
            ),
          ),
      ],
    );
  }
}
