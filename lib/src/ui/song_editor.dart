import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import '../model/metronome_pattern.dart';
import '../timing/tap_tempo.dart';
import 'beat_indicator.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'repeat_button.dart';
import 'subdivision_icon.dart';
import 'theme.dart';

/// Opens the song editor (ui-spec.md "Song editor") for [song], or a new
/// song when null. Completes with the saved song, or null if cancelled or
/// deleted. Editing never touches the click.
Future<Song?> openSongEditor(
  BuildContext context,
  LibraryController library, {
  Song? song,
}) => Navigator.push(
  context,
  MaterialPageRoute<Song>(
    builder: (_) => SongEditor(library: library, song: song),
  ),
);

class SongEditor extends StatefulWidget {
  const SongEditor({super.key, required this.library, this.song});

  final LibraryController library;

  /// Null: a new song.
  final Song? song;

  static const nameKey = Key('song-name');
  static const bpmKey = Key('song-bpm');
  static const tapKey = Key('song-tap');
  static const beatsKey = Key('song-beats');
  static const patternKey = Key('song-pattern');
  static const deleteKey = Key('delete-song');

  static const maxBeats = 16;

  /// "Quarter notes, accent on 1" / "Sixteenths, custom pattern".
  static String summary(MetronomePattern pattern) =>
      '${_subdivisionNames[pattern.stepsPerBeat]}, '
      '${pattern.isDefault ? 'accent on 1' : 'custom pattern'}';

  static const _subdivisionNames = {
    1: 'Quarter notes',
    2: 'Eighth notes',
    3: 'Triplets',
    4: 'Sixteenths',
  };

  @override
  State<SongEditor> createState() => _SongEditorState();
}

