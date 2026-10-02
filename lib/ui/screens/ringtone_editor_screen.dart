import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../../services/ringtone_service.dart';
import '../theme/app_theme.dart';
import '../widgets/track_tile.dart';

/// Full-screen ringtone editor with waveform visualisation, draggable
/// start / end markers, and a preview button.  The user picks a segment
/// of any song and sets it as ringtone, notification or alarm sound.
class RingtoneEditorScreen extends StatefulWidget {
  final AppMediaItem item;

  const RingtoneEditorScreen({super.key, required this.item});

  @override
  State<RingtoneEditorScreen> createState() => _RingtoneEditorScreenState();
}

class _RingtoneEditorScreenState extends State<RingtoneEditorScreen>
    with TickerProviderStateMixin {
  final RingtoneService _ringtoneService = RingtoneService();

  // ── Loading state ───────────────────────────────────────────────────
  bool _loading = true;
  String _loadingMessage = 'Preparing audio…';
  String? _error;

  // ── Audio ───────────────────────────────────────────────────────────
  String? _filePath;
  Duration _totalDuration = Duration.zero;

  // ── Trim markers (in milliseconds) ──────────────────────────────────
  int _startMs = 0;
  int _endMs = 30000; // Default: first 30 seconds
  static const int _minClipMs = 1000; // At least 1 second

  // ── Waveform ────────────────────────────────────────────────────────
  List<double> _waveformSamples = [];

  // ── Preview playback ────────────────────────────────────────────────
  bool _isPreviewing = false;
  StreamSubscription? _positionSub;
  StreamSubscription? _playerStateSub;
  Duration _previewPosition = Duration.zero;

  // ── Setting ringtone ────────────────────────────────────────────────
  bool _setting = false;
  RingtoneType _selectedType = RingtoneType.ringtone;

  // ── Animations ──────────────────────────────────────────────────────
  late final AnimationController _fadeIn;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<MusicPlayerProvider>().pause();
      }
    });
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _prepare();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _ringtoneService.disposePreview();
    _fadeIn.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Prepare file + waveform ─────────────────────────────────────────

  Future<void> _prepare() async {
    try {
      setState(() => _loadingMessage = 'Resolving audio source…');

      _filePath = await _ringtoneService.resolveFilePath(widget.item);
      if (_filePath == null) {
        setState(() {
          _error = 'Could not resolve the audio file for this track.';
          _loading = false;
        });
        return;
      }

      setState(() => _loadingMessage = 'Analysing waveform…');

      // Load the file into the preview player to get its duration.
      final player = _ringtoneService.previewPlayer;
      final duration = await player.setFilePath(_filePath!);
      _totalDuration = duration ?? widget.item.duration ?? Duration.zero;

      // Default clip: first 30s or total duration if shorter.
      _startMs = 0;
      _endMs = math.min(_totalDuration.inMilliseconds, 30000);
      if (_endMs - _startMs < _minClipMs) {
        _endMs = math.min(_totalDuration.inMilliseconds, _minClipMs);
      }
      _previewPosition = Duration(milliseconds: _startMs);

      // Generate a pseudo-waveform from the file.
      await _generateWaveform();

      // Listen to position for the preview highlight.
      _positionSub = player.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _previewPosition = pos);
        // Stop at the end marker and reset seek position back to startMs.
        if (_isPreviewing && pos.inMilliseconds >= _endMs) {
          player.pause();
          player.seek(Duration(milliseconds: _startMs));
          setState(() {
            _isPreviewing = false;
            _previewPosition = Duration(milliseconds: _startMs);
          });
        }
      });

      _playerStateSub = player.playerStateStream.listen((state) {
        if (!mounted) return;
        if (state.processingState == ProcessingState.completed) {
          player.seek(Duration(milliseconds: _startMs));
          setState(() {
            _isPreviewing = false;
            _previewPosition = Duration(milliseconds: _startMs);
          });
        }
      });

      setState(() => _loading = false);
      _fadeIn.forward();
    } catch (e) {
      debugPrint('RingtoneEditor._prepare: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to prepare audio: $e';
          _loading = false;
        });
      }
    }
  }

  /// Build a visual waveform approximation. For real PCM, we'd need an
  /// FFI decode, which is expensive. Instead, read a chunk of the file
  /// and sample the byte values to produce an envelope that visually
  /// resembles a waveform. Good enough for a trimmer UI.
  Future<void> _generateWaveform() async {
    const sampleCount = 200;
    try {
      final file = File(_filePath!);
      final length = await file.length();
      final raf = await file.open();

      // Skip the first 4 KB (header / metadata).
      final skipBytes = math.min(4096, length ~/ 10);
      final usableLength = length - skipBytes;
      final bucketSize = math.max(1, usableLength ~/ sampleCount);

      final samples = <double>[];
      for (var i = 0; i < sampleCount; i++) {
        final offset = skipBytes + (i * bucketSize);
        if (offset >= length) break;
        await raf.setPosition(offset);
        final chunk = await raf.read(math.min(bucketSize, 512));
        if (chunk.isEmpty) break;

        // Average of absolute byte values, normalised to 0–1.
        double sum = 0;
        for (final b in chunk) {
          sum += (b - 128).abs(); // treat as unsigned centred on 128
        }
        samples.add((sum / chunk.length) / 128.0);
      }
      await raf.close();

      // Normalise so the tallest bar is 1.0.
      final maxVal = samples.fold<double>(0, math.max);
      if (maxVal > 0) {
        for (var i = 0; i < samples.length; i++) {
          samples[i] = samples[i] / maxVal;
        }
      }

      _waveformSamples = samples;
    } catch (e) {
      debugPrint('Waveform generation failed: $e');
      // Fall back to random-looking bars so the UI isn't empty.
      final rng = math.Random(widget.item.id.hashCode);
      _waveformSamples =
          List.generate(sampleCount, (_) => 0.2 + rng.nextDouble() * 0.8);
    }
  }

  // ── Preview ─────────────────────────────────────────────────────────

  Future<void> _togglePreview() async {
    final player = _ringtoneService.previewPlayer;
    if (_isPreviewing) {
      await player.pause();
      setState(() => _isPreviewing = false);
      return;
    }
    if (mounted) {
      final mainPlayer = context.read<MusicPlayerProvider>();
      if (mainPlayer.isPlaying) {
        await mainPlayer.pause();
      }
    }
    // Always seek strictly to _startMs so preview plays smoothly every time.
    await player.seek(Duration(milliseconds: _startMs));
    setState(() {
      _previewPosition = Duration(milliseconds: _startMs);
      _isPreviewing = true;
    });
    await player.play();
  }

  void _updateTrim(int start, int end) {
    final totalMs = _totalDuration.inMilliseconds;
    if (totalMs <= 0) return;

    final minClip = math.min(_minClipMs, totalMs);
    var s = start.clamp(0, totalMs);
    var e = end.clamp(0, totalMs);

    if (e - s < minClip) {
      if (s != _startMs) {
        e = math.min(totalMs, s + minClip);
        s = math.max(0, e - minClip);
      } else {
        s = math.max(0, e - minClip);
        e = math.min(totalMs, s + minClip);
      }
    }

    setState(() {
      _startMs = s;
      _endMs = e;
      _previewPosition = Duration(milliseconds: _startMs);
    });

    _ringtoneService.previewPlayer.seek(Duration(milliseconds: _startMs));
  }

  void _adjustStart(int deltaMs) {
    if (_isPreviewing) {
      _ringtoneService.previewPlayer.pause();
      setState(() => _isPreviewing = false);
    }
    _updateTrim(_startMs + deltaMs, _endMs);
  }

  void _adjustEnd(int deltaMs) {
    if (_isPreviewing) {
      _ringtoneService.previewPlayer.pause();
      setState(() => _isPreviewing = false);
    }
    _updateTrim(_startMs, _endMs + deltaMs);
  }

  void _applyPreset(double startFraction, double durationFraction) {
    final totalMs = _totalDuration.inMilliseconds;
    if (totalMs <= 0) return;
    if (_isPreviewing) {
      _ringtoneService.previewPlayer.pause();
      setState(() => _isPreviewing = false);
    }
    final s = (startFraction * totalMs).round().clamp(0, totalMs);
    final d = (durationFraction * totalMs).round().clamp(_minClipMs, totalMs);
    final e = (s + d).clamp(0, totalMs);
    _updateTrim(s, e);
  }

  // ── Set ringtone ────────────────────────────────────────────────────

  Future<void> _setRingtone() async {
    if (_filePath == null || _setting) return;
    setState(() => _setting = true);

    // Check WRITE_SETTINGS permission.
    final hasPerm = await _ringtoneService.hasWriteSettingsPermission();
    if (!hasPerm) {
      if (!mounted) return;
      final shouldRequest = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.settings_rounded,
                  color: AppTheme.accent, size: 24),
              const SizedBox(width: 8),
              const Text('Permission needed',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.mist)),
            ],
          ),
          content: Text(
            'Pulse needs the "Modify system settings" permission to '
            'change your ringtone. You\'ll be taken to the settings screen.',
            style: TextStyle(
                color: AppTheme.mist.withValues(alpha: 0.70), fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: TextStyle(
                      color: AppTheme.mist.withValues(alpha: 0.60))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (shouldRequest == true) {
        await _ringtoneService.requestWriteSettingsPermission();
      }
      setState(() => _setting = false);
      return;
    }

    // Stop preview.
    if (_isPreviewing) {
      await _ringtoneService.previewPlayer.pause();
      setState(() => _isPreviewing = false);
    }

    final success = await _ringtoneService.setAsRingtone(
      filePath: _filePath!,
      title: widget.item.title,
      artist: widget.item.artist,
      startMs: _startMs,
      endMs: _endMs,
      type: _selectedType,
    );

    setState(() => _setting = false);

    if (!mounted) return;
    if (success) {
      showCompactSnack(
        ScaffoldMessenger.of(context),
        '${_typeLabel(_selectedType)} set: ${widget.item.title}',
        icon: Icons.check_circle_rounded,
      );
      Navigator.pop(context);
    } else {
      showCompactSnack(
        ScaffoldMessenger.of(context),
        'Could not set ${_typeLabel(_selectedType).toLowerCase()}',
        icon: Icons.error_outline_rounded,
        error: true,
      );
    }
  }

  String _typeLabel(RingtoneType type) => switch (type) {
        RingtoneType.ringtone => 'Ringtone',
        RingtoneType.notification => 'Notification tone',
        RingtoneType.alarm => 'Alarm tone',
      };

  IconData _typeIcon(RingtoneType type) => switch (type) {
        RingtoneType.ringtone => Icons.ring_volume_rounded,
        RingtoneType.notification => Icons.notifications_rounded,
        RingtoneType.alarm => Icons.alarm_rounded,
      };

  String _formatDuration(int ms) {
    final m = (ms ~/ 60000).toString().padLeft(2, '0');
    final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ────────────────────────────────────────────────────────────────────
  //  BUILD
  // ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (_isPreviewing) {
          _ringtoneService.previewPlayer.pause();
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('Set as Ringtone'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              if (_isPreviewing) {
                _ringtoneService.previewPlayer.pause();
              }
              Navigator.pop(context);
            },
          ),
        ),
        body: _loading
            ? _buildLoading(colors)
            : _error != null
                ? _buildError(colors)
                : FadeTransition(
                    opacity: _fadeIn,
                    child: _buildEditor(colors),
                  ),
      ),
    );
  }

  // ── Loading ─────────────────────────────────────────────────────────

  Widget _buildLoading(PulseColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Icon(
              Icons.music_note_rounded,
              size: 64,
              color: AppTheme.primary
                  .withValues(alpha: 0.4 + _pulseController.value * 0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(_loadingMessage,
              style: TextStyle(color: colors.mist.withValues(alpha: 0.7))),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: LinearProgressIndicator(
              color: AppTheme.primary,
              backgroundColor: colors.lift,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error ───────────────────────────────────────────────────────────

  Widget _buildError(PulseColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 56),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.mist.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  // ── Editor ──────────────────────────────────────────────────────────

  Widget _buildEditor(PulseColors colors) {
    final totalMs = _totalDuration.inMilliseconds;
    if (totalMs <= 0) return _buildError(colors);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─ Track info ──────────────────────────────────────────────
          _buildTrackInfo(colors),
          const SizedBox(height: 20),

          // ─ Waveform with interactive tap/scrub ──────────────────────
          _buildWaveformSection(colors, totalMs),
          const SizedBox(height: 14),

          // ─ Preset shortcuts ────────────────────────────────────────
          _buildPresets(colors, totalMs),
          const SizedBox(height: 16),

          // ─ Fine-tune controls & timestamps ─────────────────────────
          _buildFineTuneControls(colors),
          const SizedBox(height: 16),

          // ─ Range slider ────────────────────────────────────────────
          _buildRangeSlider(colors, totalMs),
          const SizedBox(height: 20),

          // ─ Preview button ──────────────────────────────────────────
          _buildPreviewButton(colors),
          const SizedBox(height: 24),

          // ─ Type selector ───────────────────────────────────────────
          _buildTypeSelector(colors),
          const SizedBox(height: 24),

          // ─ Set button ──────────────────────────────────────────────
          _buildSetButton(colors),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Track info card ─────────────────────────────────────────────────

  Widget _buildTrackInfo(PulseColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.lift.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: AppTheme.waveGradient,
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.mist,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.mist.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Waveform (Interactive) ─────────────────────────────────────────

  Widget _buildWaveformSection(PulseColors colors, int totalMs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (totalMs <= 0 || width <= 0) return;
            if (_isPreviewing) {
              _ringtoneService.previewPlayer.pause();
              setState(() => _isPreviewing = false);
            }
            final tapFraction =
                (details.localPosition.dx / width).clamp(0.0, 1.0);
            final tapMs = (tapFraction * totalMs).round();

            final startX = (_startMs / totalMs) * width;
            final endX = (_endMs / totalMs) * width;

            if ((details.localPosition.dx - startX).abs() < 24) {
              _adjustStart(tapMs - _startMs);
            } else if ((details.localPosition.dx - endX).abs() < 24) {
              _adjustEnd(tapMs - _endMs);
            } else {
              final clipLen = math.max(_minClipMs, _endMs - _startMs);
              _updateTrim(tapMs, (tapMs + clipLen).clamp(0, totalMs));
            }
          },
          child: Container(
            height: 135,
            decoration: BoxDecoration(
              color: colors.lift.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _WaveformPainter(
                  samples: _waveformSamples,
                  startFraction: totalMs > 0 ? _startMs / totalMs : 0.0,
                  endFraction: totalMs > 0 ? _endMs / totalMs : 1.0,
                  playheadFraction: _isPreviewing && totalMs > 0
                      ? _previewPosition.inMilliseconds / totalMs
                      : -1,
                  primaryColor: AppTheme.primary,
                  accentColor: AppTheme.accent,
                  dimColor: colors.mist.withValues(alpha: 0.12),
                  selectedColor: AppTheme.primarySoft,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Quick Presets ───────────────────────────────────────────────────

  Widget _buildPresets(PulseColors colors, int totalMs) {
    if (totalMs <= 0) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _presetChip(
            'Intro 30s',
            () => _applyPreset(0.0, 30000 / totalMs),
            colors,
          ),
          const SizedBox(width: 8),
          _presetChip(
            'Chorus / Mid',
            () => _applyPreset(0.35, 30000 / totalMs),
            colors,
          ),
          const SizedBox(width: 8),
          _presetChip(
            'Ending 30s',
            () {
              if (_isPreviewing) {
                _ringtoneService.previewPlayer.pause();
                setState(() => _isPreviewing = false);
              }
              final s = math.max(0, totalMs - 30000);
              _updateTrim(s, totalMs);
            },
            colors,
          ),
          const SizedBox(width: 8),
          _presetChip(
            'Full Song',
            () {
              if (_isPreviewing) {
                _ringtoneService.previewPlayer.pause();
                setState(() => _isPreviewing = false);
              }
              _updateTrim(0, totalMs);
            },
            colors,
          ),
        ],
      ),
    );
  }

  Widget _presetChip(String label, VoidCallback onTap, PulseColors colors) {
    return ActionChip(
      label: Text(label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      backgroundColor: colors.lift.withValues(alpha: 0.6),
      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.25)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onTap,
    );
  }

  // ── Fine-Tune Controls ──────────────────────────────────────────────

  Widget _buildFineTuneControls(PulseColors colors) {
    final clipSec = ((_endMs - _startMs) / 1000).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.lift.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Start adjustment
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'START: ${_formatDuration(_startMs)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepBtn('-1s', () => _adjustStart(-1000), colors),
                  const SizedBox(width: 6),
                  _stepBtn('+1s', () => _adjustStart(1000), colors),
                ],
              ),
            ],
          ),
          // Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$clipSec s',
              style: const TextStyle(
                color: AppTheme.primarySoft,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          // End adjustment
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'END: ${_formatDuration(_endMs)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _stepBtn('-1s', () => _adjustEnd(-1000), colors),
                  const SizedBox(width: 6),
                  _stepBtn('+1s', () => _adjustEnd(1000), colors),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepBtn(String text, VoidCallback onTap, PulseColors colors) {
    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.mist)),
      ),
    );
  }

  // ── Range slider ────────────────────────────────────────────────────

  Widget _buildRangeSlider(PulseColors colors, int totalMs) {
    if (totalMs <= 0) return const SizedBox.shrink();

    final maxVal = math.max(1000.0, totalMs.toDouble());
    final minClip = math.min(_minClipMs.toDouble(), maxVal);

    double safeStart = _startMs.toDouble().clamp(0.0, maxVal);
    double safeEnd = _endMs.toDouble().clamp(0.0, maxVal);

    if (safeEnd - safeStart < minClip) {
      if (safeStart + minClip <= maxVal) {
        safeEnd = safeStart + minClip;
      } else {
        safeStart = math.max(0.0, maxVal - minClip);
        safeEnd = maxVal;
      }
    }

    if (safeStart < 0.0) safeStart = 0.0;
    if (safeEnd > maxVal) safeEnd = maxVal;
    if (safeStart > safeEnd) safeStart = safeEnd;

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            rangeThumbShape:
                const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
            rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: colors.mist.withValues(alpha: 0.1),
            thumbColor: AppTheme.accent,
            overlayColor: AppTheme.accent.withValues(alpha: 0.15),
            rangeValueIndicatorShape:
                const PaddleRangeSliderValueIndicatorShape(),
            valueIndicatorColor: AppTheme.primary,
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            showValueIndicator: ShowValueIndicator.onDrag,
          ),
          child: RangeSlider(
            values: RangeValues(safeStart, safeEnd),
            min: 0,
            max: maxVal,
            divisions: math.max(1, totalMs ~/ 500),
            labels: RangeLabels(
              _formatDuration(_startMs),
              _formatDuration(_endMs),
            ),
            onChangeStart: (_) async {
              if (_isPreviewing) {
                await _ringtoneService.previewPlayer.pause();
                setState(() => _isPreviewing = false);
              }
            },
            onChanged: (values) {
              _updateTrim(values.start.round(), values.end.round());
            },
            onChangeEnd: (_) async {
              await _ringtoneService.previewPlayer
                  .seek(Duration(milliseconds: _startMs));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0:00',
                  style: TextStyle(
                      color: colors.mist.withValues(alpha: 0.3),
                      fontSize: 11)),
              Text(_formatDuration(totalMs),
                  style: TextStyle(
                      color: colors.mist.withValues(alpha: 0.3),
                      fontSize: 11)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Preview button ──────────────────────────────────────────────────

  Widget _buildPreviewButton(PulseColors colors) {
    return Center(
      child: GestureDetector(
        onTap: _togglePreview,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: _isPreviewing
                  ? [AppTheme.accent, AppTheme.accentGlow]
                  : [AppTheme.primary, AppTheme.primarySoft],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: (_isPreviewing ? AppTheme.accent : AppTheme.primary)
                    .withValues(alpha: 0.35),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            _isPreviewing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }

  // ── Type selector ───────────────────────────────────────────────────

  Widget _buildTypeSelector(PulseColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'SET AS',
            style: TextStyle(
              color: colors.mist.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Row(
          children: RingtoneType.values.map((type) {
            final selected = _selectedType == type;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: type != RingtoneType.alarm ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.18)
                          : colors.lift.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppTheme.primary.withValues(alpha: 0.6)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _typeIcon(type),
                          color: selected
                              ? AppTheme.primarySoft
                              : colors.mist.withValues(alpha: 0.4),
                          size: 22,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _typeLabel(type),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected
                                ? colors.mist
                                : colors.mist.withValues(alpha: 0.45),
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Set button ──────────────────────────────────────────────────────

  Widget _buildSetButton(PulseColors colors) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: _setting ? null : _setRingtone,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _setting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_typeIcon(_selectedType), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Set as ${_typeLabel(_selectedType)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  WAVEFORM PAINTER
// ════════════════════════════════════════════════════════════════════════

class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final double startFraction;
  final double endFraction;
  final double playheadFraction;
  final Color primaryColor;
  final Color accentColor;
  final Color dimColor;
  final Color selectedColor;

  _WaveformPainter({
    required this.samples,
    required this.startFraction,
    required this.endFraction,
    required this.playheadFraction,
    required this.primaryColor,
    required this.accentColor,
    required this.dimColor,
    required this.selectedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final barWidth = size.width / samples.length;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * 0.42;

    // ─ Selection background ──────────────────────────────────────────
    final s = math.min(startFraction, endFraction).clamp(0.0, 1.0);
    final e = math.max(startFraction, endFraction).clamp(0.0, 1.0);
    final selStart = s * size.width;
    final selEnd = e * size.width;
    final selPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(selStart, 0, selEnd, size.height),
        const Radius.circular(4),
      ),
      selPaint,
    );

    // ─ Bars ──────────────────────────────────────────────────────────
    for (var i = 0; i < samples.length; i++) {
      final x = i * barWidth;
      final fraction = x / size.width;
      final inSelection =
          fraction >= startFraction && fraction <= endFraction;
      final barH = math.max(2.0, samples[i] * maxBarHeight);

      final paint = Paint()
        ..color = inSelection ? selectedColor : dimColor
        ..style = PaintingStyle.fill
        ..strokeCap = StrokeCap.round;

      final barRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: math.max(1.5, barWidth - 1.5),
          height: barH * 2,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(barRect, paint);
    }

    // ─ Start / end markers ───────────────────────────────────────────
    final markerPaint = Paint()
      ..color = accentColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(selStart, 0), Offset(selStart, size.height), markerPaint);
    canvas.drawLine(Offset(selEnd, 0), Offset(selEnd, size.height), markerPaint);

    // Marker dots.
    final dotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(selStart, centerY), 5, dotPaint);
    canvas.drawCircle(Offset(selEnd, centerY), 5, dotPaint);

    // ─ Playhead ──────────────────────────────────────────────────────
    if (playheadFraction >= 0) {
      final px = playheadFraction * size.width;
      final playPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), playPaint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.startFraction != startFraction ||
      old.endFraction != endFraction ||
      old.playheadFraction != playheadFraction;
}
