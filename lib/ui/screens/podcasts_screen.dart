import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../services/podcast_service.dart';
import '../../services/storage_service.dart';
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

  final StorageService _storage = StorageService();

  List<PodcastChannel> _channels = [];
  late List<PodcastChannel> _pinned = _storage.getPodcastHome();
  // Search results replace the home (pinned + top shows) until cleared.
  bool _searching = false;
  bool _isLoading = true;
  // Bumped per request; a slower earlier response must not overwrite a newer one.
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadTopPodcasts();
  }

  Future<void> _loadTopPodcasts() async {
    setState(() {
      _isLoading = true;
      _searching = false;
    });
    final request = ++_request;
    final results = await _podcastService.getTopPodcasts();
    if (mounted && request == _request) {
      setState(() {
        _channels = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchPodcasts(String query) async {
    if (query.trim().isEmpty) return _loadTopPodcasts();
    setState(() {
      _isLoading = true;
      _searching = true;
    });
    final request = ++_request;
    final results = await _podcastService.searchPodcasts(query);
    if (mounted && request == _request) {
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
        title: Text(
          'Podcasts',
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.mist.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: context.colors.mist.withValues(alpha: 0.10),
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: context.colors.mist),
                decoration: InputDecoration(
                  hintText: 'Search podcasts & RSS shows...',
                  hintStyle: TextStyle(
                    color: context.colors.mist.withValues(alpha: 0.38),
                  ),
                  prefixIcon: Icon(
                    Icons.podcasts,
                    color: podcastOrange(context),
                  ),
                  suffixIcon: _searching
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            _loadTopPodcasts();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onSubmitted: _searchPodcasts,
              ),
            ),
          ),

          Expanded(
            child: _isLoading
                ? Center(
                    child: SpinKitDoubleBounce(
                      color: podcastOrange(context),
                      size: 50.0,
                    ),
                  )
                : _channels.isEmpty && (_searching || _pinned.isEmpty)
                ? Center(
                    child: Text(
                      'No podcasts found.',
                      style: TextStyle(
                        color: context.colors.mist.withValues(alpha: 0.54),
                      ),
                    ),
                  )
                : CustomScrollView(
                    slivers: [
                      if (!_searching && _pinned.isNotEmpty) ...[
                        _sectionTitle('Your shows'),
                        _grid(_pinned),
                        _sectionTitle('Top shows'),
                      ],
                      _grid(_channels),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    sliver: SliverToBoxAdapter(
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    ),
  );

  Widget _grid(List<PodcastChannel> channels) => SliverPadding(
    padding: const EdgeInsets.all(16),
    sliver: SliverGrid.builder(
      // Cards up to ~220px: two across on a phone, as many as fit on a
      // wide (desktop) window rather than two giant ones.
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.75,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) => _buildPodcastCard(channels[index]),
    ),
  );

  bool _isPinned(PodcastChannel c) =>
      _pinned.any((p) => p.id == c.id);

  void _showPodcastMenu(PodcastChannel channel) {
    final pinned = _isPinned(channel);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                channel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(channel.author, maxLines: 1),
            ),
            ListTile(
              leading: Icon(
                pinned ? Icons.remove_circle_outline : Icons.add_home_outlined,
              ),
              title: Text(
                pinned ? 'Remove from Podcasts home' : 'Add to Podcasts home',
              ),
              onTap: () {
                Navigator.pop(sheet);
                setState(() {
                  _pinned = pinned
                      ? _pinned
                            .where((p) => p.id != channel.id)
                            .toList()
                      : [channel, ..._pinned];
                });
                _storage.setPodcastHome(_pinned);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      pinned
                          ? 'Removed from Podcasts home'
                          : 'Added "${channel.title}" to Podcasts home',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Show episodes'),
              onTap: () {
                Navigator.pop(sheet);
                _openPodcastDetails(channel);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPodcastCard(PodcastChannel channel) {
    return GestureDetector(
      onLongPress: () => _showPodcastMenu(channel),
      onSecondaryTap: () => _showPodcastMenu(channel),
      child: _podcastCard(channel),
    );
  }

  Widget _podcastCard(PodcastChannel channel) {
    return GlassContainer(
      padding: EdgeInsets.zero,
      onTap: () => _openPodcastDetails(channel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: channel.artworkUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: channel.artworkUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: context.colors.mist.withValues(alpha: 0.10),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: context.colors.mist.withValues(alpha: 0.10),
                        child: Icon(
                          Icons.podcasts,
                          color: podcastOrange(context),
                          size: 50,
                        ),
                      ),
                    )
                  : Container(
                      color: context.colors.mist.withValues(alpha: 0.10),
                      child: Icon(
                        Icons.podcasts,
                        color: podcastOrange(context),
                        size: 50,
                      ),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  channel.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.mist.withValues(alpha: 0.60),
                  ),
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
      backgroundColor: context.colors.surface,
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
    final episodes = await widget.podcastService.fetchEpisodes(
      widget.channel.feedUrl,
    );
    if (mounted) {
      setState(() {
        _episodes = episodes;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerProvider = Provider.of<MusicPlayerProvider>(
      context,
      listen: false,
    );

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
                        color: context.colors.mist.withValues(alpha: 0.10),
                        child: Icon(
                          Icons.podcasts,
                          color: podcastOrange(context),
                        ),
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      widget.channel.author,
                      maxLines: 1,
                      style: TextStyle(
                        color: context.colors.mist.withValues(alpha: 0.60),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Divider(color: context.colors.mist.withValues(alpha: 0.10)),

        Expanded(
          child: _isLoading
              ? Center(
                  child: SpinKitDoubleBounce(
                    color: podcastOrange(context),
                    size: 40,
                  ),
                )
              : _episodes.isEmpty
              ? Center(
                  child: Text(
                    'No episodes found.',
                    style: TextStyle(
                      color: context.colors.mist.withValues(alpha: 0.54),
                    ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        episode.pubDate ?? 'Podcast Episode',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.mist.withValues(alpha: 0.54),
                        ),
                      ),
                      trailing: Icon(
                        Icons.play_circle_fill,
                        color: podcastOrange(context),
                        size: 36,
                      ),
                      onTap: () {
                        final mediaItem = widget.podcastService
                            .episodeToMediaItem(episode, widget.channel);
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

/// Podcast orange: the bright accent is too faint on light backgrounds
/// (~1.9:1), so a darker shade there.
Color podcastOrange(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? Colors.orange.shade800
    : Colors.orangeAccent;
