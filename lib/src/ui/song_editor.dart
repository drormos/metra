import 'package:flutter/material.dart';

import '../controller/library_controller.dart';
import '../controller/metronome_controller.dart';
import '../model/library.dart';
import '../model/metronome_pattern.dart';
import '../timing/tap_tempo.dart';
import 'beat_indicator.dart';
import 'editor_scaffold.dart';
import 'haptics.dart';
import 'meter_control.dart';
import 'song_library.dart';
import 'subdivision_icon.dart';
import 'tempo_controls.dart';
import 'tempo_ruler.dart';
import 'theme.dart';

/// Opens the song editor (ui-spec.md "Song editor") for [song], or a new
/// song when null. Completes with the saved song, or null if cancelled or
/// deleted. Editing doesn't touch the click unless Preview is on; leaving
/// ends the preview, restoring what the main screen was doing. Saving the
/// loaded song then applies its changes to [metronome] without restarting
/// the bar.
Future<Song?> openSongEditor(
  BuildContext context,
  LibraryController library,
  MetronomeController metronome, {
  Song? song,
}) async {
  final saved = await Navigator.push(
    context,
    MaterialPageRoute<Song>(
      builder: (_) =>
          SongEditor(library: library, metronome: metronome, song: song),
    ),
  );
  metronome.endPreview();
  if (saved != null && saved.id == library.currentSong?.id) {
    metronome.applyEdit(bpm: saved.bpm, pattern: saved.pattern);
  }
  return saved;
}

class SongEditor extends StatefulWidget {
  const SongEditor({
    super.key,
    required this.library,
    required this.metronome,
    this.song,
  });

  final LibraryController library;

  /// Only for Preview; [openSongEditor] restores it on leaving.
  final MetronomeController metronome;

  /// Null: a new song.
  final Song? song;

  static const nameKey = Key('song-name');
  static const bpmKey = Key('song-bpm');
  static const tapKey = Key('song-tap');
  static const patternKey = Key('song-pattern');
  static const deleteKey = Key('delete-song');
  static const previewKey = Key('song-preview');

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
  // A new song starts at the main screen's tempo, so a tempo just found
  // becomes the song's; everything else starts from the defaults.
  late final int _initialBpm = widget.song?.bpm ?? widget.metronome.bpm;
  late int _bpm = _initialBpm;
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
      _bpm != _initialBpm ||
      _pattern != (widget.song?.pattern ?? const MetronomePattern.standard());

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  MetronomeController get _metronome => widget.metronome;

  bool get _previewPlaying => _metronome.previewing && _metronome.isPlaying;

  /// Every touch that edits the draft ticks (ui-spec.md "Haptics"), and a
  /// running preview hears it at once. The tempo ruler and steps tick
  /// themselves ([tick] false): the ruler only on fives.
  void _edit(VoidCallback change, {bool tick = true}) {
    if (tick) Haptics.tick();
    setState(change);
    if (_previewPlaying) _metronome.applyEdit(bpm: _bpm, pattern: _pattern);
  }

  /// Stop ends the preview: the main screen's click comes back at once
  /// (or stays silent if it was stopped).
  void _togglePreview() {
    Haptics.medium(); // like Start/Stop
    _previewPlaying
        ? _metronome.endPreview()
        : _metronome.preview(bpm: _bpm, pattern: _pattern);
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
    final ok = await confirm(
      context,
      SongLibrary.deleteMessage([song], _library.setlistsUsing(song.id)),
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
    // One name per song keeps lists unambiguous.
    final taken = _library.songNameTaken(_name.text, exceptId: song?.id);
    return EditorScaffold(
      title: 'Song',
      actionLabel: 'Save',
      dirty: _dirty,
      onAction: _name.text.trim().isEmpty || taken ? null : _save,
      bottom: SizedBox(
        height: 60,
        child: ListenableBuilder(
          listenable: _metronome,
          builder: (context, _) => OutlinedButton.icon(
            key: SongEditor.previewKey,
            style: OutlinedButton.styleFrom(foregroundColor: colors.text),
            onPressed: _togglePreview,
            icon: Icon(
              _previewPlaying ? Icons.stop : Icons.play_arrow,
              size: 20,
            ),
            label: Text(
              _previewPlaying ? 'Stop' : 'Preview',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          LabeledField(
            key: SongEditor.nameKey,
            label: 'Name',
            controller: _name,
            autofocus: _isNew,
            onChanged: (_) => setState(() {}),
            error: taken ? 'Another song already has this name' : null,
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
          MeterControl(
            beats: _pattern.beatsPerBar,
            unit: _pattern.beatUnit,
            onChanged: (beats, unit) => _edit(
              () => _pattern = _pattern.withBeats(beats, beatUnit: unit),
            ),
          ),
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

  /// The main screen's tempo controls, smaller: number, ruler, steps.
  Widget _tempo(MetraColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        // Shrinks rather than overflowing on narrow phones.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: BpmReadout(
            bpm: _bpm,
            fontSize: 84,
            unitSize: 16,
            numberKey: SongEditor.bpmKey,
          ),
        ),
      ),
      const SizedBox(height: 10),
      TempoRuler(
        bpm: _bpm,
        onChanged: (bpm) => _edit(() => _bpm = bpm, tick: false),
      ),
      const SizedBox(height: 12),
      TempoSteps(
        bpm: _bpm,
        height: 52,
        fontSize: 24,
        onStep: (delta) => _edit(
          () => _bpm = (_bpm + delta).clamp(
            MetronomeController.minBpm,
            MetronomeController.maxBpm,
          ),
          tick: false,
        ),
      ),
    ],
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
