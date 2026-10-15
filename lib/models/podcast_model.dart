class PodcastChannel {
  final String id;
  final String title;
  final String author;
  final String description;
  final String artworkUrl;
  final String feedUrl;
  final List<PodcastEpisode> episodes;

  PodcastChannel({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.artworkUrl,
    required this.feedUrl,
    this.episodes = const [],
  });

  factory PodcastChannel.fromiTunesJson(Map<String, dynamic> json) {
    return PodcastChannel(
      id: json['collectionId']?.toString() ?? '',
      title: json['collectionName'] ?? json['trackName'] ?? 'Unknown Podcast',
      author: json['artistName'] ?? 'Unknown Creator',
      description: json['primaryGenreName'] ?? 'Podcast',
      artworkUrl: json['artworkUrl600'] ?? json['artworkUrl100'] ?? '',
      feedUrl: json['feedUrl'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'artworkUrl': artworkUrl,
    'feedUrl': feedUrl,
  };

  factory PodcastChannel.fromJson(Map<String, dynamic> json) => PodcastChannel(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? 'Unknown Podcast',
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    artworkUrl: json['artworkUrl'] as String? ?? '',
    feedUrl: json['feedUrl'] as String? ?? '',
  );
}

class PodcastEpisode {
  final String id;
  final String title;
  final String description;
  final String audioUrl;
  final String? pubDate;
  final Duration? duration;
  final String? artworkUrl;

  PodcastEpisode({
    required this.id,
    required this.title,
    required this.description,
    required this.audioUrl,
    this.pubDate,
    this.duration,
    this.artworkUrl,
  });
}
