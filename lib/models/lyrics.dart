/// One line of time-synced lyrics.
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// Lyrics for a song: time-synced lines when a source has them (the Now
/// Playing panel then highlights and follows the line being sung), or plain
/// text otherwise.
class Lyrics {
  /// Sorted by time; empty when only plain text is known.
  final List<LyricLine> lines;
  final String plain;

  /// Where they came from, for the small credit under the panel.
  final String source;

  const Lyrics({required this.lines, required this.plain, required this.source});

  bool get isSynced => lines.isNotEmpty;

  factory Lyrics.synced(List<LyricLine> lines, String source) => Lyrics(
        lines: lines,
        plain: lines.map((l) => l.text).join('\n'),
        source: source,
      );

  factory Lyrics.plainText(String text, String source) =>
      Lyrics(lines: const [], plain: text, source: source);

  /// The line being sung at [position]: the last one whose time has passed,
  /// or -1 before the first.
  int indexAt(Duration position) {
    var lo = 0, hi = lines.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  static final _stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');

  /// Parses LRC: `[mm:ss.xx]text`. A line may carry several stamps (a
  /// repeated chorus); metadata tags like `[ar:…]` and blank lines are
  /// skipped. Returns lines sorted by time.
  static List<LyricLine> parseLrc(String lrc) {
    final out = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final stamps = _stamp.allMatches(raw).toList();
      if (stamps.isEmpty) continue;
      final text = raw.substring(stamps.last.end).trim();
      if (text.isEmpty) continue;
      for (final m in stamps) {
        final fraction = m.group(3);
        final ms = fraction == null
            ? 0
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
        out.add(LyricLine(
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: ms,
          ),
          text,
        ));
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }
}
