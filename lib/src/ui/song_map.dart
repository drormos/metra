import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controller/metronome_controller.dart';
import '../model/song_part.dart';
import 'haptics.dart';
import 'tempo_ruler.dart';
import 'theme.dart';

/// The song map (ui-spec.md "Main screen for a song with parts",
/// `song-parts.reference.html` column 3): in the tempo ruler's slot, the
/// parts to scale under a fixed red needle, moving as the song plays.
/// Slide it and let go: it snaps to the start of the part under the
/// needle and goes there; a tap goes to the tapped part. Going there:
/// stopped, Start begins there; playing, on the next bar line
/// ([MetronomeController.jumpToPart]). Without [slide] (stage mode) only
/// taps.
class SongMap extends StatefulWidget {
  const SongMap({super.key, required this.controller, this.slide = true});

  final MetronomeController controller;
  final bool slide;

  /// The ruler's height, so nothing moves when the map takes its place.
  static const height = TempoRuler.height;
  static const pxPerBar = 14.0;
  static const minWidth = 24.0;
  static const gap = 3.0;

  /// Where each part starts and how wide it is, in map pixels.
  static List<({double x, double width})> layout(List<SongPart> parts) {
    var x = 0.0;
    return [
      for (final part in parts)
        () {
          final width = (part.bars * pxPerBar).clamp(minWidth, double.infinity);
          final block = (x: x, width: width);
          x += width + gap;
          return block;
        }(),
    ];
  }

  /// The map position of bar [bar] (+ [fraction]) of part [part].
  static double position(
    List<SongPart> parts,
    List<({double x, double width})> blocks,
    int part,
    int bar,
    double fraction,
  ) {
    final p = parts[part];
    final b = blocks[part];
    final into = bar + fraction;
    return b.x + (into / p.bars).clamp(0.0, 1.0) * b.width;
  }

  /// The part at map position [x] (the nearest one in a gap or past the
  /// ends).
  static int partAt(List<({double x, double width})> blocks, double x) {
    for (final (i, b) in blocks.indexed) {
      if (x < b.x + b.width + gap / 2) return i;
    }
    return blocks.length - 1;
  }

  @override
  State<SongMap> createState() => _SongMapState();
}

class _SongMapState extends State<SongMap> with TickerProviderStateMixin {
  MetronomeController get _controller => widget.controller;

