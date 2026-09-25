import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../providers/music_player_provider.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';

enum EqPreset { flat, bassBoost, vocal, treble }

extension EqPresetLabel on EqPreset {
  String get label => switch (this) {
    EqPreset.flat => 'Flat',
    EqPreset.bassBoost => 'Bass boost',
    EqPreset.vocal => 'Vocal',
    EqPreset.treble => 'Treble',
  };
}

/// Gains (dB) for [preset], one per band, from each band's centre frequency
/// (Hz) — phones differ in how many bands they have and where.
List<double> presetGains(
  EqPreset preset,
  List<double> centers, {
  required double min,
  required double max,
}) => [
  for (final hz in centers)
    (switch (preset) {
      EqPreset.flat => 0.0,
      EqPreset.bassBoost => hz < 150 ? 6.0 : (hz < 400 ? 3.0 : 0.0),
      EqPreset.vocal => hz < 150 ? -2.0 : (hz >= 400 && hz <= 4000 ? 3.0 : 0.0),
      EqPreset.treble => hz >= 4000 ? 5.0 : (hz >= 2000 ? 2.0 : 0.0),
    }).clamp(min, max),
];

/// Settings > Equalizer: Android's own equalizer on the player, plus extra
/// loudness. Saved, and applied again on every start.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  // The phone's bands exist once the player has started.
  late final Future<AndroidEqualizerParameters>? _parameters =
      Platform.isAndroid
      ? context.read<MusicPlayerProvider>().audioHandler.equalizer.parameters
      : null;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final eq = provider.equalizerSettings;
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: _parameters == null
          ? const Center(child: Text('The equalizer needs Android.'))
          : FutureBuilder<AndroidEqualizerParameters>(
              future: _parameters.timeout(const Duration(seconds: 3)),
              builder: (context, snapshot) {
                final params = snapshot.data;
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Play a song first, then open the equalizer again.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (params == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildControls(provider, eq, params);
              },
            ),
    );
  }

  Widget _buildControls(
    MusicPlayerProvider provider,
    EqSettings eq,
    AndroidEqualizerParameters params,
  ) {
    final bands = params.bands;
    final gains = [
      for (var i = 0; i < bands.length; i++)
        i < eq.gains.length ? eq.gains[i] : 0.0,
    ];
    void save(EqSettings next) => provider.setEqualizer(next);

    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Equalizer'),
          value: eq.enabled,
          onChanged: (on) => save(eq.copyWith(enabled: on, gains: gains)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              for (final preset in EqPreset.values)
                ActionChip(
                  label: Text(preset.label),
                  onPressed: () => save(
                    eq.copyWith(
                      enabled: true,
                      gains: presetGains(
                        preset,
                        [for (final b in bands) b.centerFrequency],
                        min: params.minDecibels,
                        max: params.maxDecibels,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < bands.length; i++)
          ListTile(
            enabled: eq.enabled,
            leading: SizedBox(
              width: 64,
              child: Text(_hz(bands[i].centerFrequency)),
            ),
            title: Slider(
              value: gains[i].clamp(params.minDecibels, params.maxDecibels),
              min: params.minDecibels,
              max: params.maxDecibels,
              activeColor: AppTheme.primary,
              onChanged: eq.enabled
                  ? (v) => save(eq.copyWith(gains: [...gains]..[i] = v))
                  : null,
            ),
            trailing: SizedBox(
              width: 56,
              child: Text('${gains[i].toStringAsFixed(1)} dB'),
            ),
          ),
        const Divider(),
        ListTile(
          enabled: eq.enabled,
          title: const Text('Loudness boost'),
          subtitle: Slider(
            value: eq.loudness,
            max: 10,
            activeColor: AppTheme.primary,
            onChanged: eq.enabled
                ? (v) => save(eq.copyWith(loudness: v, gains: gains))
                : null,
          ),
          trailing: Text('+${eq.loudness.toStringAsFixed(1)} dB'),
        ),
      ],
    );
  }

  static String _hz(double hz) =>
      hz >= 1000 ? '${(hz / 1000).toStringAsFixed(1)} kHz' : '${hz.round()} Hz';
}
