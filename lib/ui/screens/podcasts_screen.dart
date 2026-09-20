import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../services/podcast_service.dart';
import '../../models/podcast_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';

class PodcastsScreen extends StatefulWidget {
  const PodcastsScreen({super.key});

  @override
  State<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends State<PodcastsScreen> {
  final PodcastService _podcastService = PodcastService();
  final TextEditingController _searchController = TextEditingController();

  List<PodcastChannel> _channels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTopPodcasts();
  }

  Future<void> _loadTopPodcasts() async {
    setState(() => _isLoading = true);
    final results = await _podcastService.getTopPodcasts();
    if (mounted) {
      setState(() {
        _channels = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchPodcasts(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final results = await _podcastService.searchPodcasts(query);
    if (mounted) {
      setState(() {
        _channels = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Podcasts',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search podcasts & RSS shows...',
                  hintStyle: TextStyle(color: Colors.white38),
                  prefixIcon: Icon(Icons.podcasts, color: Colors.orangeAccent),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: _searchPodcasts,
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(
                    child: SpinKitDoubleBounce(
                      color: Colors.orangeAccent,
                      size: 50.0,
                    ),
                  )
                : _channels.isEmpty
                    ? const Center(
                        child: Text(
                          'No podcasts found.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: _channels.length,
                        itemBuilder: (context, index) {
                          final channel = _channels[index];
                          return _buildPodcastCard(channel);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildPodcastCard(PodcastChannel channel) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      onTap: () => _openPodcastDetails(channel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: channel.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: channel.artworkUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.white10),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.white10,
                        child: const Icon(Icons.podcasts, color: Colors.orangeAccent, size: 50),
                      ),
                    )
                  : Container(
                      color: Colors.white10,
                      child: const Icon(Icons.podcasts, color: Colors.orangeAccent, size: 50),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  channel.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPodcastDetails(PodcastChannel channel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return _PodcastEpisodesSheet(
            channel: channel,
            podcastService: _podcastService,
            scrollController: scrollController,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class _PodcastEpisodesSheet extends StatefulWidget {
  final PodcastChannel channel;
  final PodcastService podcastService;
  final ScrollController scrollController;

  const _PodcastEpisodesSheet({
    required this.channel,
    required this.podcastService,
    required this.scrollController,
  });

  @override
  State<_PodcastEpisodesSheet> createState() => _PodcastEpisodesSheetState();
}

class _PodcastEpisodesSheetState extends State<_PodcastEpisodesSheet> {
  List<PodcastEpisode> _episodes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    final episodes = await widget.podcastService.fetchEpisodes(widget.channel.feedUrl);
    if (mounted) {
      setState(() {
        _episodes = episodes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(context, listen: false);

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.channel.artworkUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.channel.artworkUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        color: Colors.white10,
                        child: const Icon(Icons.podcasts, color: Colors.orangeAccent),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.channel.title,
                      maxLines: 1,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      widget.channel.author,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(color: Colors.white10),

        Expanded(
          child: _isLoading
              ? const Center(
                  child: SpinKitDoubleBounce(color: Colors.orangeAccent, size: 40),
                )
              : _episodes.isEmpty
                  ? const Center(
                      child: Text(
                        'No episodes found.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final episode = _episodes[index];
                        return ListTile(
                          title: Text(
                            episode.title,
                            maxLines: 2,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          subtitle: Text(
                            episode.pubDate ?? 'Podcast Episode',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                          trailing: const Icon(Icons.play_circle_fill, color: Colors.orangeAccent, size: 36),
                          onTap: () {
                            final mediaItem = widget.podcastService.episodeToMediaItem(
                              episode,
                              widget.channel,
                            );
                            playerProvider.playTrack(mediaItem);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
