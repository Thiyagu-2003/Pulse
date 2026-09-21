import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../../services/youtube_service.dart';
import '../../models/media_item_model.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

class OnlineMusicScreen extends StatefulWidget {
  const OnlineMusicScreen({super.key});

  @override
  State<OnlineMusicScreen> createState() => _OnlineMusicScreenState();
}

class _OnlineMusicScreenState extends State<OnlineMusicScreen> {
  final YoutubeService _ytService = YoutubeService();
  final TextEditingController _searchController = TextEditingController();

  static const String _trendingLabel = 'Trending';

  List<AppMediaItem> _results = [];
  bool _isLoading = false;
  String _activeQuery = _trendingLabel;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoading = true;
      _activeQuery = _trendingLabel;
    });
    final items = await _ytService.getTrendingMusic();
    if (mounted) {
      setState(() {
        _results = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isLoading = true;
      _activeQuery = query;
    });
    final items = await _ytService.searchMusic(query);
    if (mounted) {
      setState(() {
        _results = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Online Music',
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
                color: AppTheme.lift,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.mist.withValues(alpha: 0.07),
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppTheme.mist),
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, videos',
                  hintStyle: TextStyle(
                    color: AppTheme.mist.withValues(alpha: 0.35),
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppTheme.mist.withValues(alpha: 0.45),
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear_rounded,
                            color: AppTheme.mist.withValues(alpha: 0.45),
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _loadTrending();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                // Without this the clear button never appears/disappears,
                // since nothing else rebuilds as the field is typed into.
                onChanged: (_) => setState(() {}),
                onSubmitted: _performSearch,
              ),
            ),
          ),

          // Genre Pill Tags
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildGenreChip(_trendingLabel),
                _buildGenreChip('Pop Music'),
                _buildGenreChip('Hip Hop'),
                _buildGenreChip('Lo-Fi Chill'),
                _buildGenreChip('Rock & Metal'),
                _buildGenreChip('EDM Beats'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Search Header Label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _activeQuery,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),

          // Track Results List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: SpinKitDoubleBounce(
                      color: AppTheme.primary,
                      size: 50.0,
                    ),
                  )
                : _results.isEmpty
                    ? const Center(
                        child: Text(
                          'No results found. Try a different search.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final item = _results[index];
                          return TrackTile(
                            item: item,
                            playlist: _results,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenreChip(String label) {
    final isSelected = _activeQuery == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        showCheckmark: false,
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.lift,
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : AppTheme.mist.withValues(alpha: 0.07),
        ),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontSize: 13,
          color: isSelected ? AppTheme.mist : AppTheme.mist.withValues(alpha: 0.6),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
        // "Trending" has its own curated query — searching for the literal
        // word returns unrelated videos.
        onSelected: (_) =>
            label == _trendingLabel ? _loadTrending() : _performSearch(label),
      ),
    );
  }

  @override
  void dispose() {
    // YoutubeService is shared with the audio handler — disposing it here
    // would kill stream extraction for the rest of the app.
    _searchController.dispose();
    super.dispose();
  }
}
