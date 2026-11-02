import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../audio/mic_input.dart';
import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../controller/tuner_controller.dart';
import '../model/tuner_note.dart';
import 'editor_scaffold.dart';
import 'icons.dart';
import 'theme.dart';
import 'value_stepper.dart';

/// Opens the Tuner (ui-spec.md "Tuner") from the tuning-fork button, with
/// the same page motion as Settings. The click stops (a tuner can't hear
/// over it) and stays stopped after.
Future<void> openTuner(
  BuildContext context, {
  required MetronomeController metronome,
  LibraryController? library,
}) {
  metronome.stop();
  return Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => TunerPage(library: library)),
  );
}

/// The tuner: the microphone listens only while this page is on screen.
class TunerPage extends StatefulWidget {
  const TunerPage({super.key, this.library, this.mic});

  /// Null when storage is unavailable: Reference A4 isn't kept.
  final LibraryController? library;

  /// Tests pass a fake.
  final MicInput? mic;

  static const noteKey = Key('tuner-note');
  static const octaveKey = Key('tuner-octave');
  static const centsKey = Key('tuner-cents');
  static const meterKey = Key('tuner-meter');
  static const allowKey = Key('tuner-allow');
  static const referenceLabel = 'Reference A4';
  static const privacyLine =
      'Metra listens only while the tuner is open. Nothing is recorded or '
      'sent.';
  static const pauseLine = 'The click pauses while the tuner is open';

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  late final TunerController _tuner;
  late final AppLifecycleListener _lifecycle;

  // Without storage, the stepper still works for this visit.
  int _a4 = 440;
  int get _referenceA4 => widget.library?.referenceA4 ?? _a4;

