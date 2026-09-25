// What the Online home page shows, as plain data so it can be unit tested.
//
// Every section is a query for YoutubeService.searchMusic (JioSaavn first,
// with the `trending:` / `playlist:` / `radio:` prefixes for its listings).

import 'listening_stats.dart';
import 'media_item_model.dart';

/// Languages offered by the chips and in Settings, in display order.
const List<String> homeLanguages = [
  'Tamil',
  'Telugu',
  'Hindi',
  'Malayalam',
  'Kannada',
  'Punjabi',
  'Bengali',
  'English',
];

enum HomeSectionStyle {
  /// Pages of four track rows, swiped sideways.
  rows,

  /// Square cards that each open their own track list.
  cards,

  /// The quick-picks grid of recently played songs.
  recent,
}

class HomeCard {
  final String title;
  final String query;
  const HomeCard(this.title, this.query);
}

class HomeSection {
  /// Stable across languages ("hits" is "Tamil hits" or "Hindi hits"), so
  /// the user's order and hidden set apply whatever the language.
  final String id;
  final String title;
  final HomeSectionStyle style;

  /// For [HomeSectionStyle.rows].
  final String query;

  /// For [HomeSectionStyle.cards].
  final List<HomeCard> cards;

  /// Added by the user (can be deleted, not just hidden).
  final bool custom;

  const HomeSection.rows(this.id, this.title, this.query, {this.custom = false})
    : style = HomeSectionStyle.rows,
      cards = const [];

  const HomeSection.cards(this.id, this.title, this.cards)
    : style = HomeSectionStyle.cards,
      query = '',
      custom = false;

  const HomeSection.recent()
    : id = 'recent',
      title = 'Recently played',
      style = HomeSectionStyle.recent,
      query = '',
      cards = const [],
      custom = false;
}

/// The user's home page: section order, hidden sections, and sections they
/// added. Stored as JSON in settings.
class HomeLayout {
  final List<String> order;
  final Set<String> hidden;

  /// Added rows, as (id, title). Each is the best-matching JioSaavn playlist
  /// for its title (falling back to a song search).
  final List<(String, String)> custom;

  const HomeLayout({
    this.order = const [],
    this.hidden = const {},
    this.custom = const [],
  });

  static const HomeLayout standard = HomeLayout();

  List<HomeSection> get customSections => [
    for (final (id, title) in custom)
      HomeSection.rows(id, title, 'playlist:$title', custom: true),
  ];

  HomeLayout copyWith({
    List<String>? order,
    Set<String>? hidden,
    List<(String, String)>? custom,
  }) => HomeLayout(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    custom: custom ?? this.custom,
  );

  Map<String, dynamic> toJson() => {
    'order': order,
    'hidden': hidden.toList(),
    'custom': [
      for (final (id, title) in custom) {'id': id, 'title': title},
    ],
  };

  /// Never throws: a damaged setting falls back to the standard page.
  factory HomeLayout.fromJson(Object? json) {
    if (json is! Map) return standard;
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    final custom = <(String, String)>[];
    final raw = json['custom'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map && e['id'] is String && e['title'] is String) {
          custom.add((e['id'] as String, e['title'] as String));
        }
      }
    }
    return HomeLayout(
      order: strings(json['order']),
      hidden: strings(json['hidden']).toSet(),
      custom: custom,
    );
  }
}

/// Every section the home page can show for [language] — recently played,
/// the built-in catalogue, and the user's own — in the user's order.
/// Sections the user hasn't placed (new ones, or another language's extras)
/// keep their standard position after the placed ones. Hidden sections are
/// left out unless [includeHidden] (the Customize screen lists them too).
List<HomeSection> arrangeHome(
  String? language,
  HomeLayout layout, {
  bool includeHidden = false,
  List<HomeSection> personal = const [],
}) {
  final all = [
    const HomeSection.recent(),
    ...personal,
    ...homeSectionsFor(language),
    ...layout.customSections,
  ];
  final byId = {for (final s in all) s.id: s};
  final placed = [
    for (final id in layout.order)
      if (byId.containsKey(id)) byId[id]!,
  ];
  final placedIds = placed.map((s) => s.id).toSet();
  final arranged = [...placed, ...all.where((s) => !placedIds.contains(s.id))];
  return includeHidden
      ? arranged
      : arranged.where((s) => !layout.hidden.contains(s.id)).toList();
}

