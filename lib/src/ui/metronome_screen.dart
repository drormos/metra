import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/tempo_name.dart';
import 'beat_indicator.dart';
import 'fit_text.dart';
import 'haptics.dart';
import 'setlist_group.dart';
import 'setlist_picker.dart';
import 'save_as_new_dialog.dart';
import 'icons.dart';
import 'settings_screen.dart';
import 'song_editor.dart';
import 'song_library.dart';
import 'subdivision_icon.dart';
import 'tempo_controls.dart';
import 'tempo_ruler.dart';
import 'time_signature_sheet.dart';
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
  static const subdivisionKey = Key('subdivision');
  static const revertKey = Key('revert');
  static const saveToSongKey = Key('save-to-song');
  static const saveAsNewKey = Key('save-as-new');
  static const subtitleKey = Key('subtitle');

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
          body: metronome,
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
        _topRow(context),
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
              // scale-down keeps the tempo line from overflowing.
              final twin = (box.maxHeight - 44 - 60).clamp(0.0, 44.0);
              return Center(
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
                        MediaQuery.withNoTextScaling(
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
                        // Fixed height: the tempo name, or Revert / Save to song.
                        SizedBox(height: 44, child: _tempoLine(colors, bpm)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        TempoRuler(bpm: bpm, onChanged: controller.setBpm),
        const SizedBox(height: 18), // 6px + the normal 12px gap
        TempoSteps(bpm: bpm, onStep: controller.nudge, height: 60),
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

  /// The tempo name; while the loaded song has unsaved main-screen
  /// changes, Revert and Save to song instead (ui-spec.md "Changes to a
  /// loaded song").
  Widget _tempoLine(MetraColors colors, int bpm) {
    final library = this.library;
    if (library == null || !library.songChanged(controller)) {
      return Center(
        child: Text(
          tempoName(bpm),
          key: tempoNameKey,
          style: TextStyle(fontSize: 16, color: colors.muted),
        ),
      );
    }
    // Plain grey text buttons, "Revert · Save · Save as new": quiet, one
    // tap each (ui-spec.md "Changes to a loaded song").
    Widget action(Key key, String text, VoidCallback onPressed) => TextButton(
      key: key,
      style: TextButton.styleFrom(
        foregroundColor: colors.muted,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: onPressed,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: MetraFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    // The dim dot is the resting-beat grey (#3A3A3A).
    final dot = Text(
      '·',
      style: TextStyle(fontSize: 15, color: colors.beatResting),
    );
    // Shrinks rather than overflowing on narrow phones.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          action(revertKey, 'Revert', () {
            Haptics.tick();
            library.revertSong(controller);
          }),
          dot,
          action(saveToSongKey, 'Save', () {
            Haptics.tick();
            library.saveToSong(controller);
          }),
          dot,
          Builder(
            builder: (context) => action(
              saveAsNewKey,
              'Save as new',
              () => showSaveAsNewSong(context, library, controller),
            ),
          ),
        ],
      ),
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

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onLongPress: library == null || song == null
              ? null
              : () => longPress(
                  () =>
                      openSongEditor(context, library, controller, song: song),
                ),
          // 34px, shrinking to 22px for long names; ellipsis only below.
          // A fixed 34px line box, the name at its bottom: a shrunk title
          // never moves the subtitle.
          child: SizedBox(
            height: 34,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: FitText(
                song?.name ?? '',
                textKey: titleKey,
                minFontSize: 22,
                style: const TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        // Always 17px; with the 34px title box it fills the 54px block,
        // so the subtitle sits on the block's bottom in every mode.
        SizedBox(
          height: 17,
          child: GestureDetector(
            onLongPress: library == null || set == null
                ? null
                : () => longPress(
                    () => openSetlists(
                      context,
                      library: library,
                      metronome: controller,
                      setId: set.id,
                    ),
                  ),
            child: Text(
              set?.name ?? '',
              key: subtitleKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 17 / 14,
                color: colors.muted,
              ),
            ),
          ),
        ),
      ],
    );
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
              onPressed: () => showTimeSignatureSheet(context, controller),
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
            tooltip: 'Menu',
            onPressed: () => openSettings(
              context,
              metronome: controller,
              library: library,
              onSetlists: library == null
                  ? null
                  : () => openSetlists(
                      context,
                      library: library,
                      metronome: controller,
                    ),
              onSongLibrary: library == null
                  ? null
                  : () => openSongLibrary(context, library, controller),
            ),
            child: const MenuIcon(),
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
    // Read once, as the button's own label.
    excludeFromSemantics: true,
    child: SizedBox.square(
      dimension: 44,
      child: OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size.square(44),
        ),
        onPressed: onPressed,
        child: Semantics(label: tooltip, child: child),
      ),
    ),
  );

  static const _subdivisionNames = {
    1: 'quarter notes',
    2: 'eighth notes',
    3: 'triplets',
    4: 'sixteenth notes',
  };
}
