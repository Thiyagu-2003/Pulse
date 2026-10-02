import 'dart:async';

import 'package:flutter/material.dart';
import '../../services/voice_command_service.dart';
import '../theme/app_theme.dart';

/// A full-screen overlay that shows the pulsating mic animation while the
/// user is speaking, the live transcript, and the parsed command feedback.
///
/// Usage:
/// ```dart
/// VoiceCommandOverlay.show(context, onCommand: (cmd) { ... });
/// ```
class VoiceCommandOverlay extends StatefulWidget {
  final VoiceCommandService service;
  final void Function(VoiceCommand command) onCommand;

  const VoiceCommandOverlay({
    super.key,
    required this.service,
    required this.onCommand,
  });

  /// Convenience: push the overlay as a transparent route.
  static Future<void> show(
    BuildContext context, {
    required VoiceCommandService service,
    required void Function(VoiceCommand command) onCommand,
  }) async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) => VoiceCommandOverlay(
          service: service,
          onCommand: onCommand,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  @override
  State<VoiceCommandOverlay> createState() => _VoiceCommandOverlayState();
}

class _VoiceCommandOverlayState extends State<VoiceCommandOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _waveController;
  late final Animation<double> _pulseAnimation;

  String _transcript = '';
  String _statusText = 'Listening...';
  bool _isListening = false;
  bool _hasResult = false;
  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<VoiceCommand>? _commandSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _listeningSub;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _subscribeStreams();
    _startListening();
  }

  void _subscribeStreams() {
    _transcriptSub = widget.service.transcriptStream.listen((text) {
      if (mounted) setState(() => _transcript = text);
    });
    _commandSub = widget.service.commandStream.listen((command) {
      if (!mounted) return;
      setState(() {
        _hasResult = true;
        _statusText = _commandLabel(command);
      });
      widget.onCommand(command);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.of(context).pop();
      });
    });
    _errorSub = widget.service.errorStream.listen((error) {
      if (!mounted) return;
      setState(() => _statusText = error);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    });
    _listeningSub = widget.service.listeningStream.listen((listening) {
      if (mounted) setState(() => _isListening = listening);
    });
  }

  Future<void> _startListening() async {
    final started = await widget.service.startListening();
    if (!started && mounted) {
      setState(() => _statusText = 'Could not start voice recognition');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  String _commandLabel(VoiceCommand cmd) {
    return switch (cmd.action) {
      VoiceAction.play => '▶ Playing "${cmd.query}"',
      VoiceAction.pause => '⏸ Pausing',
      VoiceAction.resume => '▶ Resuming',
      VoiceAction.stop => '⏹ Stopping',
      VoiceAction.next => '⏭ Next track',
      VoiceAction.previous => '⏮ Previous track',
      VoiceAction.shuffle => '🔀 Shuffle',
      VoiceAction.repeat => '🔁 Repeat',
      VoiceAction.search => '🔍 Searching "${cmd.query}"',
      VoiceAction.favorite => '❤ Liked!',
      VoiceAction.volumeUp => '🔊 Volume up',
      VoiceAction.volumeDown => '🔉 Volume down',
      VoiceAction.none => 'Hmm, didn\'t catch that',
    };
  }

  @override
  void dispose() {
    widget.service.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _transcriptSub?.cancel();
    _commandSub?.cancel();
    _errorSub?.cancel();
    _listeningSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.service.cancel();
        Navigator.of(context).pop();
      },
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: GestureDetector(
              onTap: () {}, // absorb taps on the card itself
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      blurRadius: 40,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Pulsating Mic ──
                    AnimatedBuilder(
                      listenable: _pulseAnimation,
                      builder: (context, child) {
                        return _buildMicButton(_pulseAnimation.value);
                      },
                    ),
                    const SizedBox(height: 24),

                    // ── Status ──
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        _statusText,
                        key: ValueKey(_statusText),
                        style: TextStyle(
                          color: _hasResult
                              ? Colors.greenAccent
                              : Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Live transcript ──
                    if (_transcript.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.format_quote_rounded,
                              color: AppTheme.primary.withValues(alpha: 0.6),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _transcript,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Hint ──
                    Text(
                      'Try "Play Shape of You" or "Next song"',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicButton(double scale) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer pulse rings
          if (_isListening) ...[
            AnimatedBuilder(
              listenable: _waveController,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(120, 120),
                  painter: _WavePainter(
                    progress: _waveController.value,
                    color: AppTheme.primary,
                  ),
                );
              },
            ),
          ],
          // Glowing circle
          Transform.scale(
            scale: _isListening ? scale : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppTheme.primary,
                    AppTheme.primary.withValues(alpha: 0.6),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(
                      alpha: _isListening ? 0.5 : 0.2,
                    ),
                    blurRadius: _isListening ? 30 : 10,
                    spreadRadius: _isListening ? 5 : 0,
                  ),
                ],
              ),
              child: Icon(
                _hasResult
                    ? Icons.check_rounded
                    : _isListening
                        ? Icons.mic_rounded
                        : Icons.mic_off_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints expanding concentric rings from the mic centre.
class _WavePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 3; i++) {
      final t = ((progress + i / 3) % 1.0);
      final radius = 30 + t * 30;
      final paint = Paint()
        ..color = color.withValues(alpha: (1 - t) * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.progress != progress;
}

/// [AnimatedBuilder] is missing in some Flutter versions under that name;
/// this keeps us safe.
class AnimatedBuilder extends AnimatedWidget {
  final TransitionBuilder builder;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
  });

  Animation<double> get animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) => builder(context, null);
}
