import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/tempo_name.dart';

void main() {
  test('tempo names at their boundaries (metronome scale)', () {
    expect(tempoName(30), 'Largo');
    expect(tempoName(59), 'Largo');
    expect(tempoName(60), 'Larghetto');
    expect(tempoName(65), 'Larghetto');
    expect(tempoName(66), 'Adagio');
    expect(tempoName(75), 'Adagio');
    expect(tempoName(76), 'Andante');
    expect(tempoName(107), 'Andante');
    expect(tempoName(108), 'Moderato');
    expect(tempoName(119), 'Moderato');
    expect(tempoName(120), 'Allegro');
    expect(tempoName(167), 'Allegro');
    expect(tempoName(168), 'Presto');
    expect(tempoName(199), 'Presto');
    expect(tempoName(200), 'Prestissimo');
    expect(tempoName(300), 'Prestissimo');
  });
}