  @override
  void initState() {
    super.initState();
    _tuner = TunerController(
      widget.mic ?? AndroidMicInput(),
      referenceA4: () => _referenceA4,
      announce: (message) {
        if (!mounted) return;
        SemanticsService.sendAnnouncement(
          View.of(context),
          message,
          TextDirection.ltr,
        );
      },
    )..open();
    // Hidden, not inactive: the permission dialog makes the app inactive.
    _lifecycle = AppLifecycleListener(
      onHide: _tuner.paused,
      onShow: _tuner.resumed,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _tuner.dispose();
    super.dispose();
  }

  void _setA4(int hz) {
    final value = hz.clamp(430, 450);
    if (widget.library case final library?) {
      library.setReferenceA4(value);
    } else {
      setState(() => _a4 = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BackBar(title: 'Tuner'),
            Expanded(
              // Scrolls only when large text makes it taller than the screen.
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: IntrinsicHeight(child: _body(context, colors)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, MetraColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: ListenableBuilder(
          listenable: _tuner,
          builder: (context, _) => _tuner.permission == MicPermission.granted
              ? _Reading(_tuner.note)
              : _Permission(_tuner),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ListenableBuilder(
          listenable: widget.library ?? _tuner,
          builder: (context, _) {
            final a4 = _referenceA4;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Wraps only at the largest text sizes.
                const Flexible(
                  child: Text('A4 =', style: TextStyle(fontSize: 17)),
                ),
                const SizedBox(width: 12),
                ValueStepper(
                  label: TunerPage.referenceLabel,
                  showLabel: false,
                  display: '$a4 Hz',
                  editText: '$a4',
                  fieldWidth: 96,
                  onMinus: a4 > 430 ? () => _setA4(a4 - 1) : null,
                  onPlus: a4 < 450 ? () => _setA4(a4 + 1) : null,
                  onTyped: (text) {
                    if (int.tryParse(text.trim()) case final v?) {
                      _setA4(v);
                    }
                  },
                ),
              ],
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Text(
          TunerPage.pauseLine,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: colors.muted),
        ),
      ),
    ],
  );
}

/// Before the microphone is allowed: the privacy line (above Android's
/// dialog), and after a refusal "Allow microphone".
class _Permission extends StatelessWidget {
  const _Permission(this.tuner);

  final TunerController tuner;

  @override
  Widget build(BuildContext context) {
    final permission = tuner.permission;
    if (permission == null) return const SizedBox.shrink();
    final refused =
        permission == MicPermission.denied ||
        permission == MicPermission.blocked;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              TunerPage.privacyLine,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: context.colors.muted),
            ),
            if (refused) ...[
              const SizedBox(height: 24),
              OutlinedButton(
                key: TunerPage.allowKey,
                onPressed: tuner.allow,
                child: const Text('Allow microphone'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The note, the cents line and the meter; "–" and "Play a string" in
/// silence.
/// The note: the letter ~200dp tall (cap height), and a small column
/// tight to its right with the sharp at the cap height and the muted
/// octave on the baseline, centered as one group. "–" in silence.
class _NoteName extends StatelessWidget {
  const _NoteName(this.note);

  final TunerNote? note;

  /// Saira Extra Condensed: cap height 0.688 em. With height 1 and even
  /// leading the cap sits from 0.160 em to the baseline at 0.848 em.
  static const _size = 290.0;
  static const _cap = 0.688 * _size;
  static const _capTop = 0.160 * _size;
  static const _baseline = 0.848 * _size;
  static const _octave = 0.3 * _size;
  static const _sharp = 0.26 * _size;
  static const _even = TextHeightBehavior(
    leadingDistribution: TextLeadingDistribution.even,
  );

  static TextStyle _style(double size, Color color) => TextStyle(
    fontFamily: MetraFonts.condensed,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1,
    leadingDistribution: TextLeadingDistribution.even,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final note = this.note;
    final group = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          note?.name ?? '–',
          key: TunerPage.noteKey,
          style: _style(_size, note == null ? colors.muted : colors.text),
          textHeightBehavior: _even,
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: SizedBox(
              height: _size,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The sign's drawing starts 2/24 into its box.
                  const SizedBox(height: _capTop - _sharp * 2 / 24),
                  if (note.sharp)
                    // Only its drawing (5.5 to 19 of 24) takes room, its
                    // left edge on the octave's, so the group centres on
                    // what's seen.
                    SizedBox(
                      width: _sharp * 13.5 / 24,
                      height: _sharp,
                      child: OverflowBox(
                        alignment: Alignment.centerLeft,
                        minWidth: _sharp,
                        maxWidth: _sharp,
                        child: Transform.translate(
                          offset: const Offset(-_sharp * 5.5 / 24, 0),
                          child: AccidentalIcon(
                            sharp: true,
                            size: _sharp,
                            color: colors.text,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: _sharp),
                  const Spacer(),
                  Text(
                    '${note.octave}',
                    key: TunerPage.octaveKey,
                    style: _style(_octave, colors.muted),
                    textHeightBehavior: _even,
                  ),
                  // Its baseline on the letter's.
                  const SizedBox(height: _size - _baseline - 0.152 * _octave),
                ],
              ),
            ),
          ),
      ],
    );
    // Laid out on the full 1 em line; only the cap (plus a little) takes
    // room, the empty top and bottom of the line overflow unpainted.
    return SizedBox(
      height: _cap + 16,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Align(
          heightFactor: (_cap + 16) / _size,
          child: MediaQuery.withNoTextScaling(child: group),
        ),
      ),
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading(this.note);

  final TunerNote? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final note = this.note;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Read through the announcements, never per frame.
          ExcludeSemantics(child: _NoteName(note)),
          const SizedBox(height: 12),
          Text(
            note?.line ?? 'Play a string',
            key: TunerPage.centsKey,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: colors.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 24),
          ExcludeSemantics(
            child: _Meter(
              cents: note?.cents ?? 0,
              heard: note != null,
              inTune: note?.inTune ?? false,
            ),
          ),
          const SizedBox(height: 8),
          ExcludeSemantics(
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 14, color: colors.muted),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AccidentalIcon(sharp: false, size: 16),
                      Text(' −50'),
                    ],
                  ),
                  Text('0'),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('+50 '),
                      AccidentalIcon(sharp: true, size: 16),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// −50…+50 cents: ticks every 5, longer every 25, a center tick, and the
/// needle easing toward each reading (at once with "Remove animations").
class _Meter extends StatefulWidget {
  const _Meter({
    required this.cents,
    required this.heard,
    required this.inTune,
  });

  final double cents;
  final bool heard;
  final bool inTune;

  @override
  State<_Meter> createState() => _MeterState();
}

class _MeterState extends State<_Meter> with SingleTickerProviderStateMixin {
  /// How fast the needle closes in: 63% of the way in this long.
  static const _ease = Duration(milliseconds: 90);

  late final Ticker _ticker = createTicker(_tick);
  double _shown = 0;
  Duration _last = Duration.zero;

  @override
  void didUpdateWidget(_Meter old) {
    super.didUpdateWidget(old);
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown = widget.cents;
    } else if (!_ticker.isActive && _shown != widget.cents) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final k = 1 - math.exp(-dt / (_ease.inMicroseconds / 1e6));
    setState(() => _shown += (widget.cents - _shown) * k);
    if ((widget.cents - _shown).abs() < 0.05) {
      _shown = widget.cents;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    key: TunerPage.meterKey,
    height: 88,
    width: double.infinity,
    child: CustomPaint(
      painter: _MeterPainter(
        cents: _shown,
        heard: widget.heard,
        inTune: widget.inTune,
        colors: context.colors,
      ),
    ),
  );
}

class _MeterPainter extends CustomPainter {
  _MeterPainter({
    required this.cents,
    required this.heard,
    required this.inTune,
    required this.colors,
  });

  final double cents;
  final bool heard;
  final bool inTune;
  final MetraColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    // Room for the needle's half width at either end.
    const inset = 3.0;
    double x(double c) => inset + (c + 50) / 100 * (size.width - 2 * inset);
    final mid = size.height / 2;
    final tick = Paint()..strokeWidth = 2;
    for (var c = -50; c <= 50; c += 5) {
      final long = c % 25 == 0;
      final half = size.height * (c == 0 ? 0.42 : (long ? 0.32 : 0.18));
      tick.color = c == 0 ? colors.text : (long ? colors.muted : colors.border);
      canvas.drawLine(
        Offset(x(c.toDouble()), mid - half),
        Offset(x(c.toDouble()), mid + half),
        tick,
      );
    }
    final needle = Paint()
      ..strokeWidth = inTune ? 6 : 4
      ..strokeCap = StrokeCap.round
      ..color = !heard
          ? colors.accent.withValues(alpha: 0.35)
          : (inTune ? colors.text : colors.accent);
    final at = x(cents.clamp(-50, 50));
    canvas.drawLine(Offset(at, 3), Offset(at, size.height - 3), needle);
  }

  @override
  bool shouldRepaint(_MeterPainter old) =>
      old.cents != cents ||
      old.heard != heard ||
      old.inTune != inTune ||
      old.colors != colors;
}
