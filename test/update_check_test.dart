import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/update_service.dart';

void main() {
  test('versions compare number by number', () {
    expect(UpdateService.isNewer('v1.10.0', '1.9.2'), isTrue);
    expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    expect(UpdateService.isNewer('v1.0.0', '1.0.0'), isFalse);
    expect(UpdateService.isNewer('0.9', '1.0.0'), isFalse);
    expect(UpdateService.isNewer('', '1.0.0'), isFalse);
  });

  test('a newer release offers its APK', () {
    final update = UpdateService.fromRelease({
      'tag_name': 'v1.2.0',
      'body': 'Autoplay and more',
      'html_url': 'https://github.com/x/releases/v1.2.0',
      'assets': [
        {'browser_download_url': 'https://github.com/x/notes.txt'},
        {'browser_download_url': 'https://github.com/x/app-armeabi-v7a-release.apk'},
        {'browser_download_url': 'https://github.com/x/app-arm64-v8a-release.apk'},
      ],
    }, current: '1.0.0');
    expect(update!.version, '1.2.0');
    expect(update.url, 'https://github.com/x/app-arm64-v8a-release.apk');
    expect(UpdateService.fromRelease({'tag_name': 'v1.0.0'}, current: '1.0.0'),
        isNull);
  });
}
