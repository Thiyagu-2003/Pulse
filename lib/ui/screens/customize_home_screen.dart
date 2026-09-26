import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/home_sections.dart';
import '../../providers/music_player_provider.dart';
import '../theme/app_theme.dart';

/// Arrange the Online home page: drag sections into any order, switch them
/// on or off, add rows of your own, or go back to the standard page.
/// Changes apply as they're made.
class CustomizeHomeScreen extends StatelessWidget {
  const CustomizeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MusicPlayerProvider>();
    final layout = provider.homeLayout;
    final sections =
        arrangeHome(provider.homeLanguage, layout,
            includeHidden: true, personal: provider.madeForYouSections);

    Future<void> save(HomeLayout next) => provider.setHomeLayout(next);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customize home'),
        actions: [
          TextButton(
            onPressed: () => save(HomeLayout.standard),
            child: const Text('Reset'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add section'),
        onPressed: () async {
          final title = await _askForTitle(context);
          if (title == null) return;
          await save(layout.copyWith(
            custom: [
              ...layout.custom,
              ('custom_${DateTime.now().millisecondsSinceEpoch}', title),
            ],
          ));
        },
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 96),
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Text(
            'Drag to reorder. Switch off what you don\'t want. '
            '"Add section" makes a row from any artist, film or mood.',
            style: TextStyle(color: context.colors.mist.withValues(alpha: 0.6)),
          ),
        ),
        itemCount: sections.length,
        onReorder: (from, to) {
          if (from < to) to -= 1;
          final ids = sections.map((s) => s.id).toList();
          ids.insert(to, ids.removeAt(from));
          save(layout.copyWith(order: ids));
        },
        itemBuilder: (context, i) {
          final section = sections[i];
          final visible = !layout.hidden.contains(section.id);
          return ListTile(
            key: ValueKey(section.id),
            leading: ReorderableDragStartListener(
              index: i,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
            title: Text(
              section.title,
              style: TextStyle(
                color: visible
                    ? context.colors.mist
                    : context.colors.mist.withValues(alpha: 0.4),
              ),
            ),
            subtitle: Text(_describe(section)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section.custom)
                  IconButton(
                    tooltip: 'Remove section',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => save(layout.copyWith(
                      custom: layout.custom
                          .where((c) => c.$1 != section.id)
                          .toList(),
                      order: layout.order
                          .where((id) => id != section.id)
                          .toList(),
                    )),
                  ),
                Switch(
                  value: visible,
                  onChanged: (on) => save(layout.copyWith(
                    hidden: on
                        ? ({...layout.hidden}..remove(section.id))
                        : {...layout.hidden, section.id},
                  )),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _describe(HomeSection s) => switch (s.style) {
        HomeSectionStyle.recent => 'Your recently played songs',
        HomeSectionStyle.cards => 'Playlist cards',
        HomeSectionStyle.rows => s.custom
            ? 'Your section'
            : s.id.startsWith('foryou')
                ? 'Made for you, from what you play'
                : 'Songs',
      };

  static Future<String?> _askForTitle(BuildContext context) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Yuvan Shankar Raja, Vikram, Rainy day',
          ),
          onSubmitted: (v) => Navigator.pop(dialogContext, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    // Disposed after the dialog's closing animation has let go of it.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    final trimmed = title?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