class _SongEditorState extends State<SongEditor> {
  // The draft: nothing is saved until Save.
  late final String _initialName =
      widget.song?.name ?? widget.library.newSongName();
  late final _name = TextEditingController(text: _initialName)
    // A new song's default name is selected, so typing replaces it.
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: _initialName.length,
    );
  late int _bpm = widget.song?.bpm ?? 120;
  late MetronomePattern _pattern =
      widget.song?.pattern ?? const MetronomePattern.standard();
  bool _expanded = false;
  final _tapClock = Stopwatch()..start();
  final _tapTempo = TapTempo(
    minBpm: MetronomeController.minBpm,
    maxBpm: MetronomeController.maxBpm,
  );

  LibraryController get _library => widget.library;
  bool get _isNew => widget.song == null;

  bool get _dirty =>
      _name.text != _initialName ||
      _bpm != (widget.song?.bpm ?? 120) ||
      _pattern != (widget.song?.pattern ?? const MetronomePattern.standard());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Every touch that edits the draft ticks (ui-spec.md "Haptics").
  void _edit(VoidCallback change) {
    Haptics.tick();
    setState(change);
  }

  void _save() {
    final name = _name.text.trim();
    final song = widget.song;
    if (song == null) {
      final saved = _library.addSong(name: name, bpm: _bpm, pattern: _pattern);
      return Navigator.pop(context, saved);
    }
    _library.updateSong(
      song.copyWith(name: name, bpm: _bpm, pattern: _pattern),
    );
    Navigator.pop(context, _library.songById(song.id));
  }

  Future<void> _delete() async {
    final song = widget.song!;
    final sets = _library.setlistsUsing(song.id).map((l) => l.name).toList();
    final ok = await confirm(
      context,
      sets.isEmpty
          ? 'Delete “${song.name}”?'
          : 'Delete “${song.name}”? It will be removed from '
                '${sets.join(', ')}.',
      'Delete',
    );
    if (!ok || !mounted) return;
    _library.deleteSong(song.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final song = widget.song;
    final sets = song == null
        ? const <Setlist>[]
        : _library.setlistsUsing(song.id);
    return EditorScaffold(
      title: 'Song',
      actionLabel: 'Save',
      dirty: _dirty,
      onAction: _name.text.trim().isEmpty ? null : _save,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          LabeledField(
            key: SongEditor.nameKey,
            label: 'Name',
            controller: _name,
            autofocus: _isNew,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontFamily: MetraFonts.condensed,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          _label('Tempo'),
          _tempo(colors),
          const SizedBox(height: 10),
          SizedBox(
            height: 48,
            // Registers on pointer down, as on the main screen: tap-up
            // timing varies with how long the finger rests.
            child: Listener(
              onPointerDown: (_) {
                final bpm = _tapTempo.tap(_tapClock.elapsed);
                _edit(() => _bpm = bpm ?? _bpm);
              },
              child: OutlinedButton(
                key: SongEditor.tapKey,
                onPressed: () {},
                child: const Text('Tap tempo', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _label('Time signature'),
          _meter(colors),
          const SizedBox(height: 28),
          _patternHeader(colors),
          if (_expanded) ...[
            const SizedBox(height: 20),
            _label('Subdivision'),
            _subdivision(colors),
            const SizedBox(height: 20),
            _label('Pattern'),
            Text(
              'Tap a beat to make it accented or muted. Tap the small cells '
              'to turn single subdivisions on or off.',
              style: TextStyle(fontSize: 13, color: colors.muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            for (var beat = 0; beat < _pattern.beatsPerBar; beat++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _patternRow(colors, beat),
              ),
          ],
          if (sets.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _usage(sets),
                style: TextStyle(
                  fontSize: 14,
                  color: colors.muted,
                  height: 1.5,
                ),
              ),
            ),
          if (!_isNew)
            Padding(
              padding: const EdgeInsets.only(top: 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: SongEditor.deleteKey,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.accentSounding,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: _delete,
                  child: const Text(
                    'Delete song',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _usage(List<Setlist> sets) {
    final names = sets.map((l) => l.name).join(', ');
    return switch (sets.length) {
      1 => 'In 1 setlist: $names.',
      2 => 'In 2 setlists: $names. Changes apply to both.',
      final n => 'In $n setlists: $names. Changes apply to all.',
    };
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 14, color: context.colors.muted),
    ),
  );

  Widget _stepButton(
    String label, {
    required double size,
    required double fontSize,
    required VoidCallback? onPressed,
    bool accelerate = true,
  }) => SizedBox.square(
    dimension: size,
    child: RepeatButton(
      accelerate: accelerate,
      style: FilledButton.styleFrom(
        backgroundColor: context.colors.surface,
        foregroundColor: context.colors.text,
        padding: EdgeInsets.zero,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          fontFamily: MetraFonts.condensed,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  Widget _tempo(MetraColors colors) => Row(
    children: [
      _stepButton(
        '−',
        size: 56,
        fontSize: 30,
        onPressed: _bpm > MetronomeController.minBpm
            ? () => _edit(() => _bpm--)
            : null,
      ),
      Expanded(
        // Shrinks rather than overflowing on narrow phones.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_bpm',
                key: SongEditor.bpmKey,
                style: const TextStyle(
                  fontFamily: MetraFonts.condensed,
                  fontSize: 84,
                  fontWeight: FontWeight.w700,
                  height: 0.9,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Text('bpm', style: TextStyle(fontSize: 16, color: colors.muted)),
            ],
          ),
        ),
      ),
      _stepButton(
        '+',
        size: 56,
        fontSize: 30,
        onPressed: _bpm < MetronomeController.maxBpm
            ? () => _edit(() => _bpm++)
            : null,
      ),
    ],
  );

  Widget _meter(MetraColors colors) {
    final beats = _pattern.beatsPerBar;
    const big = TextStyle(
      fontFamily: MetraFonts.condensed,
      fontSize: 40,
      fontWeight: FontWeight.w700,
    );
    return Row(
      children: [
        _stepButton(
          '−',
          size: 48,
          fontSize: 26,
          accelerate: false,
          onPressed: beats > 1
              ? () => _edit(() => _pattern = _pattern.withBeats(beats - 1))
              : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$beats',
            key: SongEditor.beatsKey,
            textAlign: TextAlign.center,
            style: big,
          ),
        ),
        _stepButton(
          '+',
          size: 48,
          fontSize: 26,
          accelerate: false,
          onPressed: beats < SongEditor.maxBeats
              ? () => _edit(() => _pattern = _pattern.withBeats(beats + 1))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '/',
            style: big.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.muted,
            ),
          ),
        ),
        Expanded(
          child: _segmented(colors, [
            for (final unit in const [4, 8])
              (
                selected: _pattern.beatUnit == unit,
                onTap: () => _edit(
                  () => _pattern = _pattern.withBeats(beats, beatUnit: unit),
                ),
                child: Text(
                  '$unit',
                  style: const TextStyle(
                    fontFamily: MetraFonts.condensed,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ]),
        ),
      ],
    );
  }

  /// Options in one 2px frame; the selected one filled with the text color.
  Widget _segmented(
    MetraColors colors,
    List<({bool selected, VoidCallback onTap, Widget child})> options,
  ) => Container(
    decoration: BoxDecoration(
      border: Border.all(color: colors.border, width: 2),
      borderRadius: BorderRadius.circular(4),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option.selected,
                child: Material(
                  color: option.selected ? colors.text : colors.background,
                  child: InkWell(
                    onTap: option.onTap,
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: option.selected
                                ? colors.background
                                : colors.text,
                          ),
                          child: option.child,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _patternHeader(MetraColors colors) => SizedBox(
    height: 72,
    child: OutlinedButton(
      key: SongEditor.patternKey,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        foregroundColor: colors.text,
      ),
      onPressed: () => setState(() => _expanded = !_expanded),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pattern and subdivision',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  SongEditor.summary(_pattern),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.muted,
                  ),
                ),
              ],
            ),
          ),
          Icon(_expanded ? Icons.expand_less : Icons.expand_more),
        ],
      ),
    ),
  );

  Widget _subdivision(MetraColors colors) => Row(
    children: [
      for (var steps = 1; steps <= 4; steps++) ...[
        if (steps > 1) const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 56,
            child: _option(
              colors,
              key: ValueKey('subdivision-$steps'),
              selected: _pattern.stepsPerBeat == steps,
              onTap: () =>
                  _edit(() => _pattern = _pattern.withSubdivision(steps)),
              child: SubdivisionIcon(steps),
            ),
          ),
        ),
      ],
    ],
  );

  /// An outlined option, filled with the text color when selected.
  Widget _option(
    MetraColors colors, {
    required Key key,
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) => Semantics(
    selected: selected,
    child: OutlinedButton(
      key: key,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: selected ? colors.text : null,
        foregroundColor: selected ? colors.background : colors.text,
        side: selected ? BorderSide.none : null,
      ),
      onPressed: onTap,
      child: child,
    ),
  );

  Widget _patternRow(MetraColors colors, int beat) {
    final perBeat = _pattern.stepsPerBeat;
    final first = beat * perBeat;
    final level = _pattern.steps[first];
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            '${beat + 1}',
            style: TextStyle(fontSize: 14, color: colors.muted),
          ),
        ),
        const SizedBox(width: 10),
        _cell(
          key: ValueKey('pattern-beat-$beat'),
          label: 'Beat ${beat + 1}: ${_levelNames[level]}',
          width: 64,
          color: switch (level) {
            StepLevel.accent => colors.accentResting,
            StepLevel.silent => colors.mutedFill,
            _ => colors.beatResting,
          },
          muted: level == StepLevel.silent,
          onTap: () => _edit(() => _pattern = _pattern.cycleBeat(beat)),
        ),
        if (perBeat > 1) ...[
          const SizedBox(width: 10),
          for (var cell = 1; cell < perBeat; cell++) ...[
            if (cell > 1) const SizedBox(width: 6),
            Expanded(
              child: Builder(
                builder: (context) {
                  final on = _pattern.steps[first + cell] != StepLevel.silent;
                  return _cell(
                    key: ValueKey('pattern-cell-$beat-$cell'),
                    label:
                        'Beat ${beat + 1}, subdivision ${cell + 1}: '
                        '${on ? 'on' : 'off'}',
                    color: on ? colors.border : colors.mutedFill,
                    muted: !on,
                    onTap: () =>
                        _edit(() => _pattern = _pattern.toggleCell(beat, cell)),
                  );
                },
              ),
            ),
          ],
          // Keeps cells the same width for every subdivision (3 per row in
          // the reference): the free slots stay empty.
          for (var empty = perBeat; empty < 4; empty++) ...[
            const SizedBox(width: 6),
            const Expanded(child: SizedBox()),
          ],
        ],
      ],
    );
  }

  static const _levelNames = {
    StepLevel.accent: 'accent',
    StepLevel.normal: 'regular',
    StepLevel.silent: 'muted',
    StepLevel.soft: 'regular',
  };

  Widget _cell({
    required Key key,
    required String label,
    required Color color,
    required bool muted,
    required VoidCallback onTap,
    double? width,
  }) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: width,
          height: 48,
          color: color,
          child: muted
              ? CustomPaint(painter: MutedLine(context.colors.mutedLine))
              : null,
        ),
      ),
    ),
  );
}
