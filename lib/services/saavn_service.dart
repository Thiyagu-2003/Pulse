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

  Future<dynamic> _call(String endpoint, Map<String, String> params) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        '__call': endpoint,
        '_format': 'json',
        '_marker': '0',
        'api_version': '4',
        'ctx': 'web6dot0',
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
