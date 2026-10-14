import 'package:flutter_test/flutter_test.dart';
import 'package:metra/src/model/tempo_name.dart';

void main() {
  test('tempo names at their boundaries', () {
    expect(tempoName(30), 'Largo');
    expect(tempoName(65), 'Largo');
    expect(tempoName(66), 'Adagio');
    expect(tempoName(76), 'Andante');
    expect(tempoName(108), 'Moderato');
    expect(tempoName(120), 'Allegro');
    expect(tempoName(167), 'Allegro');
    expect(tempoName(168), 'Presto');
    expect(tempoName(300), 'Presto');
  });
}
