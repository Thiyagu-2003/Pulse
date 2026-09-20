import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';
import '../../services/local_music_service.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

class LocalSongsScreen extends StatefulWidget {
  const LocalSongsScreen({super.key});

  @override
  State<LocalSongsScreen> createState() => _LocalSongsScreenState();
}

class _LocalSongsScreenState extends State<LocalSongsScreen> {
  final LocalMusicService _localService = LocalMusicService();
  List<AppMediaItem> _localSongs = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _initLocalMusic();
  }

  Future<void> _initLocalMusic() async {
    final granted = await _localService.requestPermission();
    if (granted) {
      final songs = await _localService.fetchLocalSongs();
      if (mounted) {
        setState(() {
          _localSongs = songs;
          _hasPermission = true;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Local Songs',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.accent),
            onPressed: () {
              setState(() => _isLoading = true);
              _initLocalMusic();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SpinKitDoubleBounce(
                color: AppTheme.accent,
                size: 50.0,
              ),
            )
          : !_hasPermission
              ? _buildPermissionDeniedView()
              : _localSongs.isEmpty
                  ? _buildEmptyView()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_localSongs.length} Songs found',
                                style: const TextStyle(color: Colors.white60),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.play_arrow, color: Colors.white),
                                label: const Text('Play All', style: TextStyle(color: Colors.white)),
                                onPressed: () {
                                  // Actually play the first song with the full local queue
                                  if (_localSongs.isNotEmpty) {
                                    final playerProvider = Provider.of<MusicPlayerProvider>(
                                      context,
                                      listen: false,
                                    );
                                    playerProvider.playTrack(
                                      _localSongs.first,
                                      playlist: _localSongs,
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _localSongs.length,
                            itemBuilder: (context, index) {
                              return TrackTile(
                                item: _localSongs[index],
                                playlist: _localSongs,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            const Text(
              'Storage Permission Required',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant permission to scan your device for local MP3, FLAC, and audio files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: _initLocalMusic,
              child: const Text('Grant Access', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.library_music, size: 80, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'No Local Songs Found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Add music files to your device storage to play them offline.',
            style: TextStyle(color: Colors.white60),
          ),
        ],
      ),
    );
  }
}
