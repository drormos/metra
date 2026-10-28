import 'library.dart';

/// A setlist as plain text for the phone's share menu (ui-spec.md "Set ⌄"
/// › "Share"): the set name and count, one line per song, then "Shared
/// from Metra".
String setlistShareText(Setlist setlist, List<Song> songs) => [
  '${setlist.name} (${songs.length == 1 ? '1 song' : '${songs.length} songs'})',
  for (final (i, song) in songs.indexed) '${i + 1}. ${songShareLine(song)}',
  '',
  'Shared from Metra',
].join('\n');

/// "Midnight Engine · 148 · 7/8"; a song with parts stays one line and
/// says what changes: "Glass Harbor · 120, 128, 140 · 4/4, 2/4".
String songShareLine(Song song) {
  final tempos = <int>[];
  final meters = <String>[];
  for (final part in song.parts) {
    // A Gradual part's end counts as a tempo.
    for (final t in [part.tempoStart, if (part.gradual) part.tempoEnd]) {
      if (!tempos.contains(t)) tempos.add(t);
    }
    final meter = part.pattern.timeSignature;
    if (!meters.contains(meter)) meters.add(meter);
  }
  final tempo = tempos.length <= 3
      ? tempos.join(', ')
      : '${tempos.reduce((a, b) => a < b ? a : b)}–'
            '${tempos.reduce((a, b) => a > b ? a : b)} '
            '(${tempos.length} tempos)';
  final meter = meters.every((m) => m == '4/4')
      ? null
      : meters.length <= 3
      ? meters.join(', ')
      : '${meters.length} time signatures';
  return [song.name, tempo, ?meter].join(' · ');
}
