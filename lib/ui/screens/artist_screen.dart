import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';

import '../../providers/music_player_provider.dart';
import '../../services/saavn_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mini_player.dart';
import '../widgets/track_tile.dart';
import 'track_list_screen.dart';

/// Open an album, playlist or artist from a search result or song menu.
void openCollection(BuildContext context, SaavnCollection c) {
  final saavn = SaavnService.instance;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => switch (c.kind) {
        SaavnKind.artist => ArtistScreen(artistId: c.id, name: c.title),
        SaavnKind.album => TrackListScreen(
          title: c.title,
          load: () async => (await saavn.album(c.id))?.songs ?? const [],
        ),
        SaavnKind.playlist => TrackListScreen(
          title: c.title,
          load: () => saavn.playlist(c.id),
        ),
      },
    ),
  );
}

/// One album/playlist/artist row: artwork (round for artists), title, subtitle.
class CollectionTile extends StatelessWidget {
  final SaavnCollection collection;
  const CollectionTile({super.key, required this.collection});

  @override
  Widget build(BuildContext context) {
    final c = collection;
    final round = c.kind == SaavnKind.artist;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(round ? 25 : 8),
        child: c.image.startsWith('http')
            ? CachedNetworkImage(
                imageUrl: c.image,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _placeholder(context, c.kind),
              )
            : _placeholder(context, c.kind),
      ),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: c.subtitle.isEmpty
          ? null
          : Text(
              c.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.mist.withValues(alpha: 0.6),
              ),
            ),
      onTap: () => openCollection(context, c),
    );
  }

  static Widget _placeholder(BuildContext context, SaavnKind kind) => Container(
    width: 50,
    height: 50,
    color: context.colors.mist.withValues(alpha: 0.1),
    child: Icon(switch (kind) {
      SaavnKind.artist => Icons.person_rounded,
      SaavnKind.album => Icons.album_rounded,
      SaavnKind.playlist => Icons.queue_music_rounded,
    }, color: AppTheme.primary),
  );
}

/// An artist's top songs and albums.
class ArtistScreen extends StatefulWidget {
  final String artistId;
  final String name;
  const ArtistScreen({super.key, required this.artistId, required this.name});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<SaavnArtist?> _artist = _fetch();

  Future<SaavnArtist?> _fetch() => SaavnService.instance
      .artist(widget.artistId)
      .catchError((Object _) => null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
      body: FutureBuilder<SaavnArtist?>(
        future: _artist,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SpinKitDoubleBounce(color: AppTheme.primary, size: 50),
            );
          }
          final artist = snapshot.data;
          if (artist == null) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _artist = _fetch()),
                child: const Text("Couldn't load this artist. Tap to retry."),
              ),
            );
          }
          final songs = artist.topSongs;
          return ListView(
            children: [
              const SizedBox(height: 8),
              if (artist.image.startsWith('http'))
                Center(
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: artist.image,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    if (songs.isNotEmpty)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Play'),
                        onPressed: () => context
                            .read<MusicPlayerProvider>()
                            .playTrack(songs.first, playlist: songs),
                      ),
                    const Spacer(),
                    if (songs.isNotEmpty) DownloadAllButton(items: songs),
                  ],
                ),
              ),
              if (songs.isNotEmpty) const _Heading('Top songs'),
              for (final song in songs) TrackTile(item: song, playlist: songs),
              if (artist.albums.isNotEmpty) const _Heading('Albums'),
              for (final album in artist.albums)
                CollectionTile(collection: album),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
