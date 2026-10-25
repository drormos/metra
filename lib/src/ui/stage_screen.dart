import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import '../model/on_start.dart';
import 'beat_indicator.dart';
import 'dashed_outline.dart';
import 'fit_text.dart';
import 'haptics.dart';
import 'metronome_screen.dart';
import 'tempo_controls.dart';
import 'theme.dart';

/// Stage mode (ui-spec.md "Stage mode", `stage-mode.reference.html`): the
/// loaded set, full screen and play-only. Previous / Next / Start-Stop are
/// plain taps; nothing edits; leaving takes a 1 s hold.
class StageScreen extends StatefulWidget {
  const StageScreen({
    super.key,
    required this.controller,
    required this.library,
  });

  final MetronomeController controller;
  final LibraryController library;

  static const exitKey = Key('stage-exit');
  static const titleKey = Key('stage-title');
  static const positionKey = Key('stage-position');
  static const bpmKey = Key('stage-bpm');
  static const meterKey = Key('stage-meter');
  static const hintKey = Key('stage-hint');
  static const previousKey = Key('stage-previous');
  static const nextKey = Key('stage-next');
  static const playKey = Key('stage-play');

  static const holdHint = 'Hold to exit stage mode';
  static const holdingHint = 'Keep holding to leave stage mode';
  static const tipText =
      "Tip: turn on Do Not Disturb so calls don't interrupt the show.";

  /// A second Previous / Next tap sooner than this is a bounce.
  static const bounce = Duration(milliseconds: 120);

  /// While playing, the click restarts this long after the last tap.
  static const settle = Duration(milliseconds: 300);

  static const hold = Duration(seconds: 1);

  @override
  State<StageScreen> createState() => _StageScreenState();
}

