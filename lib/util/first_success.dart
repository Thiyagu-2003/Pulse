import 'dart:async';

/// Completes with the first future that yields a non-null value.
///
/// Unlike [Future.any], a thrown error or a null result doesn't win the race —
/// it just drops out. Completes with null only once every future has failed,
/// so a fast failure never masks a slower success.
Future<T?> firstSuccess<T>(Iterable<Future<T?>> futures) {
  final pending = futures.toList();
  if (pending.isEmpty) return Future<T?>.value(null);

  final completer = Completer<T?>();
  var outstanding = pending.length;

  void settle(T? value) {
    outstanding--;
    if (completer.isCompleted) return;
    if (value != null) {
      completer.complete(value);
    } else if (outstanding == 0) {
      completer.complete(null);
    }
  }

  for (final future in pending) {
    future.then(settle, onError: (Object _) => settle(null));
  }

  return completer.future;
}
