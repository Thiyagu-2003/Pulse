import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:music_player/models/home_sections.dart';
import 'package:music_player/models/listening_stats.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/services/storage_service.dart';

AppMediaItem _song(String id, String artist,
        {MediaSourceType type = MediaSourceType.saavn}) =>
    AppMediaItem(
      id: id,
      title: 'Song $id',
      artist: artist,
      duration: const Duration(minutes: 4),
      sourceType: type,
    );

void main() {
  test('lead artist', () {
    expect(mainArtist('Anirudh Ravichander, Arivu'), 'Anirudh Ravichander');
    expect(mainArtist('A.R. Rahman & Shreya'), 'A.R. Rahman');
    expect(mainArtist('Unknown Artist'), '');
  });

  test('history counts plays; stats and mixes follow them', () async {
    Hive.init((await Directory.systemTemp.createTemp('pulse_stats_')).path);
    await Hive.openBox<String>(StorageService.historyBox);
    final storage = StorageService();
    for (final (song, times) in [
      (_song('a', 'Anirudh, Arivu'), 3),
      (_song('b', 'Anirudh'), 2),
      (_song('c', 'Ilaiyaraaja'), 2),
      (_song('yt', 'Yuvan', type: MediaSourceType.youtube), 1),
    ]) {
      for (var i = 0; i < times; i++) {
        await storage.addToHistory(song);
      }
      // Distinct timestamps, so "newest" is well defined.
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }

    final entries = storage.getHistoryEntries();
    expect(entries.first.item.id, 'yt'); // newest first
    final stats = ListeningStats.from(entries);
    expect(stats.plays, 8);
    expect(stats.time, const Duration(minutes: 32));
    expect(stats.topSongs.first.$1.id, 'a');
    expect(stats.topArtists.first, ('Anirudh', 5));

    final sections = madeForYou(entries);
    // Radio from the last JioSaavn song (not the YouTube one), then mixes.
    expect(sections.map((s) => s.query),
        ['radio:c', 'playlist:Anirudh', 'playlist:Ilaiyaraaja']);
    expect(sections.map((s) => s.id),
        ['foryou_radio', 'foryou_artist0', 'foryou_artist1']);
    expect(madeForYou(const []), isEmpty);

    // Placed after "Recently played" unless the user moved them.
    final home = arrangeHome('Tamil', HomeLayout.standard, personal: sections);
    expect(home.take(4).map((s) => s.id),
        ['recent', 'foryou_radio', 'foryou_artist0', 'foryou_artist1']);
  });
}
