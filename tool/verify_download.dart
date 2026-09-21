// Throwaway diagnostic: exercises the real extraction + download path against
// YouTube, outside Flutter. Tests search and stream resolution separately so a
// failure in one doesn't hide the other.
//
// Run: dart run tool/verify_download.dart
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const String knownVideoId = 'dQw4w9WgXcQ';

void main() async {
  final yt = YoutubeExplode();

  stdout.writeln('=== 1. SEARCH (Online tab listing) ===');
  try {
    final results = await yt.search.search('lofi hip hop');
    stdout.writeln('OK: ${results.length} results, first="${results.first.title}"');
  } catch (e) {
    stdout.writeln('BROKEN: $e');
  }

  stdout.writeln('\n=== 2. VIDEO METADATA ===');
  try {
    final video = await yt.videos.get(knownVideoId);
    stdout.writeln('OK: "${video.title}" by ${video.author} (${video.duration})');
  } catch (e) {
    stdout.writeln('BROKEN: $e');
  }

  stdout.writeln('\n=== 3. STREAM MANIFEST (playback + download) ===');
  StreamManifest? manifest;
  try {
    manifest = await yt.videos.streamsClient.getManifest(knownVideoId);
    stdout.writeln('OK: ${manifest.audioOnly.length} audio-only streams, '
        '${manifest.muxed.length} muxed');
    for (final s in manifest.audioOnly) {
      stdout.writeln('   container=${s.container.name.padRight(5)} '
          'codec=${s.codec.subtype.padRight(6)} bitrate=${s.bitrate}');
    }
  } catch (e) {
    stdout.writeln('BROKEN: $e');
  }

  if (manifest == null || manifest.audioOnly.isEmpty) {
    yt.close();
    exitCode = 1;
    return;
  }

  stdout.writeln('\n=== 4. STREAM SELECTION (Pulse logic) ===');
  final streams = manifest.audioOnly;
  final mp4 = streams.where((s) => s.container == StreamContainer.mp4).toList();
  final chosen =
      mp4.isNotEmpty ? mp4.withHighestBitrate() : streams.withHighestBitrate();
  final ext =
      chosen.container == StreamContainer.mp4 ? 'm4a' : chosen.container.name;
  final naive = streams.withHighestBitrate();

  stdout.writeln('Pulse picks : ${chosen.container.name} -> .$ext  '
      '(${chosen.codec.subtype}, ${chosen.bitrate})');
  stdout.writeln('Naive pick  : ${naive.container.name} '
      '(${naive.codec.subtype}, ${naive.bitrate})  <- the old behaviour');
  // audioOnly streams carry no video track by construction; printing the
  // runtime type makes that visible rather than asserting a tautology.
  stdout.writeln('Stream type : ${chosen.runtimeType}');

  stdout.writeln('\n=== 5. ACTUAL DOWNLOAD ===');
  try {
    final file = File('${Directory.systemTemp.path}/pulse_dl_test.$ext');
    final sink = file.openWrite();
    var received = 0;
    final watch = Stopwatch()..start();
    await for (final chunk in yt.videos.streamsClient.get(chosen)) {
      sink.add(chunk);
      received += chunk.length;
      if (received > 400000) break;
    }
    await sink.flush();
    await sink.close();
    watch.stop();

    stdout.writeln('OK: wrote $received bytes in ${watch.elapsedMilliseconds}ms '
        '(full track would be ${chosen.size})');

    final head = await file.openRead(0, 12).first;
    stdout.writeln('magic: '
        '${head.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    final isMp4 = head.length > 7 &&
        head[4] == 0x66 && head[5] == 0x74 && head[6] == 0x79 && head[7] == 0x70;
    final isWebm = head.length > 3 &&
        head[0] == 0x1a && head[1] == 0x45 && head[2] == 0xdf && head[3] == 0xa3;
    final detected = isMp4 ? 'MP4/M4A' : (isWebm ? 'WebM' : 'unknown');
    stdout.writeln('contents  : $detected');
    stdout.writeln('extension : .$ext');
    stdout.writeln('match?    : '
        '${(isMp4 && ext == 'm4a') || (isWebm && ext == 'webm')}');
    await file.delete();
  } catch (e) {
    stdout.writeln('BROKEN: $e');
    exitCode = 1;
  }

  yt.close();
}