  late final Ticker _ticker = createTicker(_tick);
  // The map position under the needle while following the click.
  double _x = 0;
  int _current = 0;
  // While dragging or snapping: the position under the finger.
  double? _drag;
  late final AnimationController _snap = AnimationController(vsync: this)
    ..addListener(
      () => setState(
        () => _drag = _snapTween.transform(
          Curves.decelerate.transform(_snap.value),
        ),
      ),
    );
  Tween<double> _snapTween = Tween(begin: 0, end: 0);
  // A part gone to while playing: held at its start until it plays.
  int? _going;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    _controller.removeListener(_sync);
    _ticker.dispose();
    _snap.dispose();
    super.dispose();
  }

  List<SongPart> get _parts => _controller.parts ?? const [];

  void _sync() {
    if (_controller.isPlaying) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      _going = null;
    }
    // Outside a frame: the last frame's time.
    _follow(SchedulerBinding.instance.currentSystemFrameTimeStamp);
  }

  void _tick(Duration _) =>
      _follow(SchedulerBinding.instance.currentFrameTimeStamp);

  void _follow(Duration frameTime) {
    final parts = _parts;
    if (parts.isEmpty || !mounted) return;
    final at = _controller.playheadAt(frameTime);
    if (at == null) return;
    final blocks = SongMap.layout(parts);
    var part = at.part.clamp(0, parts.length - 1);
    var x = SongMap.position(parts, blocks, part, at.bar, at.fraction);
    if (_going case final going?) {
      if (going == part) {
        _going = null;
      } else {
        part = going;
        x = blocks[going].x;
      }
    }
    if (x != _x || part != _current) {
      setState(() {
        _x = x;
        _current = part;
      });
    }
  }

  void _go(int part) {
    final parts = _parts;
    if (parts.isEmpty) return;
    Haptics.tick();
    final blocks = SongMap.layout(parts);
    if (_controller.isPlaying) _going = part;
    _snapTween = Tween(begin: _drag ?? _x, end: blocks[part].x);
    _snap.duration = MetraMotion.of(context, MetraMotion.mapSnap);
    _snap.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _drag = null);
    });
    _controller.jumpToPart(part);
    _follow(SchedulerBinding.instance.currentSystemFrameTimeStamp);
  }

  void _dragStart(DragStartDetails _) {
    // Mid-snap: from where the snap was going.
    final snapping = _snap.isAnimating;
    _snap.stop();
    setState(() => _drag = snapping ? _snapTween.end : (_drag ?? _x));
  }

  void _dragUpdate(DragUpdateDetails d) {
    final blocks = SongMap.layout(_parts);
    final end = blocks.last.x + blocks.last.width;
    setState(() => _drag = (_drag! - d.delta.dx).clamp(0.0, end));
  }

  void _dragEnd([DragEndDetails? _]) {
    final x = _drag;
    if (x == null) return;
    _go(SongMap.partAt(SongMap.layout(_parts), x));
  }

  void _tap(TapUpDetails d, double width) {
    final from = _snap.isAnimating ? _snapTween.end! : (_drag ?? _x);
    final x = from + d.localPosition.dx - width / 2;
    _go(SongMap.partAt(SongMap.layout(_parts), x));
  }

  @override
  Widget build(BuildContext context) {
    final parts = _parts;
    if (parts.isEmpty) return const SizedBox(height: SongMap.height);
    final current = _current.clamp(0, parts.length - 1);
    String spoken(int i) =>
        '${parts[i].name}, part ${i + 1} of ${parts.length}';
    // The ruler's 46px slot; the touch target overhangs it by 1px above
    // and below to make 48dp.
    return SizedBox(
      height: SongMap.height,
      child: OverflowBox(
        minHeight: 48,
        maxHeight: 48,
        child: Semantics(
          slider: true,
          label: 'Song map',
          value: spoken(current),
          increasedValue: current + 1 < parts.length
              ? spoken(current + 1)
              : null,
          decreasedValue: current > 0 ? spoken(current - 1) : null,
          onIncrease: current + 1 < parts.length
              ? () => _go(current + 1)
              : null,
          onDecrease: current > 0 ? () => _go(current - 1) : null,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d, box.maxWidth),
              onHorizontalDragStart: widget.slide ? _dragStart : null,
              onHorizontalDragUpdate: widget.slide ? _dragUpdate : null,
              onHorizontalDragEnd: widget.slide ? _dragEnd : null,
              onHorizontalDragCancel: widget.slide ? _dragEnd : null,
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: CustomPaint(
                    painter: _MapPainter(
                      parts: parts,
                      at: _drag ?? _x,
                      current: current,
                      loops: widget.controller.songEnd == SongEnd.loopLastPart,
                      colors: context.colors,
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
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.parts,
    required this.at,
    required this.current,
    required this.loops,
    required this.colors,
  });

  final List<SongPart> parts;
  final double at;
  final int current;

  /// The last part loops until Stop: a loop icon after its name.
  final bool loops;
  final MetraColors colors;

  static const _blockTop = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Blocks end at the map's edges, under the fade: unclipped, the part
    // of a block past the edge showed again at full brightness.
    canvas.clipRect(Offset.zero & size);
    final centre = size.width / 2;
    final fill = Paint();
    // Top and bottom rules, as the ruler's.
    fill.color = colors.divider;
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, size.width, 2), fill)
      ..drawRect(Rect.fromLTWH(0, size.height - 2, size.width, 2), fill);

    final blocks = SongMap.layout(parts);
    final height = size.height - 2 * _blockTop;
    for (final (i, part) in parts.indexed) {
      final b = blocks[i];
      final left = centre + b.x - at;
      if (left > size.width || left + b.width < 0) continue;
      final selected = i == current;
      final color = selected ? colors.text : colors.tickResting;
      final rect = Rect.fromLTWH(left, _blockTop, b.width, height);
      fill.color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        fill,
      );
      _label(
        canvas,
        part,
        rect,
        selected,
        loop: loops && i == parts.length - 1,
      );
    }

    // The edges fade into the background.
    for (final right in [false, true]) {
      final edge = Rect.fromLTWH(
        right ? size.width - 32 : 0,
        0,
        32,
        size.height,
      );
      fill.shader = LinearGradient(
        begin: right ? Alignment.centerRight : Alignment.centerLeft,
        end: right ? Alignment.centerLeft : Alignment.centerRight,
        colors: [colors.background, colors.background.withAlpha(0)],
      ).createShader(edge);
      canvas.drawRect(edge, fill);
    }
    fill.shader = null;

    // The fixed needle on top.
    fill.color = colors.accent;
    canvas.drawRect(Rect.fromLTWH(centre - 2, 0, 4, size.height), fill);
  }

  /// The name inside when it fits; a looping last part adds the loop icon.
  void _label(
    Canvas canvas,
    SongPart part,
    Rect rect,
    bool selected, {
    required bool loop,
  }) {
    final color = selected ? colors.background : colors.muted;
    final name = TextPainter(
      text: TextSpan(
        text: part.name,
        style: TextStyle(
          fontFamily: MetraFonts.body,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const icon = Icons.repeat;
    final loopIcon = loop
        ? (TextPainter(
            text: TextSpan(
              text: String.fromCharCode(icon.codePoint),
              style: TextStyle(
                fontFamily: icon.fontFamily,
                package: icon.fontPackage,
                fontSize: 12,
                color: color,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout())
        : null;
    final width = name.width + (loopIcon == null ? 0 : loopIcon.width + 3);
    if (width <= rect.width - 6) {
      var left = rect.center.dx - width / 2;
      name.paint(canvas, Offset(left, rect.center.dy - name.height / 2));
      if (loopIcon != null) {
        left += name.width + 3;
        loopIcon.paint(
          canvas,
          Offset(left, rect.center.dy - loopIcon.height / 2),
        );
      }
    }
    name.dispose();
    loopIcon?.dispose();
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.at != at ||
      old.current != current ||
      old.loops != loops ||
      old.colors != colors ||
      !identical(old.parts, parts);
}
