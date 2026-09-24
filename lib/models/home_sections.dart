// What the Online home page shows, as plain data so it can be unit tested.
//
// Every section is a YouTube search: there is no catalogue API behind Pulse,
// so "Tamil hits" is simply the query that reliably returns Tamil hits.

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
}

class HomeCard {
  final String title;
  final String query;
  const HomeCard(this.title, this.query);
}

class HomeSection {
  final String title;
  final HomeSectionStyle style;

  /// For [HomeSectionStyle.rows].
  final String query;

  /// For [HomeSectionStyle.cards].
  final List<HomeCard> cards;

  const HomeSection.rows(this.title, this.query)
      : style = HomeSectionStyle.rows,
        cards = const [];

  const HomeSection.cards(this.title, this.cards)
      : style = HomeSectionStyle.cards,
        query = '';
}

/// Artist and era rows that only make sense for one language.
const Map<String, List<HomeSection>> _languageExtras = {
  'Tamil': [
    HomeSection.rows('Anirudh', 'Anirudh Ravichander hit songs'),
    HomeSection.rows('Ilaiyaraaja classics', 'Ilaiyaraaja classic hit songs'),
    HomeSection.rows('Kollywood dance', 'Tamil kuthu dance songs'),
  ],
  'Telugu': [
    HomeSection.rows('Tollywood dance', 'Telugu mass dance songs'),
  ],
  'Hindi': [
    HomeSection.rows('Arijit Singh', 'Arijit Singh hit songs'),
    HomeSection.rows('Bollywood dance', 'Bollywood dance songs'),
  ],
  'Malayalam': [
    HomeSection.rows('Mollywood hits', 'Malayalam movie hit songs'),
  ],
};

/// The home page for [language], or the language-neutral page when it is
/// null.
List<HomeSection> homeSectionsFor(String? language) {
  if (language == null) {
    return const [
      HomeSection.rows('Trending now', 'trending songs this week official audio'),
      HomeSection.rows('Global hits', 'top global hit songs official audio'),
      HomeSection.rows('Chill', 'chill songs official audio'),
      HomeSection.rows('Workout', 'workout songs official audio'),
      HomeSection.cards('Top playlists', [
        HomeCard('Top 50', 'top 50 songs official audio'),
        HomeCard('Party', 'party songs official audio'),
        HomeCard('Romance', 'romantic songs official audio'),
        HomeCard('Lo-fi', 'lofi songs'),
        HomeCard('Road trip', 'road trip songs official audio'),
      ]),
    ];
  }

  final l = language;
  return [
    HomeSection.rows('Trending in $l', '$l trending songs this week'),
    HomeSection.rows('$l hits', '$l hit songs'),
    HomeSection.rows('Latest $l', 'latest $l songs'),
    HomeSection.rows('$l melodies', '$l melody songs'),
    HomeSection.rows('$l love songs', '$l love songs'),
    ...?_languageExtras[l],
    HomeSection.rows('90s $l', '90s $l hit songs'),
    HomeSection.cards('Trending now', [
      HomeCard('$l Top 50', 'top 50 $l songs'),
      HomeCard('$l viral hits', 'viral $l songs'),
      HomeCard('New $l releases', 'new $l songs'),
      HomeCard('$l party', '$l party songs'),
    ]),
    HomeSection.cards('Top playlists', [
      HomeCard('$l romance', '$l romantic songs'),
      HomeCard('$l chill', '$l chill songs'),
      HomeCard('$l workout', '$l workout songs'),
      HomeCard('$l road trip', '$l road trip songs'),
      HomeCard('$l devotional', '$l devotional songs'),
      HomeCard('$l sad songs', '$l sad songs'),
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
