import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Three bars rising and falling while audio plays.
///
/// This is the app's one piece of continuous, non-user-triggered motion, and
/// it earns that by carrying information rather than decoration: it marks
/// which row in a list is the one you can hear, and it stops moving when
/// playback pauses — so the list answers "is it playing?" without a second
/// icon. It is also, literally, the pulse the app is named after.
class PlayingIndicator extends StatefulWidget {
  final bool isPlaying;
  final double size;
  /// Defaults to the theme's accent.
  final Color? color;

  const PlayingIndicator({
    super.key,
    required this.isPlaying,
    this.size = 16,
    this.color,
  });

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// Offsets so the bars don't move as one block.
  static const List<double> _phases = [0.0, 0.45, 0.8];

  // MediaQuery must not be read in initState — depending on an inherited
  // widget before initState completes trips an assertion. didChangeDependencies
  // is the correct hook, and it also picks up the accessibility setting being
  // changed while the app is running.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(PlayingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) _syncAnimation();
  }

  void _syncAnimation() {
    // Respect the system "remove animations" setting — a looping animation is
    // exactly what that setting exists to stop.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    if (widget.isPlaying && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
      return;
    }

    // Settle to a resting height rather than freezing mid-stride.
    _controller.stop();
    _controller.animateTo(0, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / 6;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final phase in _phases)
                _bar(barWidth, _heightFactor(phase)),
            ],
          );
        },
      ),
    );
  }

  double _heightFactor(double phase) {
    if (!widget.isPlaying && _controller.value == 0) return 0.32;
    final wave = math.sin((_controller.value + phase) * 2 * math.pi);
    // Map -1..1 onto a floor of 0.28 so a bar never collapses to nothing.
    return 0.28 + (wave + 1) / 2 * 0.72;
  }

  Widget _bar(double width, double factor) {
    return Container(
      width: width,
      height: widget.size * factor,
      decoration: BoxDecoration(
        color: widget.color ?? context.colors.accent,
        borderRadius: BorderRadius.circular(width),
      ),
    );
  }
}
