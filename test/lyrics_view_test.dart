import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:music_player/models/lyrics.dart';
import 'package:music_player/ui/widgets/lyrics_view.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  double sizeOf(WidgetTester tester, String line) {
    final style = tester
        .widget<AnimatedDefaultTextStyle>(find.ancestor(
            of: find.text(line),
            matching: find.byType(AnimatedDefaultTextStyle)).first)
        .style;
    return style.fontSize!;
  }

  testWidgets('highlights the line being sung, follows it, and seeks on tap',
      (tester) async {
    final positions = StreamController<Duration>();
    Duration? seekedTo;
    final lines = [
      for (var i = 0; i < 30; i++) '[00:${(i * 2).toString().padLeft(2, '0')}.00]line $i',
    ].join('\n');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: LyricsView(
            lyrics: Lyrics.synced(Lyrics.parseLrc(lines), 'LRCLIB'),
            positions: positions.stream,
            duration: () => const Duration(minutes: 1),
            onSeek: (d) => seekedTo = d,
          ),
        ),
      ),
    ));

    positions.add(const Duration(seconds: 4, milliseconds: 500));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(sizeOf(tester, 'line 2'), 23); // current
    expect(sizeOf(tester, 'line 3'), 18);

    // Later in the song: the highlight moves and the list scrolls to it.
    positions.add(const Duration(seconds: 40));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(sizeOf(tester, 'line 20'), 23);
    expect(sizeOf(tester, 'line 2'), 18);
    expect(tester.getTopLeft(find.text('line 20')).dy, lessThan(400));

    await tester.tap(find.text('line 22'));
    expect(seekedTo, const Duration(seconds: 44));
    expect(find.text('Lyrics: LRCLIB'), findsOneWidget);
    await positions.close();
  });

  testWidgets('plain lyrics say they are not time-synced', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 400,
          child: LyricsView(
            lyrics: Lyrics.plainText('some words', 'JioSaavn'),
            positions: const Stream.empty(),
            duration: () => null,
            onSeek: (_) {},
          ),
        ),
      ),
    ));
    expect(find.text('some words'), findsOneWidget);
    expect(find.text('Lyrics: JioSaavn · not time-synced'), findsOneWidget);
  });
}
