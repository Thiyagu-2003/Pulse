import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Play/pause control whose glyph morphs between the two states.
///
/// Motion here answers the tap: the triangle folds into the bars, so the
/// button shows the state it has just moved to rather than swapping icons
/// between frames. Used by both the mini player and Now Playing so the two
/// controls behave identically.
class PlayPauseButton extends StatefulWidget {
  final bool isPlaying;
  final VoidCallback onPressed;
  final double size;
  /// Defaults to the theme's accent.
  final Color? color;

  const PlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.size = 28,
    this.color,
  });

  @override
  State<PlayPauseButton> createState() => _PlayPauseButtonState();
}

class _PlayPauseButtonState extends State<PlayPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    // Start settled in the current state, so the icon doesn't animate in
    // from "play" every time the widget is rebuilt.
    value: widget.isPlaying ? 1 : 0,
  );

  @override
  void didUpdateWidget(PlayPauseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    widget.isPlaying ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: widget.onPressed,
      tooltip: widget.isPlaying ? 'Pause' : 'Play',
      icon: AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _controller,
        size: widget.size,
        color: widget.color ?? context.colors.accent,
      ),
    );
  }
}
