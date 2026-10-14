/// Italian tempo marking shown under the BPM. Boundaries follow common
/// metronome markings, trimmed to the six names in the UI spec.
String tempoName(int bpm) => switch (bpm) {
  < 66 => 'Largo',
  < 76 => 'Adagio',
  < 108 => 'Andante',
  < 120 => 'Moderato',
  < 168 => 'Allegro',
  _ => 'Presto',
};