class _StageScreenState extends State<StageScreen>
    with SingleTickerProviderStateMixin {
  MetronomeController get _metronome => widget.controller;
  LibraryController get _library => widget.library;

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: StageScreen.hold)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _exit();
        });

  /// The song shown while a run of taps waits to restart the click.
  int? _pending;
  Timer? _restart;
  Timer? _bounce;
  String? _hint;
  Timer? _hintTimer;
  late Timer _clock;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clock = Timer.periodic(
      const Duration(seconds: 10),
      (_) => setState(() {}),
    );
    // Reverted changes are said first; the tip then waits for the next
    // entry.
    final notice = _library.takeStageNotice();
    final tip = !_library.tipSeen(LibraryController.stageTip);
    if (notice != null || tip) {
      _hint = notice ?? StageScreen.tipText;
      _hintTimer = Timer(Duration(seconds: notice != null ? 3 : 5), () {
        if (mounted) setState(() => _hint = null);
      });
    }
    if (notice == null && tip) {
      // Saved after this build: it notifies the app.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _library.markTipSeen(LibraryController.stageTip),
      );
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _restart?.cancel();
    _hold.dispose();
    _bounce?.cancel();
    _hintTimer?.cancel();
    _clock.cancel();
    super.dispose();
  }

  int get _shown => _pending ?? _library.currentIndex;

  void _say(String text, [Duration time = const Duration(seconds: 2)]) {
    _hintTimer?.cancel();
    setState(() => _hint = text);
    _hintTimer = Timer(time, () {
      if (mounted) setState(() => _hint = null);
    });
  }

  /// Previous / Next. Stopped, the song loads at once; playing, the shown
  /// song moves with every tap and the click restarts once, [settle]
  /// after the last one.
  void _step(int delta) {
    if (_bounce?.isActive ?? false) return;
    _bounce = Timer(StageScreen.bounce, () {});
    final songs = _library.visibleSongs;
    final from = _shown;
    final to = from < 0 ? (delta > 0 ? 0 : -1) : from + delta;
    if (to < 0 || to >= songs.length) return;
    Haptics.medium();
    if (!_metronome.isPlaying) {
      _library.playSong(songs[to], _metronome, index: to);
      return;
    }
    setState(() => _pending = to);
    _restart?.cancel();
    _restart = Timer(StageScreen.settle, () => setState(_commit));
  }

  /// Loads the shown song now, if a run of taps is waiting.
  void _commit() {
    _restart?.cancel();
    final to = _pending;
    _pending = null;
    final songs = _library.visibleSongs;
    if (to != null && to < songs.length) {
      _library.playSong(songs[to], _metronome, index: to);
    }
  }

  void _jump(int index) {
    _pending = null;
    _restart?.cancel();
    Haptics.medium();
    _library.playSong(_library.visibleSongs[index], _metronome, index: index);
  }

  void _startStop() {
    Haptics.medium();
    if (_metronome.isPlaying) {
      _metronome.stop();
      setState(_commit); // the shown song loads, stopped
    } else {
      _metronome.toggle();
    }
  }

  /// Pedals and keyboard: as on the main screen, after any waiting tap.
  void _pedal(void Function(MetronomeController) step) {
    setState(_commit);
    step(_metronome);
  }

  void _exit() {
    Haptics.tick();
    setState(_commit);
    _library.exitStageMode();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: false,
      // In immersive mode Android takes the first back swipe itself (it
      // shows the bars); a Back that reaches us is the second: it exits.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _startStop,
          for (final key in [
            LogicalKeyboardKey.pageDown,
            LogicalKeyboardKey.arrowRight,
          ])
            SingleActivator(key): () => _pedal(_library.nextSong),
          for (final key in [
            LogicalKeyboardKey.pageUp,
            LogicalKeyboardKey.arrowLeft,
          ])
            SingleActivator(key): () => _pedal(_library.previousSong),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: colors.background,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: MetronomeScreen.maxTextScale,
                    child: ListenableBuilder(
                      listenable: Listenable.merge([_metronome, _library]),
                      builder: (context, _) => Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: _content(context),
                      ),
                    ),
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
    final colors = context.colors;
    final songs = _library.visibleSongs;
    final index = _shown;
    final song = index >= 0 && index < songs.length ? songs[index] : null;
    // A waiting tap shows the song it lands on; otherwise what plays (a
    // speed up's tempo included).
    final pending = _pending != null;
    final bpm = pending ? song!.bpm : _metronome.bpm;
    final pattern = pending ? song!.pattern : _metronome.pattern;
    final onStart = pending ? song!.onStart : _metronome.onStart;
    final before = index > 0 ? songs[index - 1] : null;
    final after = index + 1 < songs.length ? songs[index + 1] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Large text: the pill shrinks rather than pushing the time
            // off the screen.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _exitPill(colors),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              TimeOfDay.now().format(context),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: Center(
            child: FitText(
              song?.name ?? '',
              textKey: StageScreen.titleKey,
              minFontSize: 24,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: MetraFonts.condensed,
                fontSize: 44,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
        _position(colors, songs.length, index),
        const SizedBox(height: 12),
        BeatIndicator(controller: _metronome, blockHeight: 64, editable: false),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MediaQuery.withNoTextScaling(
                      child: BpmReadout(
                        bpm: bpm,
                        fontSize: BpmReadout.fit(
                          context,
                          Size(box.maxWidth, box.maxHeight - 32),
                        ).clamp(0, 150).toDouble(),
                        unitSize: 18,
                        numberKey: StageScreen.bpmKey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // While playing, a count-in / speed up / stop after
                    // shows its progress here, as on the main screen.
                    SizedBox(
                      height: 24,
                      width: box.maxWidth,
                      child: RunLine(
                        controller: _metronome,
                        child: Center(
                          child: Text(
                            _meterLine(pattern.timeSignature, onStart),
                            key: StageScreen.meterKey,
                            style: TextStyle(fontSize: 15, color: colors.muted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 24,
          child: Center(
            child: Text(
              _hint ?? '',
              key: StageScreen.hintKey,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: colors.text),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 104,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _stepButton(
                  colors,
                  key: StageScreen.previousKey,
                  label: '‹ Previous',
                  song: before,
                  end: 'Start of set',
                  alignment: CrossAxisAlignment.start,
                  onTap: () => _step(-1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stepButton(
                  colors,
                  key: StageScreen.nextKey,
                  label: 'Next ›',
                  song: index < 0 && songs.isNotEmpty ? songs.first : after,
                  end: 'End of set',
                  alignment: CrossAxisAlignment.end,
                  onTap: () => _step(1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: FilledButton.icon(
            key: StageScreen.playKey,
            onPressed: _startStop,
            icon: Icon(
              _metronome.isPlaying ? Icons.stop : Icons.play_arrow,
              size: 28,
            ),
            label: Text(
              _metronome.isPlaying ? 'Stop' : 'Start',
              style: const TextStyle(fontSize: 26),
            ),
          ),
        ),
      ],
    );
  }

  /// "4/4 · count-in 1 bar": the time signature plus what's on in "When
  /// I press Start".
  static String _meterLine(String timeSignature, OnStart on) => [
    timeSignature,
    if (on.countIn > 0) 'count-in ${OnStart.barsLabel(on.countIn)}',
    if (on.speedUp) 'speed up',
    if (on.stopAfter != StopAfter.off) 'stop after',
  ].join(' · ');

  /// "Friday set · 4 of 12": opens the set's list, read-only.
  Widget _position(MetraColors colors, int count, int index) {
    final set = _library.activeSetlist;
    final text = [
      ?set?.name,
      if (index >= 0) '${index + 1} of $count',
    ].join(' · ');
    return Semantics(
      button: true,
      onTapHint: 'show the set',
      child: InkWell(
        key: StageScreen.positionKey,
        onTap: count == 0 ? null : _showSet,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16, color: colors.muted),
            ),
          ),
        ),
      ),
    );
  }

  /// The set's songs: tap one to jump to it; nothing else.
  void _showSet() {
    final songs = _library.visibleSongs;
    final current = _shown;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.sheet,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (sheet) {
        final colors = sheet.colors;
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: songs.length,
            itemBuilder: (_, i) => ListTile(
              key: ValueKey('stage-song-$i'),
              minTileHeight: 56,
              selected: i == current,
              selectedColor: colors.text,
              selectedTileColor: colors.selectedRow,
              leading: Text(
                '${i + 1}',
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
              title: Text(
                songs[i].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18),
              ),
              trailing: Text(
                '${songs[i].bpm}',
                style: TextStyle(fontSize: 13, color: colors.muted),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _jump(i);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _stepButton(
    MetraColors colors, {
    required Key key,
    required String label,
    required Song? song,
    required String end,
    required CrossAxisAlignment alignment,
    required VoidCallback onTap,
  }) {
    // Tight lines: three of them fit 104px with large text.
    final muted = TextStyle(
      overflow: TextOverflow.ellipsis,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: colors.muted,
    );
    return Semantics(
      button: true,
      enabled: song != null,
      label: song == null ? end : '$label ${song.name}, ${song.bpm} BPM',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          // Inert at the ends ("Start of set", "End of set").
          onTap: song == null ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: alignment,
              children: [
                if (song == null)
                  Text(end, maxLines: 1, style: muted)
                else ...[
                  Text(label, maxLines: 1, style: muted),
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${song.bpm} BPM',
                    maxLines: 1,
                    style: muted.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The only hold: a dashed pill with a lock, filling left to right over
  /// 1 s. Releasing early resets it and says how to leave.
  Widget _exitPill(MetraColors colors) => Semantics(
    button: true,
    // TalkBack's double-tap-and-hold is the hold.
    label: 'Exit stage mode, double-tap and hold',
    onLongPress: _exit,
    excludeSemantics: true,
    child: Listener(
      key: StageScreen.exitKey,
      onPointerDown: (_) {
        _hold.forward(from: 0);
        _say(StageScreen.holdingHint, StageScreen.hold * 2);
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: SizedBox(
        height: 48,
        child: Center(
          child: CustomPaint(
            painter: DashedOutline(colors.controlOutline, radius: 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AnimatedBuilder(
                animation: _hold,
                builder: (context, child) => CustomPaint(
                  painter: _Fill(_hold.value, colors.beatResting),
                  child: child,
                ),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: colors.muted),
                      const SizedBox(width: 6),
                      Text(
                        'Hold to exit',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void _release() {
    if (_hold.isCompleted) return;
    _hold.value = 0;
    _say(StageScreen.holdHint);
  }
}

/// The hold's progress, filled from the left.
class _Fill extends CustomPainter {
  _Fill(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    canvas.drawRect(
      Offset.zero & Size(size.width * progress, size.height),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Fill old) =>
      old.progress != progress || old.color != color;
}
