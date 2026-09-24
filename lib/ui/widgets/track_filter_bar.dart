import 'package:flutter/material.dart';
import '../../models/track_query.dart';
import '../theme/app_theme.dart';

/// Search field with an optional sort menu, shared by the Local and Library
/// screens. Omit [sort] to hide the sort control — history is chronological
/// and reordering it would destroy the only thing it means.
class TrackFilterBar extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String hintText;
  final TrackSort? sort;
  final ValueChanged<TrackSort>? onSortChanged;

  const TrackFilterBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    this.hintText = 'Search title, artist, album...',
    this.sort,
    this.onSortChanged,
  });

  @override
  State<TrackFilterBar> createState() => _TrackFilterBarState();
}

class _TrackFilterBarState extends State<TrackFilterBar> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(TrackFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only resync when the query changed from outside (a clear button, a tab
    // switch). Assigning during typing would fight the cursor.
    if (widget.query != _controller.text) {
      _controller.text = widget.query;
      _controller.selection =
          TextSelection.collapsed(offset: widget.query.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.query;
    final sort = widget.sort;
    final onQueryChanged = widget.onQueryChanged;
    final onSortChanged = widget.onSortChanged;
    final hintText = widget.hintText;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.mist.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.mist.withValues(alpha: 0.10)),
              ),
              child: TextField(
                controller: _controller,
                style: TextStyle(color: context.colors.mist),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hintText,
                  hintStyle: TextStyle(color: context.colors.mist.withValues(alpha: 0.38), fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: context.colors.accent, size: 20),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, color: context.colors.mist.withValues(alpha: 0.38), size: 18),
                          onPressed: () => onQueryChanged(''),
                        ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: onQueryChanged,
              ),
            ),
          ),
          if (sort != null && onSortChanged != null) ...[
            const SizedBox(width: 8),
            PopupMenuButton<TrackSort>(
              icon: Icon(Icons.sort_rounded, color: context.colors.accent),
              tooltip: 'Sort by ${sort.label}',
              color: context.colors.surface,
              initialValue: sort,
              onSelected: onSortChanged,
              itemBuilder: (_) => [
                for (final option in TrackSort.values)
                  PopupMenuItem(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          option == sort
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: option == sort ? context.colors.accent : context.colors.mist.withValues(alpha: 0.38),
                        ),
                        const SizedBox(width: 10),
                        Text(option.label),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
