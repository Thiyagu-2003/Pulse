import 'media_item_model.dart';
import 'playback_mode.dart';

/// The playback queue and the order it plays in.
///
/// Split out of MusicPlayerProvider so it can be unit tested: the provider
/// needs an initialized AudioService and Hive, this needs nothing.
///
/// Two lists are maintained together — [items] in display order, and [order],
/// a permutation of indices into it giving play order. Every edit has to keep
/// them consistent, which is what [isConsistent] asserts.
class QueueState {
  final List<AppMediaItem> _items = [];
  List<int> _order = [];
  int _currentIndex = -1;
  int _orderPos = -1;
  bool _shuffled = false;

  List<AppMediaItem> get items => List.unmodifiable(_items);
  int get currentIndex => _currentIndex;
  int get orderPos => _orderPos;
  bool get isShuffled => _shuffled;
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;

  AppMediaItem? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _items.length)
          ? _items[_currentIndex]
          : null;

  /// Replace the whole queue and make [track] current, adding it if the list
  /// somehow doesn't contain it.
  void replaceWith(List<AppMediaItem> tracks, AppMediaItem track) {
    _items
      ..clear()
      ..addAll(tracks);
    _currentIndex = _items.indexWhere((t) => t.id == track.id);
    if (_currentIndex == -1) {
      _items.insert(0, track);
      _currentIndex = 0;
    }
    _rebuildOrder();
  }

  /// Make [track] current. Appends it if it isn't queued yet — without
  /// reshuffling what's already lined up.
  void selectOrAppend(AppMediaItem track) {
    final existing = _items.indexWhere((t) => t.id == track.id);
    if (existing == -1) {
      _items.add(track);
      _currentIndex = _items.length - 1;
      _order.add(_currentIndex);
      _orderPos = _order.length - 1;
    } else {
      _currentIndex = existing;
      _orderPos = _order.indexOf(_currentIndex);
    }
  }

  /// Shuffle pins the current track to the front of the order, so turning it
  /// on doesn't jump away from what's playing.
  void setShuffled(bool value) {
    _shuffled = value;
    _rebuildOrder();
  }

  void _rebuildOrder() {
    _order = List.generate(_items.length, (i) => i);
    if (_shuffled) {
      _order.shuffle();
      if (_currentIndex >= 0) {
        final at = _order.indexOf(_currentIndex);
        if (at > 0) {
          _order[at] = _order[0];
          _order[0] = _currentIndex;
        }
      }
    }
    _orderPos = _currentIndex >= 0 ? _order.indexOf(_currentIndex) : -1;
  }

  /// Move a queue item. [from] and [to] are positions in the final list.
  void move(int from, int to) {
    if (from < 0 || from >= _items.length) return;
    if (to < 0 || to >= _items.length || from == to) return;

    _items.insert(to, _items.removeAt(from));
    _order = _order.map((i) => indexAfterMove(i, from, to)).toList();
    _currentIndex = indexAfterMove(_currentIndex, from, to);
    _orderPos = _order.indexOf(_currentIndex);
  }

  /// Remove a queue item. Returns true when the removed item was the one
  /// playing, so the caller knows it has to start something else.
  bool removeAt(int index) {
    if (index < 0 || index >= _items.length) return false;

    final wasCurrent = index == _currentIndex;
    _items.removeAt(index);
    _order = orderAfterRemoval(_order, index);

    if (index < _currentIndex) _currentIndex--;

    if (_items.isEmpty) {
      _currentIndex = -1;
      _orderPos = -1;
      return wasCurrent;
    }

    if (wasCurrent) {
      // _orderPos still points at the slot the removed track held, which now
      // holds whatever followed it. Clamp for a removal off the end.
      _orderPos = _orderPos.clamp(0, _order.length - 1);
      _currentIndex = _order[_orderPos];
    } else {
      _orderPos = _order.indexOf(_currentIndex);
    }
    return wasCurrent;
  }

  /// Make the queue row at [index] current. Tapping a row in the queue sheet
  /// must play *that* row, which a lookup by id can't promise.
  AppMediaItem? selectAt(int index) {
    if (index < 0 || index >= _items.length) return null;
    _currentIndex = index;
    _orderPos = _order.indexOf(index);
    return _items[index];
  }

  /// The queue never holds the same track twice: two copies both highlight as
  /// playing and make next/previous look broken. Removes an existing copy of
  /// [item] so it can be re-added; false when [item] is the track playing,
  /// where re-queueing it is a no-op.
  bool _dropExisting(AppMediaItem item) {
    final existing = _items.indexWhere((t) => t.id == item.id);
    if (existing == -1) return true;
    if (existing == _currentIndex) return false;
    removeAt(existing);
    return true;
  }

  /// Queue [item] directly after whatever is playing. False if it already is
  /// the track playing.
  bool insertNext(AppMediaItem item) {
    if (!_dropExisting(item)) return false;
    final insertAt = _currentIndex + 1;
    _items.insert(insertAt, item);
    _order = orderAfterInsertion(_order, insertAt);
    _order.insert(_orderPos + 1, insertAt);
    return true;
  }

  /// Queue [item] last. False if it is the track playing.
  bool append(AppMediaItem item) {
    if (!_dropExisting(item)) return false;
    _items.add(item);
    _order.add(_items.length - 1);
    return true;
  }

  /// Step to the next track, or null when playback should stop. [auto] marks
  /// a track that ended by itself rather than the user pressing next.
  AppMediaItem? advance({required QueueRepeat repeat, required bool auto}) {
    final next = nextPosition(
      position: _orderPos,
      length: _order.length,
      repeat: repeat,
      auto: auto,
    );
    if (next == null) return null;
    _orderPos = next;
    _currentIndex = _order[next];
    return _items[_currentIndex];
  }

  /// What would play next, without moving the cursor. Used to resolve the
  /// next stream URL ahead of time.
  AppMediaItem? peekNext({required QueueRepeat repeat}) {
    final next = nextPosition(
      position: _orderPos,
      length: _order.length,
      repeat: repeat,
      auto: false,
    );
    return next == null ? null : _items[_order[next]];
  }

  AppMediaItem? previous() {
    if (_order.isEmpty) return null;
    _orderPos = previousPosition(position: _orderPos, length: _order.length);
    _currentIndex = _order[_orderPos];
    return _items[_currentIndex];
  }

  /// The invariant every operation above must preserve: the play order is a
  /// permutation of the queue's indices, and the cursors agree.
  bool get isConsistent {
    if (_order.length != _items.length) return false;
    if (_order.toSet().length != _order.length) return false;
    if (_order.any((i) => i < 0 || i >= _items.length)) return false;

    if (_items.isEmpty) return _currentIndex == -1 && _orderPos == -1;
    if (_currentIndex < 0 || _currentIndex >= _items.length) return false;
    if (_orderPos < 0 || _orderPos >= _order.length) return false;
    return _order[_orderPos] == _currentIndex;
  }
}
