/// Italian tempo marking shown under the BPM: the mechanical metronome
/// scale (Wittner). Where two ranges share an edge, the faster name takes
/// it. The scale starts at 40; slower tempos stay Largo, and Prestissimo
/// (200–208 on the scale) runs on to the 300 bpm limit.
String tempoName(int bpm) => switch (bpm) {
  < 60 => 'Largo',
  < 66 => 'Larghetto',
  < 76 => 'Adagio',
  < 108 => 'Andante',
  < 120 => 'Moderato',
  < 168 => 'Allegro',
  < 200 => 'Presto',
  _ => 'Prestissimo',
};
