import 'media_item_model.dart';

/// A user-created playlist.
///
/// Stores whole [AppMediaItem]s rather than track ids: a playlist entry has to
/// survive the source it came from disappearing (a YouTube search result is
/// not in any local library), so there is nothing to join back to.
class Playlist {
  final String id;
  final String name;
  final List<AppMediaItem> items;

  const Playlist({
    required this.id,
    required this.name,
    this.items = const [],
  });

  int get length => items.length;

  bool contains(String trackId) => items.any((t) => t.id == trackId);

  Playlist copyWith({String? name, List<AppMediaItem>? items}) => Playlist(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
      );

  /// Adding a track already in the playlist is a no-op rather than a
  /// duplicate — re-tapping "add to playlist" should be harmless.
  Playlist withItem(AppMediaItem item) =>
      contains(item.id) ? this : copyWith(items: [...items, item]);

  Playlist withoutItem(String trackId) =>
      copyWith(items: items.where((t) => t.id != trackId).toList());

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((t) => t.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        items: (json['items'] as List?)
                ?.map((t) => AppMediaItem.fromJson(t as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}
