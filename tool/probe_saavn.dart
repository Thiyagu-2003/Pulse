// Live check of the JioSaavn API from a PC: search, decrypt the media url,
// then fetch bytes from the start and from 80% into the file.
//
// Run: dart run tool/probe_saavn.dart "vaseegara"
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const _base = 'https://www.jiosaavn.com/api.php';

Future<dynamic> call(String endpoint, Map<String, String> params,
    {String lang = 'tamil'}) async {
  final uri = Uri.parse(_base).replace(queryParameters: {
    '__call': endpoint,
    '_format': 'json',
    '_marker': '0',
    'api_version': '4',
    'ctx': 'web6dot0',
    ...params,
  });
  final c = HttpClient();
  final sw = Stopwatch()..start();
  try {
    final req = await c.getUrl(uri);
    req.headers.set('Cookie', 'L=$lang');
    final res = await req.close();
    final body = await utf8.decodeStream(res);
    stdout.writeln('  $endpoint -> HTTP ${res.statusCode} in ${sw.elapsedMilliseconds}ms');
    return jsonDecode(body);
  } finally {
    c.close();
  }
}

String decrypt(String encrypted) {
  final key = Uint8List.fromList(utf8.encode('38346591' * 3));
  final engine = DESedeEngine()..init(false, DESedeParameters(key));
  final data = base64.decode(encrypted.trim());
  final out = Uint8List(data.length);
  for (var i = 0; i < data.length; i += 8) {
    engine.processBlock(data, i, out, i);
  }
  final pad = out.last;
  return utf8.decode(out.sublist(0, out.length - (pad <= 8 ? pad : 0)));
}

Future<(int, int)> fetchRange(String url, int from, int len) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('Range', 'bytes=$from-${from + len - 1}');
    final res = await req.close();
    final n = await res.fold<int>(0, (s, b) => s + b.length);
    return (res.statusCode, n);
  } finally {
    c.close(force: true);
  }
}

void main(List<String> args) async {
  final q = args.isEmpty ? 'vaseegara' : args.first;
  stdout.writeln('search "$q"');
  final res = await call('search.getResults', {'q': q, 'p': '1', 'n': '10'});
  final results = (res is Map ? res['results'] : null) as List? ?? [];
  stdout.writeln('  ${results.length} songs');
  for (final s in results.take(3)) {
    final m = s as Map;
    final more = m['more_info'] as Map? ?? {};
    stdout.writeln('  - ${m['title']} | ${more['music'] ?? m['subtitle']} | '
        '${more['duration']}s | lang=${m['language']}');
  }
  if (results.isEmpty) return;
  final more = (results.first as Map)['more_info'] as Map;
  final url = decrypt(more['encrypted_media_url'] as String);
  stdout.writeln('decrypted: $url');
  for (final br in ['96', '160', '320']) {
    final u = url.replaceAll(RegExp(r'_\d+\.mp4'), '_$br.mp4');
    final head = await HttpClient().headUrl(Uri.parse(u)).then((r) => r.close());
    final total = head.contentLength;
    final (s0, n0) = await fetchRange(u, 0, 65536);
    final at80 = (total * 0.8).round();
    final (s80, n80) = await fetchRange(u, at80, 65536);
    stdout.writeln('  _$br: ${(total / 1048576).toStringAsFixed(1)} MB  '
        'start=$s0/${n0}B  at80%=$s80/${n80}B');
  }

  stdout.writeln('trending tamil');
  final t = await call('content.getTrending',
      {'entity_type': 'song', 'entity_language': 'tamil'});
  stdout.writeln('  ${t is List ? t.length : 'not a list: ${t.runtimeType}'} items');
  stdout.writeln('autocomplete "anir"');
  final a = await call('autocomplete.get', {'query': 'anir'});
  if (a is Map) {
    for (final k in ['songs', 'albums', 'artists', 'playlists']) {
      final d = (a[k] as Map?)?['data'] as List? ?? [];
      stdout.writeln('  $k: ${d.map((e) => (e as Map)['title']).take(3).toList()}');
    }
  }
}
