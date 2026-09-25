// Deciding whether search results are about what was typed — tolerant of
// typos and of the many ways Tamil (and other Indian-language) words are
// written in English letters.
//
// JioSaavn matches titles literally: "kamatchi song" (extra word) or a
// description like "vijay beast arabic song" returns *something*, just not
// the song. Before this, any non-empty answer was shown as-is.

import 'media_item_model.dart';

/// Words people add to a search that are never part of a song's name.
const _filler = {
  'song', 'songs', 'lyrics', 'lyric', 'video', 'videos', 'audio', 'official',
  'full', 'hd', 'mp3', 'new', 'latest', 'movie', 'film', 'tamil', 'hindi',
  'telugu', 'malayalam', 'kannada', 'from', 'the', 'a', 'of', 'by',
};

/// [query] without filler words ("kamatchi song lyrics" → "kamatchi").
/// Unchanged if that would leave nothing.
String stripFiller(String query) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !_filler.contains(w))
      .toList();
  return words.isEmpty ? query.trim() : words.join(' ');
}

/// A word folded so spelling variants compare equal: lower case, letters
/// only, common transliteration pairs merged (zh→l, th/dh→t, ph→f, w→v,
/// sh→s, ks→x), and doubled letters collapsed ("Kaamaatchi" → "kamatchi",
/// "Vaseegara" → "vasegara").
String foldWord(String word) {
  var w = word.toLowerCase().replaceAll(RegExp(r'[^a-z\u0080-￿]'), '');
  for (final (from, to) in const [
    ('zh', 'l'),
    ('th', 't'),
    // த is written "th" or "dh" interchangeably.
    ('dh', 't'),
    ('ph', 'f'),
    ('sh', 's'),
    ('ks', 'x'),
    ('w', 'v'),
  ]) {
    w = w.replaceAll(from, to);
  }
  final out = StringBuffer();
  for (var i = 0; i < w.length; i++) {
    if (i == 0 || w[i] != w[i - 1]) out.write(w[i]);
  }
  return out.toString();
}

/// Edit distance, capped: returns [cap]+1 as soon as it's exceeded.
int _distance(String a, String b, int cap) {
  if ((a.length - b.length).abs() > cap) return cap + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = cur[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
      if (cur[j] < rowMin) rowMin = cur[j];
    }
    if (rowMin > cap) return cap + 1;
    prev = cur;
  }
  return prev[b.length];
}

/// Whether two words are the same word, allowing a typo or two.
bool wordsMatch(String typed, String candidate) {
  final a = foldWord(typed), b = foldWord(candidate);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  // A prefix of a longer word counts ("kannu" in "kannukulla").
  if (a.length >= 4 && b.startsWith(a)) return true;
  if (b.length >= 4 && a.startsWith(b)) return true;
  final cap = a.length <= 4 ? 1 : 2;
  return _distance(a, b, cap) <= cap;
}

List<String> _words(String s) =>
    s.toLowerCase().split(RegExp(r'[\s\-_,|/()"\[\]:.!?]+')).where((w) => w.length >= 2).toList();

/// Whether [results] look like answers to [query]: at least half of the
/// typed words (filler aside) appear — typos allowed — in the title, album
/// or artist of one of the top results. Words glued together count too
/// ("kannu kulla" matches "Kannukulla").
bool looksRelevant(String query, List<AppMediaItem> results, {int top = 5}) {
  if (results.isEmpty) return false;
  final typed = _words(stripFiller(query));
  if (typed.isEmpty) return true;
  for (final r in results.take(top)) {
    final text = '${r.title} ${r.album} ${r.artist}';
    final words = _words(text);
    final glued = foldWord(text.replaceAll(' ', ''));
    final hits = typed.where((t) =>
        words.any((w) => wordsMatch(t, w)) ||
        (foldWord(t).length >= 4 && glued.contains(foldWord(t)))).length;
    if (hits * 2 >= typed.length) return true;
  }
  return false;
}

/// A YouTube video title reduced to the song's name, for looking it up on
/// JioSaavn: "Arabic Kuthu - Official Lyric Video | Beast | Vijay" →
/// "Arabic Kuthu".
String songNameFromVideoTitle(String title) {
  var t = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ');
  t = t.split(RegExp(r'\s[|\-–—]\s|\|')).first;
  t = t.replaceAll(
      RegExp(r'\b(official|lyric|lyrical|video|audio|full|song|hd|4k)\b',
          caseSensitive: false),
      ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}
