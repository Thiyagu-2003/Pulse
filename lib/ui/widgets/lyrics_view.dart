import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/lyrics.dart';

/// Lyrics that move with the song.
///
/// Synced lyrics: the line being sung is highlighted and scrolled to ~40%
/// down the panel; tapping a line seeks there. Plain lyrics: the text glides
/// along with the song's progress. Either way, scrolling by hand pauses the
/// auto-follow for a few seconds.
///
/// Lives on Now Playing, which is dark in both themes, so it draws in white.
class LyricsView extends StatefulWidget {
  final Lyrics lyrics;
  final Stream<Duration> positions;
  final Duration? Function() duration;
  final void Function(Duration) onSeek;

  const LyricsView({
    super.key,
    required this.lyrics,
    required this.positions,
    required this.duration,
    required this.onSeek,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _lineKeys =
      List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
  StreamSubscription<Duration>? _sub;
  int _current = -1;
  DateTime _userScrolledAt = DateTime(0);

  static const _followPause = Duration(seconds: 4);

  bool get _userIsScrolling =>
      DateTime.now().difference(_userScrolledAt) < _followPause;

  @override
  void initState() {
    super.initState();
    _sub = widget.positions.listen(_onPosition);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    if (widget.lyrics.isSynced) {
      final index = widget.lyrics.indexAt(position);
      if (index == _current) return; // rebuild only when the line changes
      setState(() => _current = index);
      if (index >= 0 && !_userIsScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToLine(index));
      }
    } else {
      _glide(position);
    }
  }

  void _scrollToLine(int index) {
    final context = _lineKeys[index].currentContext;
    if (context == null || !mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.4,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// Plain lyrics: keep the text's scroll in step with the song's progress.
  void _glide(Duration position) {
    final total = widget.duration();
    if (_userIsScrolling || total == null || total == Duration.zero) return;
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final target =
        (max * position.inMilliseconds / total.inMilliseconds).clamp(0.0, max);
    if ((target - _scroll.offset).abs() < 2) return;
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 600), curve: Curves.linear);
  }

  bool _onScroll(ScrollNotification n) {
    // Only a finger counts; the auto-follow's own animations don't.
    if (n is ScrollStartNotification && n.dragDetails != null ||
        n is ScrollUpdateNotification && n.dragDetails != null) {
      _userScrolledAt = DateTime.now();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final lyrics = widget.lyrics;
    return LayoutBuilder(
      builder: (context, box) {
        // Room above and below, so the first and last lines can reach the
        // highlight position too.
        final pad = box.maxHeight * 0.4;
        return NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ShaderMask(
            // Soft fade at the top and bottom edges.
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.12, 0.88, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.symmetric(vertical: lyrics.isSynced ? pad : 24),
              child: Column(
                children: [
                  if (lyrics.isSynced)
                    for (var i = 0; i < lyrics.lines.length; i++)
                      _line(i)
                  else ...[
                    Text(
                      lyrics.plain,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.9,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    lyrics.isSynced
                        ? 'Lyrics: ${lyrics.source}'
                        : 'Lyrics: ${lyrics.source} · not time-synced',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(int i) {
    final line = widget.lyrics.lines[i];
    final isCurrent = i == _current;
    final isPast = i < _current;
    return GestureDetector(
      key: _lineKeys[i],
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _userScrolledAt = DateTime(0); // tapping means "follow from here"
        widget.onSeek(line.time);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: isCurrent ? 23 : 18,
            height: 1.35,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent
                ? Colors.white
                : Colors.white.withValues(alpha: isPast ? 0.32 : 0.5),
          ),
          child: Text(line.text, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}
