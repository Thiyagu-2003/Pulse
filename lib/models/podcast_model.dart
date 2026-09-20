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
