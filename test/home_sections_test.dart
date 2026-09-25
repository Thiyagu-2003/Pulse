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


  test('home rows skip jukeboxes but keep songs and unknown lengths', () {
    expect(isSongLength(const Duration(minutes: 4)), isTrue);
    expect(isSongLength(null), isTrue);
    expect(isSongLength(const Duration(minutes: 45)), isFalse);
  });

  group('customizable home', () {
    List<String> ids(List<HomeSection> s) => s.map((x) => x.id).toList();

    test('standard page: recently played, then the catalogue', () {
      final page = arrangeHome('Tamil', HomeLayout.standard);
      expect(page.first.id, 'recent');
      expect(ids(page).sublist(1), ids(homeSectionsFor('Tamil')));
    });

    test('moved sections come first; the rest keep their order', () {
      final page = arrangeHome(
          'Tamil', const HomeLayout(order: ['top_playlists', 'trending']));
      expect(ids(page).take(3), ['top_playlists', 'trending', 'recent']);
      expect(ids(page).toSet().length, page.length); // nothing duplicated
    });

    test('hidden sections are left out, but listed for the editor', () {
      const layout = HomeLayout(hidden: {'recent', 'nineties'});
      expect(ids(arrangeHome('Tamil', layout)), isNot(contains('recent')));
      expect(ids(arrangeHome('Tamil', layout)), isNot(contains('nineties')));
      expect(ids(arrangeHome('Tamil', layout, includeHidden: true)),
          containsAll(['recent', 'nineties']));
    });

    test('added sections are rows of a playlist search, placeable anywhere', () {
      const layout = HomeLayout(
        custom: [('custom_1', 'Yuvan Shankar Raja')],
        order: ['custom_1'],
      );
      final first = arrangeHome('Tamil', layout).first;
      expect(first.id, 'custom_1');
      expect(first.custom, isTrue);
      expect(first.query, 'playlist:Yuvan Shankar Raja');
    });

    test('ids for another language, or unknown ones, are ignored', () {
      // "anirudh" only exists on the Tamil page.
      final page = arrangeHome('Hindi',
          const HomeLayout(order: ['anirudh', 'gone', 'love']));
      expect(page.first.id, 'love');
    });

    test('layout survives JSON; damaged settings give the standard page', () {
      const layout = HomeLayout(
        order: ['love'],
        hidden: {'recent'},
        custom: [('custom_9', 'Rainy day')],
      );
      final back = HomeLayout.fromJson(layout.toJson());
      expect(back.order, ['love']);
      expect(back.hidden, {'recent'});
      expect(back.custom.single, ('custom_9', 'Rainy day'));
      expect(HomeLayout.fromJson('nonsense').order, isEmpty);
      expect(HomeLayout.fromJson({'order': 'x', 'custom': [1]}).custom, isEmpty);
    });

    test('section ids are unique on every page', () {
      for (final language in [...homeLanguages, null]) {
        final all = ids(arrangeHome(language, HomeLayout.standard));
        expect(all.toSet().length, all.length, reason: '$language');
      }
    });
  });
}
