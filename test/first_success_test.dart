import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/util/first_success.dart';

Future<T> after<T>(int ms, T value) =>
    Future.delayed(Duration(milliseconds: ms), () => value);

Future<T> failsAfter<T>(int ms) =>
    Future.delayed(Duration(milliseconds: ms), () => throw StateError('nope'));

void main() {
  test('returns the first non-null result', () async {
    final result = await firstSuccess([after(80, 'slow'), after(10, 'fast')]);
    expect(result, 'fast');
  });

  test('a fast failure does not beat a slower success', () async {
    // The whole reason this exists instead of Future.any: NewPipe failing
    // instantly must not stop youtube_explode from being used.
    final result = await firstSuccess<String>([
      failsAfter(10),
      after(60, 'worked'),
    ]);
    expect(result, 'worked');
  });

  test('a fast null does not beat a slower success', () async {
    final result = await firstSuccess<String>([
      after(10, null),
      after(60, 'worked'),
    ]);
    expect(result, 'worked');
  });

  test('returns null only once everything has failed', () async {
    final result = await firstSuccess<String>([
      after(10, null),
      failsAfter(20),
      after(30, null),
    ]);
    expect(result, isNull);
  });

  test('an empty list resolves to null rather than hanging', () async {
    expect(await firstSuccess<String>([]), isNull);
  });

  test('a single success and a single failure both resolve', () async {
    expect(await firstSuccess([after(5, 'only')]), 'only');
    expect(await firstSuccess<String>([failsAfter(5)]), isNull);
  });

  test('later failures after a win do not throw', () async {
    final result = await firstSuccess<String>([
      after(5, 'winner'),
      failsAfter(40),
    ]);
    expect(result, 'winner');
    // Let the loser settle; an unhandled rejection here would fail the test.
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });
}
