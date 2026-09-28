import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_item_model.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';

/// Before a playlist downloads: its name (editable, unless it's already one
/// of the user's playlists) and a checklist of its songs, all ticked — untick
/// the ones not wanted. Returns the name and the chosen songs, or null if
/// cancelled.
Future<(String, List<AppMediaItem>)?> showDownloadPlaylistSheet(
  BuildContext context, {
  required String name,
  required List<AppMediaItem> items,
  bool nameEditable = true,
}) {
  return showModalBottomSheet<(String, List<AppMediaItem>)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _DownloadPlaylistSheet(
      name: name,
      items: items.where((t) => t.sourceType.isOnline).toList(),
      nameEditable: nameEditable,
    ),
  );
}

class _DownloadPlaylistSheet extends StatefulWidget {
  final String name;
  final List<AppMediaItem> items;
  final bool nameEditable;

  const _DownloadPlaylistSheet({
    required this.name,
    required this.items,
    required this.nameEditable,
  });

  @override
  State<_DownloadPlaylistSheet> createState() => _DownloadPlaylistSheetState();
}

class _DownloadPlaylistSheetState extends State<_DownloadPlaylistSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final Set<String> _chosen = widget.items.map((t) => t.id).toSet();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicPlayerProvider>();
    final items = widget.items;
    final all = _chosen.length == items.length;
    final toDownload = items
        .where((t) => _chosen.contains(t.id) && !provider.isDownloaded(t.id))
        .length;
    final name = _name.text.trim();

    return Padding(
      // Above the keyboard while the name is being edited.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Download playlist',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (widget.nameEditable)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Playlist and folder name',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              CheckboxListTile(
                title: Text('${_chosen.length} of ${items.length} songs'),
                value: all,
                activeColor: AppTheme.primary,
                controlAffinity: ListTileControlAffinity.leading,
                onChanged: (_) => setState(() {
                  if (all) {
                    _chosen.clear();
                  } else {
                    _chosen.addAll(items.map((t) => t.id));
                  }
                }),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final song = items[i];
                    final done = provider.isDownloaded(song.id);
                    return CheckboxListTile(
                      value: _chosen.contains(song.id),
                      activeColor: AppTheme.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        done ? 'Downloaded · ${song.artist}' : song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (on) => setState(() {
                        if (on == true) {
                          _chosen.add(song.id);
                        } else {
                          _chosen.remove(song.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      toDownload == 0
                          ? 'Save playlist'
                          : 'Download $toDownload '
                                '${toDownload == 1 ? 'song' : 'songs'}',
                    ),
                    onPressed: _chosen.isEmpty || name.isEmpty
                        ? null
                        : () => Navigator.pop(context, (
                            _name.text.trim(),
                            [
                              for (final t in items)
                                if (_chosen.contains(t.id)) t,
                            ],
                          )),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
