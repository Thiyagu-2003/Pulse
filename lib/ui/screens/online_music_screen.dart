import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/home_sections.dart';
import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../../services/network_status.dart';
import '../../services/youtube_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';
import 'customize_home_screen.dart';
import 'online_search_screen.dart';
import 'settings_screen.dart';
import 'track_list_screen.dart';

/// The Online tab: greeting, quick picks, language chips, then rows of songs
/// and playlist cards for the chosen language.
class OnlineMusicScreen extends StatefulWidget {
  /// Off in widget tests, which have no network to prefetch from.
  final bool prefetch;
  const OnlineMusicScreen({super.key, this.prefetch = true});

  @override
  State<OnlineMusicScreen> createState() => _OnlineMusicScreenState();
}

class _OnlineMusicScreenState extends State<OnlineMusicScreen> {
  /// Bumped by pull-to-refresh; part of the list key so every section
  /// rebuilds and searches again.
  int _refreshCount = 0;

  Future<void> _refresh() async {
    YoutubeService().clearSearchCache();
    setState(() => _refreshCount++);
    // Keep the spinner until the top section has actually reloaded.
    final language = context.read<MusicPlayerProvider>().homeLanguage;
    await YoutubeService()
        .cachedSearch(homeSectionsFor(language).first.query)
        .catchError((Object _) => <AppMediaItem>[]);
  }

  /// Which page (language + refresh) has had its top songs warmed.
  String? _prefetchedFor;

  /// Resolve stream URLs for the songs most likely to be tapped — the first
  /// quick picks and the first page of the top section — so they start
  /// almost instantly. One at a time: a burst of requests is what gets
  /// YouTube handing out dead URLs.
  Future<void> _prefetchTopSongs(String firstQuery) async {
    final yt = YoutubeService();
    final recent = context
        .read<MusicPlayerProvider>()
        .getHistory()
        .where((t) => t.sourceType == MediaSourceType.youtube)
        .take(4)
        .toList();
    final top = await yt
        .cachedSearch(firstQuery)
        .catchError((Object _) => <AppMediaItem>[]);
    for (final track in [
      ...recent,
      // JioSaavn songs carry their link already; only YouTube ones need it.
      ...top
          .where(
            (t) =>
                t.sourceType == MediaSourceType.youtube &&
                isSongLength(t.duration),
          )
          .take(4),
    ]) {
      if (!mounted) return;
      await yt.warmStreamUrlNow(track.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.select<MusicPlayerProvider, String?>(
      (p) => p.homeLanguage,
    );
    final layout = context.select<MusicPlayerProvider, String>(
      (p) => jsonEncode(p.homeLayout.toJson()),
    );
    final sections = homeSectionsFor(language);
    final arranged = arrangeHome(
      language,
      HomeLayout.fromJson(jsonDecode(layout)),
      personal: context.read<MusicPlayerProvider>().madeForYouSections,
    );
    final page = '$language/$_refreshCount';
    if (widget.prefetch && _prefetchedFor != page) {
      _prefetchedFor = page;
      _prefetchTopSongs(sections.first.query);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: NetworkStatus.instance.offline,
          // Nothing online can load: the downloads, which still play.
          // Back online, the rows are built afresh (failures aren't cached).
          builder: (context, offline, onlineHome) =>
              offline ? const _OfflineHome() : onlineHome!,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: context.colors.accent,
            child: ListView(
              key: ValueKey(page),
              // Room for the floating mini player.
              padding: const EdgeInsets.only(bottom: 110),
              children: [
                const _Header(),
                _LanguageChips(selected: language),
                // In the user's order (Settings > Customize home). Keyed by
                // id, so reordering moves each section's state with it.
                for (final section in arranged)
                  switch (section.style) {
                    HomeSectionStyle.recent => _QuickPicks(
                      key: ValueKey(section.id),
                      fallbackQuery: sections.first.query,
                    ),
                    HomeSectionStyle.rows => _RowsSection(
                      key: ValueKey(section.id),
                      section: section,
                    ),
                    HomeSectionStyle.cards => _CardsSection(
                      key: ValueKey(section.id),
                      section: section,
                    ),
                  },
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Customize home'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CustomizeHomeScreen(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Online tab with no connection: a notice, then the downloads.
class _OfflineHome extends StatelessWidget {
  const _OfflineHome();

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<MusicPlayerProvider>().getDownloads();
    final muted = context.colors.mist.withValues(alpha: 0.6);
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        const _Header(),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.lift,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: context.colors.accent),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "You're offline. Your downloaded songs still play.",
                ),
              ),
            ],
          ),
        ),
        if (downloads.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Nothing downloaded yet. Tap the download button on any song '
              'to keep it for offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          )
        else ...[
          const _SectionTitle('Downloads'),
          for (final song in downloads)
            TrackTile(item: song, playlist: downloads),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          // The app's own icon, in the style chosen in Settings.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              context.select<MusicPlayerProvider, bool>(
                    (p) => p.darkLauncherIcon,
                  )
                  ? 'icons/app_icon_dark.png'
                  : 'icons/app_icon_light.png',
              width: 40,
              height: 40,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              greetingFor(DateTime.now().hour),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded, size: 26),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OnlineSearchScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined, size: 26),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two columns of recently played tracks. Before anything has been played,
/// the top of the first section stands in so the page doesn't open empty.
class _QuickPicks extends StatelessWidget {
  final String fallbackQuery;
  const _QuickPicks({super.key, required this.fallbackQuery});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the playing track changes, which is when history grows.
    // ...and when history is cleared in Settings (the tab stays alive).
    context.select<MusicPlayerProvider, (String?, int)>(
      (p) => (p.currentTrack?.id, p.historyCount),
    );
    final history = context
        .read<MusicPlayerProvider>()
        .getHistory()
        .take(8)
        .toList();
    if (history.isNotEmpty) return _grid(history);

