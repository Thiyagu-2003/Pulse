// Playback and queue-order rules, kept free of Flutter and plugin imports so
// they can be unit tested without an initialized AudioService or Hive.
//
// The provider keeps the queue (display order) and a play order of indices
// into it. Every queue edit therefore has to rewrite those indices, which is
// exactly the bookkeeping that is easy to get subtly wrong — so it lives here,
// as pure functions, rather than inline in the provider.
//
// Named QueueRepeat rather than RepeatMode because Flutter's material.dart
// already exports a RepeatMode.

enum QueueRepeat { off, all, one }

/// The next slot in the play order, or null when playback should stop.
///
/// [position] and [length] index the *play order*, not the queue — under
/// shuffle those differ.
///
/// [auto] distinguishes a track that ended by itself from the user pressing
/// next. The difference matters at both ends of the list: a finished queue
/// should stop rather than loop forever, but the next button always wraps;
/// and repeat-one replays only on completion, since pressing next while
/// repeat-one is on obviously means "give me a different track".
int? nextPosition({
  required int position,
  required int length,
  required QueueRepeat repeat,
  required bool auto,
}) {
  if (length <= 0) return null;
  if (position < 0) return 0;

  if (auto && repeat == QueueRepeat.one) return position;

  final next = position + 1;
  if (next < length) return next;

  // Ran off the end.
  if (auto && repeat == QueueRepeat.off) return null;
  return 0;
}

/// Where the queue index [index] ends up once the item at [from] is moved to
/// [to]. Items between the two positions shift by one to fill the gap.
int indexAfterMove(int index, int from, int to) {
  if (index < 0 || from == to) return index;
  if (index == from) return to;
  if (from < to && index > from && index <= to) return index - 1;
  if (from > to && index >= to && index < from) return index + 1;
  return index;
}

/// A play order rewritten after the queue item at [removedAt] is deleted:
/// references to it disappear and every later index shifts down one.
List<int> orderAfterRemoval(List<int> order, int removedAt) => order
    .where((i) => i != removedAt)
    .map((i) => i > removedAt ? i - 1 : i)
    .toList();

/// A play order rewritten after a new queue item is inserted at [insertedAt].
/// The new item is not itself added to the order — the caller decides where it
/// should play, which differs between "play next" and "add to queue".
List<int> orderAfterInsertion(List<int> order, int insertedAt) =>
    order.map((i) => i >= insertedAt ? i + 1 : i).toList();

/// Whether a stored playback position is worth resuming from.
///
/// A position near the start isn't worth restoring, and one near the end means
/// the track was effectively finished — resuming there would drop the listener
/// straight into the outro.
bool shouldResume({
  required Duration saved,
  Duration? total,
  Duration threshold = const Duration(seconds: 10),
}) {
  if (saved < threshold) return false;
  if (total != null && total > Duration.zero && saved > total - threshold) {
    return false;
  }
  return true;
}

/// The previous slot in the play order. Always wraps: this is only ever
/// reached by an explicit button press.
int previousPosition({required int position, required int length}) {
  if (length <= 0) return 0;
  if (position < 0) return 0;
  return (position - 1 + length) % length;
}
