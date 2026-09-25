import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

/// Settings > Listening stats: totals, most played songs and artists.
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final stats = context.read<MusicPlayerProvider>().stats;
    final hours = stats.time.inMinutes / 60;
    final muted = TextStyle(color: context.colors.mist.withValues(alpha: 0.6));
    return Scaffold(
      appBar: AppBar(title: const Text('Listening stats')),
      body: stats.plays == 0
          ? Center(
              child: Text('Play some songs to see your stats.', style: muted),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _Total('${stats.plays}', 'plays'),
                      _Total(
                        hours >= 1
                            ? hours.toStringAsFixed(1)
                            : '${stats.time.inMinutes}',
                        hours >= 1 ? 'hours' : 'minutes',
                      ),
                    ],
                  ),
                ),
                const _Heading('Top artists'),
                for (final (i, (artist, plays)) in stats.topArtists.indexed)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(artist),
                    trailing: Text('$plays plays', style: muted),
                  ),
                const _Heading('Most played'),
                for (final (song, _) in stats.topSongs)
                  TrackTile(
                    item: song,
                    playlist: [for (final (s, _) in stats.topSongs) s],
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'From your last 200 songs. Time assumes each play ran '
                    'to the end.',
                    style: muted.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Total extends StatelessWidget {
  final String value;
  final String label;
  const _Total(this.value, this.label);

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: context.colors.accent,
          ),
        ),
        Text(label),
      ],
    ),
  );
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
