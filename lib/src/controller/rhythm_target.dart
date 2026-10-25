import 'package:flutter/foundation.dart';

import '../model/metronome_pattern.dart';

/// What the Rhythm panel edits: the click, or one part of a song.
abstract interface class RhythmTarget implements Listenable {
  MetronomePattern get pattern;
  void setMeter(int beatsPerBar, int beatUnit);
  void setSubdivision(int stepsPerBeat);
  void setPolyrhythm(int n);
}
