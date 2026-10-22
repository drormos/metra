import 'package:flutter/material.dart';

/// Search in every list (ui-spec.md "Search (all search fields)"): a name
/// matches when the query appears anywhere in it, ignoring case and
/// accents; the matching part is drawn white and semibold.

// One plain letter per accented one, so folding keeps every index.
const _plain = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'č': 'c',
  'ć': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ō': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'š': 's',
  'ś': 's',
  'ž': 'z',
  'ź': 'z',
  'ż': 'z',
  'ř': 'r',
  'ł': 'l',
  'đ': 'd',
  'ď': 'd',
  'ť': 't',
};

/// Lowercase with accents dropped, the same length as [text].
String foldForSearch(String text) =>
    text.toLowerCase().split('').map((c) => _plain[c] ?? c).join();

/// Where the (trimmed) [query] appears in [name], or null. An empty query
/// matches everything (with no range).
({int start, int end})? searchMatch(String name, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return (start: 0, end: 0);
  final at = foldForSearch(name).indexOf(q);
  return at < 0 ? null : (start: at, end: at + q.length);
}

bool matchesSearch(String name, String query) =>
    searchMatch(name, query) != null;

/// [name] in [style], with the part matching [query] white and semibold.
class SearchName extends StatelessWidget {
  const SearchName(
    this.name, {
    super.key,
    required this.query,
    required this.style,
    required this.matchColor,
  });

  final String name;
  final String query;
  final TextStyle style;
  final Color matchColor;

  @override
  Widget build(BuildContext context) {
    final match = searchMatch(name, query);
    if (match == null || match.start == match.end) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: name.substring(0, match.start)),
          TextSpan(
            text: name.substring(match.start, match.end),
            style: TextStyle(color: matchColor, fontWeight: FontWeight.w600),
          ),
          TextSpan(text: name.substring(match.end)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The one muted line when nothing matches.
class NoMatches extends StatelessWidget {
  const NoMatches(this.what, this.query, {super.key, required this.color});

  /// "songs" or "sets".
  final String what;
  final String query;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
    child: Text(
      'No $what match "${query.trim()}"',
      key: const ValueKey('no-matches'),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, color: color),
    ),
  );
}
