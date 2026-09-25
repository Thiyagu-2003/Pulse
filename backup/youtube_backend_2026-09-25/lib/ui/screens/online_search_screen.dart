import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import '../../models/home_sections.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';

/// Online search. Empty box: recent searches. While typing: YouTube's own
/// query suggestions and the top matching songs, like YouTube Music.
/// Submitted: full results.
class OnlineSearchScreen extends StatefulWidget {
  const OnlineSearchScreen({super.key});

  @override
  State<OnlineSearchScreen> createState() => _OnlineSearchScreenState();
}

class _OnlineSearchScreenState extends State<OnlineSearchScreen> {
  final _controller = TextEditingController();

  /// The submitted search; null while showing recent searches/suggestions.
  String? _query;

  /// What's in the box right now, trimmed.
  String _typed = '';
  List<String> _suggestions = [];
  List<AppMediaItem> _songPreview = [];
  Timer? _suggestTimer;
  Timer? _songsTimer;
  // Like [_request], for the suggestions typed ahead of any submit.
  int _suggestRequest = 0;
  List<AppMediaItem> _results = [];
  bool _isLoading = false;
  // Bumped per request; a slower earlier response must not overwrite a newer one.
  int _request = 0;

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _controller.text = query;
    _typed = query;
    _stopSuggesting();
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

  void _stopSuggesting() {
    _suggestTimer?.cancel();
    _songsTimer?.cancel();
    _suggestRequest++; // drop suggestions still in flight
  }

  /// Suggestions after a short pause in typing (not per keystroke), songs
  /// after a longer one, since a song search is the heavier request.
  void _onTyped(String text) {
    _stopSuggesting();
    final typed = text.trim();
    setState(() {
      _typed = typed;
      _query = null; // editing after a search goes back to suggestions
      _isLoading = false;
      if (typed.isEmpty) {
        _suggestions = [];
        _songPreview = [];
      }
    });
    _request++;
    if (typed.isEmpty) return;

    final request = _suggestRequest;
    final yt = YoutubeService();
    _suggestTimer = Timer(const Duration(milliseconds: 250), () async {
      final suggestions = await yt.searchSuggestions(typed);
      if (mounted && request == _suggestRequest) {
        setState(() => _suggestions = suggestions);
      }
    });
    if (typed.length < 3) {
      setState(() => _songPreview = []);
      return;
    }
    _songsTimer = Timer(const Duration(milliseconds: 700), () async {
      final songs = await yt
          .cachedSearch(typed)
          .catchError((Object _) => <AppMediaItem>[]);
      if (mounted && request == _suggestRequest) {
        setState(() => _songPreview =
            songs.where((t) => isSongLength(t.duration)).take(4).toList());
      }
    });
  }

  /// The ↖ button: put a suggestion in the box to keep refining it.
  void _refine(String suggestion) {
    _controller.value = TextEditingValue(
      text: '$suggestion ',
      selection: TextSelection.collapsed(offset: suggestion.length + 1),
    );
    _onTyped(suggestion);
  }

  void _clear() {
    _controller.clear();
    _onTyped('');
  }

  @override
  void dispose() {
    _stopSuggesting();
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
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: _clear,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: _onTyped,
            onSubmitted: _search,
          ),
        ),
      ),
      // Pushed over the tabs, so it needs its own mini player.
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: _query != null
          ? _buildResults()
          : _typed.isEmpty
              ? _buildRecent()
              : _buildSuggestions(),
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

  Widget _buildSuggestions() {
    final muted = context.colors.mist.withValues(alpha: 0.6);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        for (final suggestion in _suggestions)
          ListTile(
            leading: Icon(Icons.search_rounded, color: muted),
            title: _highlighted(suggestion),
            trailing: IconButton(
              tooltip: 'Edit this search',
              icon: Icon(Icons.north_west_rounded, color: muted, size: 20),
              onPressed: () => _refine(suggestion),
            ),
            onTap: () => _search(suggestion),
          ),
        if (_songPreview.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Songs',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          for (final song in _songPreview)
            TrackTile(item: song, playlist: _songPreview),
        ],
        // Always offer the literal text, even before suggestions arrive.
        ListTile(
          leading: Icon(Icons.search_rounded, color: context.colors.accent),
          title: Text('Search for "$_typed"'),
          onTap: () => _search(_typed),
        ),
      ],
    );
  }

  /// The part of a suggestion already typed stays plain; the completion is
  /// bold — how YouTube and Spotify draw it.
  Widget _highlighted(String suggestion) {
    final typed = _typed.toLowerCase();
    final base = TextStyle(color: context.colors.mist);
    if (!suggestion.toLowerCase().startsWith(typed)) {
      return Text(suggestion, style: base);
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: suggestion.substring(0, typed.length)),
          TextSpan(
            text: suggestion.substring(typed.length),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
