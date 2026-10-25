/// Raw-JSON migrations for the saved library, applied in order on load,
/// so the parsers ([Library.fromJson]) only ever read the latest format.
///
/// A file's `version` says which steps it still needs: step `i` turns
/// version `i + 1` into `i + 2`. Every step works on decoded JSON (maps and
/// lists), never on model classes, so old shapes don't have to be
/// parseable by today's code.
///
/// Version history:
/// - 1 (builds 2–47, one `library.json`): fields grew over time; each
///   shipped shape is a golden fixture in `test/fixtures/`.
/// - 2 (build 49 on): `library.json` holds songs and setlists;
///   `settings.json` holds the app settings, the session and one-time
///   flags.
/// - 3 (build 56 on): settings gain `keepScreenOn` and `stageMode`.
/// - 4 (build 58 on): a song is a list of parts and an `end`; its `bpm`
///   and `pattern` became one open part.
library;

/// The latest format, and the two files' shapes in it.
const latestVersion = 4;

typedef Json = Map<String, Object?>;

/// The saved state as one map in the latest format: songs and setlists
/// under [libraryKeys], everything else is settings.
const libraryKeys = {'songs', 'setlists'};

/// Brings [json] (one combined map, any version up to [latestVersion]) to
/// the latest format. Throws [FormatException] for a version it doesn't
/// know (0 or below); newer versions are the caller's to refuse.
Json migrate(Json json) {
  final from = json['version'];
  if (from is! int || from < 1) {
    throw FormatException('Unknown library version: $from');
  }
  var current = json;
  for (var v = from; v < latestVersion; v++) {
    current = _steps[v - 1](current);
  }
  return current;
}

final List<Json Function(Json)> _steps = [_v1ToV2, _v2ToV3, _v3ToV4];

/// Version 1, in all the shapes it shipped in, to version 2:
/// - fields added after build 2 get their defaults (time signature unit,
///   polyrhythm and its pulses, played-at, volumes and their polyrhythm
///   level, theme, vibration, session);
/// - the "classic" click sound (removed in 1.1.0) becomes Woodblock;
/// - the three hint flags (1.2.0–1.3.0) join `tipsSeen`;
/// - a song's / Free play's `countIn` (builds 37–38) and the first
///   "When I press Start" keys (build 39: `countIn`, `until`, `stopAfter`)
///   become today's `onStart`.
Json _v1ToV2(Json v1) {
  Json pattern(Object? raw) {
    final p = {...raw! as Json};
    p['beatUnit'] ??= 4;
    p['polyrhythm'] ??= 0;
    p['polyStates'] ??= [
      for (var i = 0; i < (p['polyrhythm'] as int); i++) 'normal',
    ];
    return p;
  }

  Json onStart(Object? raw, Object? countIn) {
    final old = raw is Json ? raw : <String, Object?>{'countIn': countIn};
    final o = {...old};
    final bars = o.remove('countIn');
    if (bars is int && !o.containsKey('countInOn')) {
      o['countInOn'] = bars == 1 || bars == 2;
      o['countInBars'] = bars == 2 ? 2 : 1;
    }
    final until = o.remove('until');
    if (!o.containsKey('upTo')) o['upTo'] = until;
    final stop = o.remove('stopAfter');
    if (stop is String && !o.containsKey('stopOn')) {
      o['stopOn'] = stop != 'off';
      o['stopBy'] = stop == 'bars' ? 'bars' : 'time';
    }
    return o;
  }

  // An entry that's not even a map is left for the parser to skip.
  Object? song(Object? raw) {
    if (raw is! Json) return raw;
    final s = {...raw};
    if (s['pattern'] is Json) s['pattern'] = pattern(s['pattern']);
    s['onStart'] = onStart(s['onStart'], s.remove('countIn'));
    s.putIfAbsent('editedAt', () => null);
    s.putIfAbsent('playedAt', () => null);
    return s;
  }

  Object? setlist(Object? raw) {
    if (raw is! Json) return raw;
    return {...raw, 'playedAt': raw['playedAt']};
  }

  final volumes = {
    'accent': 1.0,
    'beat': 0.8,
    'subdivision': 0.45,
    'polyrhythm': 0.7,
    ...?(v1['volumes'] as Json?),
  };
  final tips = <String>{
    ...?(v1['tipsSeen'] as List?)?.whereType<String>(),
    if (v1['swipeHintSeen'] == true) swipeHintTip,
    if (v1['songsHintSeen'] == true) songsHintTip,
    if (v1['setsHintSeen'] == true) setsHintTip,
  };
  return {
    'version': 2,
    'songs': [for (final s in v1['songs']! as List) song(s)],
    'setlists': [for (final s in v1['setlists']! as List) setlist(s)],
    'lastBpm': v1['lastBpm'] ?? 120,
    'lastPattern': v1['lastPattern'] is Json
        ? pattern(v1['lastPattern'])
        : null,
    'lastOnStart': onStart(v1['lastOnStart'], v1['lastCountIn']),
    'visualOffsetMs': v1['visualOffsetMs'] ?? 0,
    'clickSound': switch (v1['clickSound']) {
      'classic' || null => 'woodblock',
      final name => name,
    },
    'themeMode': v1['themeMode'] ?? 'system',
    'vibrate': v1['vibrate'] ?? true,
    'volumes': volumes,
    'activeSetlistId': v1['activeSetlistId'],
    'currentSongId': v1['currentSongId'],
    'currentPosition': v1['currentPosition'] ?? -1,
    'tipsSeen': tips.toList()..sort(),
  };
}

/// Version 2 to 3: the screen stays on while Metra is open (the new
/// default), and stage mode starts off.
Json _v2ToV3(Json v2) => {
  ...v2,
  'version': 3,
  'keepScreenOn': 'whileOpen',
  'stageMode': false,
};

/// Version 3 to 4: every song becomes one open part with its tempo and
/// pattern ("Part 1"), ending with Stop. Entries that aren't songs are
/// left for the parser to skip.
Json _v3ToV4(Json v3) => {
  ...v3,
  'version': 4,
  'songs': [
    for (final raw in v3['songs']! as List)
      if (raw is Json)
        {
          for (final MapEntry(:key, :value) in raw.entries)
            if (key != 'bpm' && key != 'pattern') key: value,
          'parts': [
            {
              'id': 'part-1',
              'name': 'Part 1',
              'bars': null,
              'tempoStart': raw['bpm'],
              'tempoEnd': raw['bpm'],
              'pattern': raw['pattern'],
            },
          ],
          'end': 'stop',
        }
      else
        raw,
  ],
};

/// The one-time hints' names in `tipsSeen` (version 1 had a flag each).
const swipeHintTip = 'set-swipe-hint';
const songsHintTip = 'songs-swipe-hint';
const setsHintTip = 'sets-swipe-hint';
