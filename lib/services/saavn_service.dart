import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../models/media_item_model.dart';
import 'storage_service.dart';

/// JioSaavn's web API — the Online tab's source for songs.
///
/// Why not YouTube: a JioSaavn search result already carries its playable
/// URL (DES-encrypted), the CDN URLs don't expire, and the files are served
/// whole — so a tap plays with no per-song lookup. Measured from a PC:
/// search ~240ms, trending/autocomplete ~110ms, byte ranges served from any
/// point of the file at 96/160/320 kbps.
///
/// This is JioSaavn's *private* web API: no key or account, outside their
/// terms — personal use only. If it changes, `dart run tool/probe_saavn.dart`
/// says so in seconds. Full notes: docs/BACKEND_SAAVN.md.
class SaavnService {
  SaavnService._();
  static final SaavnService instance = SaavnService._();

  static const _base = 'https://www.jiosaavn.com/api.php';

  /// JioSaavn picks the feed language from this cookie (without it,
  /// trending is Hindi). Follows Settings > Home language.
  String get _languageCookie {
    final language = StorageService().getHomeLanguage();
    return 'L=${(language ?? 'hindi,english').toLowerCase()}';
  }

  /// [ctx] is the client JioSaavn thinks it's talking to; radio only
  /// answers the Android app ("android"), everything else the web one.
  Future<dynamic> _call(
    String endpoint,
    Map<String, String> params, {
    String ctx = 'web6dot0',
  }) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        '__call': endpoint,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': ctx,
        ...params,
      },
    );
    final request = await _client.getUrl(uri);
    {
      request.headers.set(HttpHeaders.cookieHeader, _languageCookie);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        await response.drain<void>().catchError((_) {});
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 10));
      return jsonDecode(body);
    }
  }

  /// Shared, so the home page's ~20 calls and every autocomplete keystroke
  /// reuse one connection instead of a new TLS handshake each.
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30);

  // JioSaavn is loosely typed: a field that's a list in one response is a
  // string in the next. Every access goes through these, never a hard cast.
  static List? _list(dynamic v) => v is List ? v : null;
  static Map? _map(dynamic v) => v is Map ? v : null;
  static String _str(dynamic v) => v == null ? '' : '$v';

  /// Songs matching [query].
  Future<List<AppMediaItem>> searchSongs(String query, {int count = 30}) async {
    final res = await _call('search.getResults', {
      'q': query,
      'p': '1',
      'n': '$count',
    });
    return _songs(_list(_map(res)?['results']));
  }

  /// What's trending in [language] (e.g. "tamil").
  Future<List<AppMediaItem>> trending(String? language) async {
    final res = await _call('content.getTrending', {
      'entity_type': 'song',
      'entity_language': (language ?? 'hindi').toLowerCase(),
    });
    return _songs(_list(res));
  }

  /// The songs of the best-matching editorial playlist for [query] — curated
  /// and in one language, unlike a plain search for an artist or mood.
  /// Falls back to a song search when there's no such playlist.
  Future<List<AppMediaItem>> playlistSongs(String query) async {
    final found = await _call('search.getPlaylistResults', {
      'q': query,
      'p': '1',
      'n': '1',
    });
    final playlist = _map(_list(_map(found)?['results'])?.firstOrNull);
    final id = _str(playlist?['id']);
    if (id.isEmpty) return searchSongs(query);
    final details = await _call('playlist.getDetails', {
      'listid': id,
      'n': '50',
      'p': '1',
    });
    final songs = _songs(_list(_map(details)?['list']));
    return songs.isNotEmpty ? songs : searchSongs(query);
  }

  /// Autocomplete for the search box: song, album and artist names.
  Future<List<String>> suggestions(String query) async {
    final res = await _call('autocomplete.get', {'query': query});
    final seen = <String>{};
    final out = <String>[];
    for (final kind in ['songs', 'albums', 'artists', 'playlists']) {
      for (final e in _list(_map(_map(res)?[kind])?['data']) ?? const []) {
        final title = unescape(_str(_map(e)?['title'])).trim();
        if (title.isNotEmpty && seen.add(title.toLowerCase())) out.add(title);
      }
    }
    return out.take(8).toList();
  }

  /// JioSaavn's lyrics for song [id], as plain text, or null.
  Future<String?> lyrics(String id) async {
    final res = await _call('lyrics.getLyrics', {'lyrics_id': id});
    final text = _str(_map(res)?['lyrics']);
    if (text.isEmpty) return null;
    return unescape(text.replaceAll(RegExp(r'<br\s*/?>'), '\n')).trim();
  }

  /// A fresh copy of one song (e.g. one saved without a media URL).
  Future<AppMediaItem?> song(String id) async {
    final res = await _call('song.getDetails', {'pids': id});
    final map = _map(res);
    final entry = _map(map?[id]) ?? _map(_list(map?['songs'])?.firstOrNull);
    return entry == null ? null : toItem(entry);
  }

  /// Replaces [radio] in tests (no network).
  @visibleForTesting
  static Future<List<AppMediaItem>> Function(String songId)? debugRadioOverride;

  /// Extras keys set by [toItem].
  static const albumIdKey = 'saavnAlbumId';
  static const artistIdKey = 'saavnArtistId';
  static const permaUrlKey = 'permaUrl';

  /// Songs like [songId] — JioSaavn's radio station seeded with it, for
  /// autoplay when the queue runs out. Empty if the station can't be made.
  Future<List<AppMediaItem>> radio(String songId, {int count = 20}) async {
    if (debugRadioOverride case final fake?) return fake(songId);
    final station = await _call('webradio.createEntityStation', {
      'entity_id': '["$songId"]',
      'entity_type': 'queue',
    }, ctx: 'android');
    final id = _str(_map(station)?['stationid']);
    if (id.isEmpty) return const [];
    final res = await _call('webradio.getSong', {
      'stationid': id,
      'k': '$count',
      'next': '1',
    }, ctx: 'android');
    // {"0": {"song": {...}}, "1": ..., "stationid": ...}
    final entries = _map(res)?.values.map((v) => _map(v)?['song']).toList();
    return _songs(entries).where((s) => s.id != songId).toList();
  }

  /// Album [id]: its songs, plus name and artwork.
  Future<SaavnCollection?> album(String id) async {
    final res = _map(await _call('content.getAlbumDetails', {'albumid': id}));
    if (res == null) return null;
    return _collection(res, 'album')?.withSongs(_songs(_list(res['list'])));
  }

  /// Playlist [id]'s songs.
  Future<List<AppMediaItem>> playlist(String id) async {
    final res = await _call('playlist.getDetails', {
      'listid': id,
      'n': '100',
      'p': '1',
    });
    return _songs(_list(_map(res)?['list']));
  }

  /// Artist [id]: top songs and albums.
  Future<SaavnArtist?> artist(String id) async {
    final res = _map(
      await _call('artist.getArtistPageDetails', {
        'artistId': id,
        'n_song': '50',
        'n_album': '30',
      }),
    );
    if (res == null || _str(res['name']).isEmpty) return null;
    return SaavnArtist(
      id: id,
      name: unescape(_str(res['name'])),
      image: _bigImage(_str(res['image'])),
      topSongs: _songs(_list(res['topSongs'])),
      albums: _collections(_list(res['topAlbums']), 'album'),
    );
  }

  /// Search tabs: albums, playlists or artists matching [query].
  Future<List<SaavnCollection>> searchCollections(
    String query,
    SaavnKind kind,
  ) async {
    final res = await _call(
      switch (kind) {
        SaavnKind.album => 'search.getAlbumResults',
        SaavnKind.playlist => 'search.getPlaylistResults',
        SaavnKind.artist => 'search.getArtistResults',
      },
      {'q': query, 'p': '1', 'n': '20'},
    );
    return _collections(_list(_map(res)?['results']), kind.name);
  }

  static List<SaavnCollection> _collections(List? raw, String kind) => [
    for (final e in raw ?? const []) ?_collection(_map(e), kind),
  ];

  static SaavnCollection? _collection(Map? json, String fallbackKind) {
    final id = _str(json?['id']);
    if (json == null || id.isEmpty) return null;
    final kind = SaavnKind.values.firstWhere(
      (k) => k.name == _str(json['type']),
      orElse: () => SaavnKind.values.byName(fallbackKind),
    );
    return SaavnCollection(
      kind: kind,
      id: id,
      title: unescape(_str(json['title']).ifEmpty(_str(json['name']))),
      subtitle: unescape(
        _str(json['subtitle']).ifEmpty(_str(json['description'])),
      ),
      image: _bigImage(_str(json['image'])),
    );
  }

  static String _bigImage(String url) =>
      url.replaceAll('150x150', '500x500').replaceAll('50x50', '500x500');

  List<AppMediaItem> _songs(List? raw) {
    final out = <AppMediaItem>[];
    for (final e in raw ?? const []) {
      final item = toItem(_map(e));
      if (item != null) out.add(item);
    }
    return out;
  }

  /// One JioSaavn song as an [AppMediaItem], or null if it isn't a playable
  /// song (albums/playlists in mixed lists, missing media URL).
  @visibleForTesting
  static AppMediaItem? toItem(Map? json) {
    if (json == null) return null;
    final type = _str(json['type']);
    if (type.isNotEmpty && type != 'song') return null;
    final more = _map(json['more_info']) ?? const {};
    final encrypted = _str(more['encrypted_media_url']);
    final id = _str(json['id']);
    if (id.isEmpty || encrypted.isEmpty) return null;

    String? url;
    try {
      url = decryptMediaUrl(encrypted);
    } catch (e) {
      debugPrint('JioSaavn decrypt failed for $id: $e');
      return null;
    }

    final primary =
        _list(_map(more['artistMap'])?['primary_artists']) ?? const [];
    final artists = primary
        .map((a) => unescape(_str(_map(a)?['name'])))
        .where((n) => n.isNotEmpty)
        .join(', ');
    final seconds = int.tryParse(_str(more['duration']));
    return AppMediaItem(
      id: id,
      title: unescape(_str(json['title'])),
      artist: artists.isNotEmpty
          ? artists
          : unescape(
              _str(more['music']),
            ).ifEmpty(unescape(_str(json['subtitle']))),
      album: unescape(_str(more['album'])).ifEmpty(onlineAlbumLabel),
      // 150x150 by default; the CDN has the same art at 500x500.
      artUri: _str(json['image']).replaceAll('150x150', '500x500'),
      streamUrl: url,
      duration: seconds == null ? null : Duration(seconds: seconds),
      sourceType: MediaSourceType.saavn,
      // For the artist/album pages and Share. Kept in extras so they survive
      // playback, favorites and history.
      extras: {
        if (_str(more['album_id']).isNotEmpty)
          albumIdKey: _str(more['album_id']),
        if (primary.isNotEmpty && _str(_map(primary.first)?['id']).isNotEmpty)
          artistIdKey: _str(_map(primary.first)?['id']),
        if (_str(json['perma_url']).isNotEmpty)
          permaUrlKey: _str(json['perma_url']),
      },
    );
  }

  /// `more_info.encrypted_media_url` → a plain CDN URL. DES-ECB with the
  /// long-public key "38346591"; PointyCastle only has triple DES, and 3DES
  /// with the same key three times is single DES.
  @visibleForTesting
  static String decryptMediaUrl(String encrypted) {
    final key = Uint8List.fromList(utf8.encode('38346591' * 3));
    final engine = DESedeEngine()..init(false, DESedeParameters(key));
    final data = base64.decode(encrypted.trim());
    final out = Uint8List(data.length);
    for (var i = 0; i + 8 <= data.length; i += 8) {
      engine.processBlock(data, i, out, i);
    }
    final pad = out.isEmpty ? 0 : out.last;
    final end = pad >= 1 && pad <= 8 ? out.length - pad : out.length;
    return utf8.decode(out.sublist(0, end));
  }

  /// The same song at the bitrate for [quality] (96 / 160 / 320 kbps).
  static String withQuality(String url, AudioQuality quality) {
    final kbps = switch (quality) {
      AudioQuality.dataSaver => 96,
      AudioQuality.balanced => 160,
      AudioQuality.best => 320,
    };
    return url.replaceFirst(RegExp(r'_(12|48|96|160|320)\.mp4'), '_$kbps.mp4');
  }

  /// JioSaavn text arrives HTML-escaped ("From &quot;Leo&quot;").
  @visibleForTesting
  static String unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

enum SaavnKind { album, playlist, artist }

/// An album, playlist or artist as listed in search results.
class SaavnCollection {
  final SaavnKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String image;

  /// Filled in for a fetched album; empty in search results.
  final List<AppMediaItem> songs;

  const SaavnCollection({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.image,
    this.songs = const [],
  });

  SaavnCollection withSongs(List<AppMediaItem> songs) => SaavnCollection(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    image: image,
    songs: songs,
  );
}

class SaavnArtist {
  final String id;
  final String name;
  final String image;
  final List<AppMediaItem> topSongs;
  final List<SaavnCollection> albums;

  const SaavnArtist({
    required this.id,
    required this.name,
    required this.image,
    required this.topSongs,
    required this.albums,
  });
}
