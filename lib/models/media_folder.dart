import 'media_item_model.dart';

/// A device folder of local audio, e.g. Music, Recordings, Call recordings.
///
/// Android's media store returns every audio file on the device in one flat
/// list — voice memos and call recordings sit right next to albums. Grouping
/// by the containing directory is what separates them, because that is how
/// the recorder apps already separate them on disk.
class MediaFolder {
  /// Full directory path, used as the identity.
  final String path;
  final List<AppMediaItem> items;

  const MediaFolder({required this.path, required this.items});

  int get length => items.length;

  /// Last path segment — "Recordings" out of "/storage/emulated/0/Recordings".
  String get name {
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.isEmpty ? path : segments.last;
  }

  /// Folders holding recordings rather than music. Used only to sort them
  /// below music and pick an icon — nothing is ever hidden, since one
  /// person's voice memos are another's field recordings.
  bool get isRecordings {
    final lower = name.toLowerCase();
    return lower.contains('record') ||
        lower.contains('voice') ||
        lower.contains('call') ||
        lower.contains('memo') ||
        lower.contains('sound') && lower.contains('rec');
  }
}

/// The directory containing [track], or null if its path is unknown.
///
/// Local tracks carry their file path in extras; streamed ones have none.
String? folderPathOf(AppMediaItem track) {
  final raw = (track.extras?['filePath'] as String?) ?? track.streamUrl;
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('content://') || raw.startsWith('http')) return null;

  final normalized = raw.replaceAll('\\', '/');
  final cut = normalized.lastIndexOf('/');
  if (cut <= 0) return null;
  return normalized.substring(0, cut);
}

/// Group tracks by containing folder.
///
/// Music folders come first, then recording folders, each alphabetically —
/// so opening the Local tab shows albums rather than a wall of call logs.
/// Tracks with no resolvable path are collected under [unknownFolderLabel].
const String unknownFolderLabel = 'Other';

List<MediaFolder> groupByFolder(List<AppMediaItem> tracks) {
  final buckets = <String, List<AppMediaItem>>{};

  for (final track in tracks) {
    final path = folderPathOf(track) ?? unknownFolderLabel;
    buckets.putIfAbsent(path, () => []).add(track);
  }

  final folders = buckets.entries
      .map((entry) => MediaFolder(path: entry.key, items: entry.value))
      .toList();

  folders.sort((a, b) {
    if (a.isRecordings != b.isRecordings) return a.isRecordings ? 1 : -1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return folders;
}