/// Artist and era rows that only make sense for one language.
const Map<String, List<HomeSection>> _languageExtras = {
  'Tamil': [
    HomeSection.rows(
      'anirudh',
      'Anirudh',
      'playlist:Anirudh Ravichander Tamil',
    ),
    HomeSection.rows(
      'ilaiyaraaja',
      'Ilaiyaraaja classics',
      'playlist:Ilaiyaraaja 90s Hits',
    ),
    HomeSection.rows(
      'kollywood_dance',
      'Kollywood dance',
      'playlist:Kuthu Tamil',
    ),
  ],
  'Telugu': [
    HomeSection.rows(
      'tollywood_dance',
      'Tollywood dance',
      'playlist:Dance Telugu',
    ),
  ],
  'Hindi': [
    HomeSection.rows('arijit', 'Arijit Singh', 'playlist:Arijit Singh'),
    HomeSection.rows(
      'bollywood_dance',
      'Bollywood dance',
      'playlist:Dance Hindi',
    ),
  ],
};

/// The home page for [language], or the language-neutral page when it is
/// null.
///
/// Each query is a JioSaavn listing (see `YoutubeService.catalog`):
/// `trending:<language>`, `playlist:<name>` — JioSaavn's editorial
/// playlists, measured 20–50 songs each and all in the right language for
/// Tamil/Hindi/Telugu/Malayalam — or a plain song search.
List<HomeSection> homeSectionsFor(String? language) {
  if (language == null) {
    return const [
      HomeSection.rows('trending', 'Trending now', 'trending:'),
      HomeSection.rows('hits', 'Global hits', 'playlist:Hits English'),
      HomeSection.rows('chill', 'Chill', 'playlist:Chill English'),
      HomeSection.rows('workout', 'Workout', 'playlist:Workout English'),
      HomeSection.cards('top_playlists', 'Top playlists', [
        HomeCard('Top 50', 'playlist:Top 50 English'),
        HomeCard('Party', 'playlist:Party English'),
        HomeCard('Romance', 'playlist:Romantic English'),
        HomeCard('Lo-fi', 'playlist:Lofi'),
        HomeCard('Road trip', 'playlist:Road Trip English'),
      ]),
    ];
  }

  final l = language;
  return [
    HomeSection.rows(
      'trending',
      'Trending in $l',
      'trending:${l.toLowerCase()}',
    ),
    HomeSection.rows('hits', '$l hits', 'playlist:Hits $l'),
    HomeSection.rows('latest', 'Latest $l', 'playlist:Latest $l'),
    HomeSection.rows('melodies', '$l melodies', 'playlist:Melody $l'),
    HomeSection.rows('love', '$l love songs', 'playlist:Love $l'),
    ...?_languageExtras[l],
    HomeSection.rows('nineties', '90s $l', 'playlist:1990s $l'),
    HomeSection.cards('trending_playlists', 'Trending playlists', [
      HomeCard('$l Top 50', 'playlist:Top 50 $l'),
      HomeCard('$l viral hits', 'playlist:Viral $l'),
      HomeCard('New $l releases', 'playlist:New Releases $l'),
      HomeCard('$l party', 'playlist:Party $l'),
    ]),
    HomeSection.cards('top_playlists', 'Top playlists', [
      HomeCard('$l romance', 'playlist:Romantic $l'),
      HomeCard('$l chill', 'playlist:Chill $l'),
      HomeCard('$l workout', 'playlist:Workout $l'),
      HomeCard('$l road trip', 'playlist:Road Trip $l'),
      HomeCard('$l devotional', 'playlist:Devotional $l'),
      HomeCard('$l sad songs', 'playlist:Sad $l'),
    ]),
  ];
}

/// "Good morning" / "Good afternoon" / "Good evening" for [hour] (0–23).
String greetingFor(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// Home rows are for songs: drop hour-long jukeboxes and mixes, which search
/// happily returns for queries like "90s hits".
bool isSongLength(Duration? duration) =>
    duration == null || duration <= const Duration(minutes: 12);

/// "Made for you": rows built from what the user plays most — a mix for
/// each of their top two artists, and songs like the one they played last.
/// Slot ids are fixed ("foryou_*"), so the user's arrangement sticks while
/// the artists change.
List<HomeSection> madeForYou(
  List<({AppMediaItem item, int plays, int playedAt})> history,
) {
  if (history.isEmpty) return const [];
  final stats = ListeningStats.from(history, top: 2);
  final lastOnline = history
      .where((e) => e.item.sourceType == MediaSourceType.saavn)
      .firstOrNull
      ?.item;
  return [
    if (lastOnline != null)
      HomeSection.rows(
        'foryou_radio',
        'Because you played ${lastOnline.title}',
        'radio:${lastOnline.id}',
      ),
    for (final (i, (artist, _)) in stats.topArtists.indexed)
      HomeSection.rows('foryou_artist$i', '$artist mix', 'playlist:$artist'),
  ];
}