    return FutureBuilder<List<AppMediaItem>>(
      future: YoutubeService().cachedSearch(fallbackQuery),
      builder: (context, snapshot) {
        final items = (snapshot.data ?? const <AppMediaItem>[])
            .where((t) => isSongLength(t.duration))
            .take(8)
            .toList();
        return items.isEmpty ? const SizedBox(height: 8) : _grid(items);
      },
    );
  }

  Widget _grid(List<AppMediaItem> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: _QuickPickTile(item: items[i], playlist: items),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < items.length
                    ? _QuickPickTile(item: items[i + 1], playlist: items)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(children: rows),
    );
  }
}

class _QuickPickTile extends StatelessWidget {
  final AppMediaItem item;
  final List<AppMediaItem> playlist;
  const _QuickPickTile({required this.item, required this.playlist});

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<MusicPlayerProvider, bool>(
      (p) => p.currentTrack?.id == item.id,
    );
    return Material(
      color: context.colors.lift,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.read<MusicPlayerProvider>().playTrack(
          item,
          playlist: playlist,
        ),
        onLongPress: () => showTrackActions(context, item),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              _Artwork(url: item.artUri, size: 56, radius: 0),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isCurrent
                        ? context.colors.accent
                        : context.colors.mist,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Picking a chip is the same setting as "Home language" in Settings.
class _LanguageChips extends StatelessWidget {
  final String? selected;
  const _LanguageChips({required this.selected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: homeLanguages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final language = homeLanguages[index];
          final isSelected = language == selected;
          return ChoiceChip(
            label: Text(language),
            selected: isSelected,
            showCheckmark: false,
            selectedColor: AppTheme.primary,
            backgroundColor: context.colors.lift,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              // White on the violet pill in both themes.
              color: isSelected
                  ? Colors.white
                  : context.colors.mist.withValues(alpha: 0.8),
            ),
            onSelected: (_) {
              if (!isSelected) {
                context.read<MusicPlayerProvider>().setHomeLanguage(language);
              }
            },
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 24, trailing == null ? 16 : 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Pages of four track rows, swiped sideways, with the next page peeking in
/// from the right so it's obvious there is more.
class _RowsSection extends StatefulWidget {
  final HomeSection section;
  const _RowsSection({super.key, required this.section});

  @override
  State<_RowsSection> createState() => _RowsSectionState();
}

class _RowsSectionState extends State<_RowsSection> {
  static const _rowsPerPage = 4;

  final _pages = PageController(viewportFraction: 0.9);
  late Future<List<AppMediaItem>> _tracks = _load();

  Future<List<AppMediaItem>> _load() => YoutubeService()
      .cachedSearch(widget.section.query)
      .then((all) => all.where((t) => isSongLength(t.duration)).toList());

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Title + artist lines, scaled with the user's font size (Android goes
    // to 200%); a fixed 64 overflowed every row at large sizes.
    final scaler = MediaQuery.textScalerOf(context);
    final rowHeight = [
      64.0,
      16 + scaler.scale(15) * 1.45 + 3 + scaler.scale(13) * 1.45,
    ].reduce((a, b) => a > b ? a : b);
    return FutureBuilder<List<AppMediaItem>>(
      future: _tracks,
      builder: (context, snapshot) {
        final loaded = snapshot.data ?? const <AppMediaItem>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle(
              widget.section.title,
              trailing: loaded.isEmpty
                  ? null
                  : DownloadAllButton(items: loaded),
            ),
            Builder(
              builder: (context) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _RowsSkeleton(rows: _rowsPerPage, height: rowHeight);
                }
                final tracks = snapshot.data ?? const <AppMediaItem>[];
                if (tracks.isEmpty) {
                  return _LoadFailed(
                    onRetry: () => setState(() => _tracks = _load()),
                  );
                }
                final pageCount = (tracks.length / _rowsPerPage).ceil();
                return SizedBox(
                  height: _rowsPerPage * rowHeight,
                  child: PageView.builder(
                    controller: _pages,
                    padEnds: false,
                    itemCount: pageCount,
                    itemBuilder: (context, page) => Column(
                      children: [
                        for (final track
                            in tracks
                                .skip(page * _rowsPerPage)
                                .take(_rowsPerPage))
                          _TrackRow(
                            item: track,
                            playlist: tracks,
                            height: rowHeight,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TrackRow extends StatelessWidget {
  final AppMediaItem item;
  final List<AppMediaItem> playlist;
  final double height;
  const _TrackRow({
    required this.item,
    required this.playlist,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isCurrent = context.select<MusicPlayerProvider, bool>(
      (p) => p.currentTrack?.id == item.id,
    );
    return InkWell(
      onTap: () => context.read<MusicPlayerProvider>().playTrack(
        item,
        playlist: playlist,
      ),
      onLongPress: () => showTrackActions(context, item),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              _Artwork(url: item.artUri, size: 50, radius: 6),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: isCurrent
                            ? context.colors.accent
                            : context.colors.mist,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.mist.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'More',
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: context.colors.mist.withValues(alpha: 0.7),
                ),
                onPressed: () => showTrackActions(context, item),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square playlist cards. Each card is a search; its artwork is the cover of
/// the first song it finds.
class _CardsSection extends StatelessWidget {
  final HomeSection section;
  const _CardsSection({super.key, required this.section});

  static const _cardSize = 150.0;
  static const _titleLineHeight = 1.25;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(section.title),
        SizedBox(
          // Artwork, gap, and two lines of title at the user's font size.
          height:
              _cardSize +
              8 +
              MediaQuery.textScalerOf(context).scale(14) *
                  _titleLineHeight *
                  2 +
              2,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: section.cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) =>
                _PlaylistCard(card: section.cards[index], size: _cardSize),
          ),
        ),
      ],
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final HomeCard card;
  final double size;
  const _PlaylistCard({required this.card, required this.size});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrackListScreen(title: card.title, query: card.query),
        ),
      ),
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<List<AppMediaItem>>(
              future: YoutubeService().cachedSearch(card.query),
              builder: (context, snapshot) {
                final tracks = snapshot.data;
                return _Artwork(
                  url: tracks != null && tracks.isNotEmpty
                      ? tracks.first.artUri
                      : null,
                  size: size,
                  radius: 12,
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              card.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: _CardsSection._titleLineHeight,
                color: context.colors.mist,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  const _Artwork({required this.url, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: context.colors.lift,
      child: Icon(
        Icons.music_note_rounded,
        color: AppTheme.primary,
        size: size * 0.4,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url != null && url!.startsWith('http')
          ? CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  final int rows;
  final double height;
  const _RowsSkeleton({required this.rows, required this.height});

  @override
  Widget build(BuildContext context) {
    final block = context.colors.mist.withValues(alpha: 0.06);
    return Column(
      children: [
        for (var i = 0; i < rows; i++)
          SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 180, height: 12, color: block),
                        const SizedBox(height: 8),
                        Container(width: 110, height: 10, color: block),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadFailed extends StatelessWidget {
  final VoidCallback onRetry;
  const _LoadFailed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Flexible(
            child: Text(
              "Couldn't load these songs.",
              style: TextStyle(
                color: context.colors.mist.withValues(alpha: 0.55),
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
