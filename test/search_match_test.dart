import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/models/media_item_model.dart';
import 'package:music_player/models/search_match.dart';

AppMediaItem _song(String title, {String album = 'Album', String artist = 'Artist'}) =>
    AppMediaItem(
        id: title, title: title, album: album, artist: artist, sourceType: MediaSourceType.saavn);

void main() {
  test('filler words are dropped, but never everything', () {
    expect(stripFiller('kamatchi song lyrics'), 'kamatchi');
    expect(stripFiller('Vaathi Coming Tamil Full Video'), 'vaathi coming');
    expect(stripFiller('song'), 'song');
  });

  test('transliteration variants fold together', () {
    expect(foldWord('Kaamaatchi'), foldWord('kamatchi'));
    expect(foldWord('Vaseegara'), foldWord('vasegara'));
    expect(foldWord('Vazhithunaiye'), foldWord('valithunaiye'));
    expect(foldWord('Pirindhaai'), foldWord('pirinthai'));
  });

  test('typos still match; different words do not', () {
    expect(wordsMatch('vaseegra', 'Vaseegara'), isTrue);
    expect(wordsMatch('hukkum', 'Hukum'), isTrue);
    expect(wordsMatch('dapam', 'Dappam'), isTrue);
    expect(wordsMatch('puthri', 'Puthiri'), isTrue);
    expect(wordsMatch('kannu', 'Kannukulla'), isTrue); // prefix
    expect(wordsMatch('beast', 'Leo'), isFalse);
    expect(wordsMatch('love', 'life'), isFalse);
  });

  test('results about the query are relevant; others are not', () {
    final kaamaatchi = [_song('Kaamaatchi', artist: 'Sunder Chandran')];
    expect(looksRelevant('kamatchi song', kaamaatchi), isTrue);
    expect(looksRelevant('kannu kulla', [_song('Kannukulla')]), isTrue); // glued
    expect(looksRelevant('vijay beast arabic song',
        [_song('Arabic Kuthu - Halamithi Habibo', album: 'Beast')]), isTrue);

    // What JioSaavn gave for "kamatchi song": other songs entirely.
    expect(looksRelevant('kamatchi song', [_song('Kamal Song'), _song('Soul Music')]),
        isFalse);
    expect(looksRelevant('anything', []), isFalse);
  });

  test('a YouTube title becomes the song name', () {
    expect(songNameFromVideoTitle(
            'Arabic Kuthu - Official Lyric Video | Beast | Thalapathy Vijay'),
        'Arabic Kuthu');
    expect(songNameFromVideoTitle('Vaseegara (Official Video) HD'), 'Vaseegara');
  });
}
