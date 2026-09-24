import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/home_sections.dart';

void main() {
  test('every language gets row sections and playlist cards', () {
    for (final language in [...homeLanguages, null]) {
      final sections = homeSectionsFor(language);
      final rows =
          sections.where((s) => s.style == HomeSectionStyle.rows).toList();
      final cards =
          sections.where((s) => s.style == HomeSectionStyle.cards).toList();

      expect(rows, isNotEmpty, reason: '$language');
      expect(cards, isNotEmpty, reason: '$language');
      expect(rows.every((s) => s.query.trim().isNotEmpty), isTrue);
      expect(cards.every((s) => s.cards.isNotEmpty), isTrue);
    }
  });

  test('the first section is a row, so quick picks have a fallback query', () {
    for (final language in [...homeLanguages, null]) {
      expect(homeSectionsFor(language).first.style, HomeSectionStyle.rows);
    }
  });

  test('queries are unique within a page, so sections never repeat', () {
    for (final language in [...homeLanguages, null]) {
      final sections = homeSectionsFor(language);
      final queries = [
        for (final s in sections)
          if (s.style == HomeSectionStyle.rows) s.query,
        for (final s in sections) ...s.cards.map((c) => c.query),
      ];
      expect(queries.toSet().length, queries.length, reason: '$language');
    }
  });

  test('language pages are about that language', () {
    final tamil = homeSectionsFor('Tamil');
    expect(tamil.first.title, 'Trending in Tamil');
    expect(tamil.any((s) => s.title == 'Ilaiyaraaja classics'), isTrue);
    expect(homeSectionsFor('Telugu').any((s) => s.title.contains('Ilaiyaraaja')),
        isFalse);
  });

  test('greeting follows the time of day', () {
    expect(greetingFor(0), 'Good morning');
    expect(greetingFor(11), 'Good morning');
    expect(greetingFor(12), 'Good afternoon');
    expect(greetingFor(16), 'Good afternoon');
    expect(greetingFor(17), 'Good evening');
    expect(greetingFor(23), 'Good evening');
  });

  test('home rows skip jukeboxes but keep songs and unknown lengths', () {
    expect(isSongLength(const Duration(minutes: 4)), isTrue);
    expect(isSongLength(null), isTrue);
    expect(isSongLength(const Duration(minutes: 45)), isFalse);
  });
}
