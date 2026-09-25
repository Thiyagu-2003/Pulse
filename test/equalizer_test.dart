import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/storage_service.dart';
import 'package:music_player/ui/screens/equalizer_screen.dart';

void main() {
  // A typical phone's five bands.
  const centers = [60.0, 230.0, 910.0, 3600.0, 14000.0];

  test('presets shape the bands by frequency, within the phone limits', () {
    expect(presetGains(EqPreset.flat, centers, min: -15, max: 15),
        [0, 0, 0, 0, 0]);
    expect(presetGains(EqPreset.bassBoost, centers, min: -15, max: 15),
        [6, 3, 0, 0, 0]);
    expect(presetGains(EqPreset.vocal, centers, min: -15, max: 15),
        [-2, 0, 3, 3, 0]);
    expect(presetGains(EqPreset.treble, centers, min: -15, max: 15),
        [0, 0, 0, 2, 5]);
    expect(presetGains(EqPreset.bassBoost, centers, min: -3, max: 3),
        [3, 3, 0, 0, 0]);
  });

  test('settings survive a round trip, and a damaged one is ignored', () {
    const eq = EqSettings(enabled: true, gains: [1.5, -2], loudness: 4);
    final back = EqSettings.fromJson(eq.toJson());
    expect([back.enabled, back.gains, back.loudness], [true, [1.5, -2], 4]);
    expect(EqSettings.fromJson({'gains': [3]}).enabled, isFalse);
  });
}
