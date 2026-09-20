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

  List<AppMediaItem> _results = [];
  bool _isLoading = false;
  String _activeQuery = 'Trending Music';

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _isLoading = true;
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
        title: const Text(
          'Online Music',
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
                decoration: InputDecoration(
                  hintText: 'Search songs, artists, videos...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.accent),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            _loadTrending();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
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
                _buildGenreChip('Trending'),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
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
        selectedColor: AppTheme.primary,
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        onSelected: (_) => _performSearch(label),
      ),
    );
  }

  @override
  void dispose() {
    _ytService.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
