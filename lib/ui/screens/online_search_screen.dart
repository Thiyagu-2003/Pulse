import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

/// Online search: recent searches until something is submitted, then results.
class OnlineSearchScreen extends StatefulWidget {
  const OnlineSearchScreen({super.key});

  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  final _controller = TextEditingController();

  /// Null while showing recent searches.
  String? _query;
  List<AppMediaItem> _results = [];
  bool _isLoading = false;
  // Bumped per request; a slower earlier response must not overwrite a newer one.
  int _request = 0;

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _controller.text = query;
    FocusScope.of(context).unfocus();
    context.read<MusicPlayerProvider>().addRecentSearch(query);

    setState(() {
      _query = query;
      _isLoading = true;
    });
    final request = ++_request;
    final results = await YoutubeService().searchMusic(query);
    if (mounted && request == _request) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  void _clear() {
    _controller.clear();
    _request++; // drop any search still in flight
    setState(() {
      _query = null;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: context.colors.mist),
            decoration: InputDecoration(
              hintText: 'Songs, artists, albums...',
              hintStyle: TextStyle(color: context.colors.mist.withValues(alpha: 0.4)),
              filled: true,
              fillColor: context.colors.lift,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: _clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            // Shows/hides the clear button as the field is typed into.
            onChanged: (_) => setState(() {}),
            onSubmitted: _search,
          ),
        ),
      ),
      // Pushed over the tabs, so it needs its own mini player.
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: _query == null ? _buildRecent() : _buildResults(),
    );
  }

  Widget _buildRecent() {
    final recent =
        context.select<MusicPlayerProvider, List<String>>((p) => p.recentSearches);
    if (recent.isEmpty) {
      return Center(
        child: Text(
          'Search for any song or artist',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.5)),
        ),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () =>
                    context.read<MusicPlayerProvider>().clearRecentSearches(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        for (final query in recent)
          ListTile(
            leading: Icon(
              Icons.history_rounded,
              color: context.colors.mist.withValues(alpha: 0.6),
            ),
            title: Text(query),
            onTap: () => _search(query),
          ),
      ],
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(
        child: SpinKitDoubleBounce(color: AppTheme.primary, size: 50),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results found. Try a different search.',
          style: TextStyle(color: context.colors.mist.withValues(alpha: 0.54)),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) =>
          TrackTile(item: _results[index], playlist: _results),
    );
  }
}
