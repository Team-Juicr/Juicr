import 'package:flutter/material.dart';

import 'app_state.dart';
import 'catalog_item.dart';
import 'juicr_bottom_sheet.dart';
import 'library_lists_section.dart';
import 'visual_style.dart';

enum DetailsSaveMenuAction { addToList, toggleSaved }

class DetailsSaveMenuSheet extends StatelessWidget {
  const DetailsSaveMenuSheet({
    super.key,
    required this.item,
    required this.saved,
  });

  final CatalogItem item;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: JuicrVisual.bottomSheetTopBorderRadius,
      ),
      child: Padding(
        padding: juicrBottomSheetPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<List<LibraryList>>(
              valueListenable: AppState.libraryLists,
              builder: (context, lists, _) {
                return DetailsSheetActionTile(
                  icon: Icons.bookmark_add_outlined,
                  title: 'Add to List',
                  subtitle: lists.isEmpty
                      ? 'Create a list for this title.'
                      : 'Choose one of your lists.',
                  onTap: () => Navigator.of(
                    context,
                  ).pop(DetailsSaveMenuAction.addToList),
                );
              },
            ),
            const SizedBox(height: 10),
            DetailsSheetActionTile(
              icon: saved
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              title: saved
                  ? 'Remove from ${item.type.pluralLabel}'
                  : 'Save to ${item.type.pluralLabel}',
              subtitle: saved
                  ? 'Remove this title from your saved library.'
                  : 'Keep this title in your saved library.',
              selected: saved,
              onTap: () =>
                  Navigator.of(context).pop(DetailsSaveMenuAction.toggleSaved),
            ),
          ],
        ),
      ),
    );
  }
}

class ListPickerSheet extends StatefulWidget {
  const ListPickerSheet({super.key, required this.item});

  final CatalogItem item;

  @override
  State<ListPickerSheet> createState() => ListPickerSheetState();
}

class ListPickerSheetState extends State<ListPickerSheet> {
  bool _creating = false;

  void _createList(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = AppState.createLibraryList(trimmed, initialItem: widget.item);
    if (!mounted) return;
    setState(() => _creating = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('Added ${widget.item.name} to ${list.name}')),
      );
  }

  void _toggleList(BuildContext context, LibraryList list) {
    final wasInList = list.itemIds.contains(widget.item.id);
    AppState.toggleItemInLibraryList(list.id, widget.item);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasInList
                ? 'Removed ${widget.item.name} from ${list.name}'
                : 'Added ${widget.item.name} to ${list.name}',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ValueListenableBuilder<List<LibraryList>>(
      valueListenable: AppState.libraryLists,
      builder: (context, lists, _) {
        return SingleChildScrollView(
          padding: juicrBottomSheetPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to List',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              if (_creating)
                InlineCreateListCard(
                  onCancel: () => setState(() => _creating = false),
                  onCreate: _createList,
                )
              else
                DetailsSheetActionTile(
                  icon: Icons.add_rounded,
                  title: 'Create new list',
                  subtitle: 'Make a list and add this title.',
                  onTap: () => setState(() => _creating = true),
                ),
              if (lists.isEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'No lists yet. Create one to organize this title.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.66),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                for (final list in lists)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DetailsSheetActionTile(
                      icon: Icons.bookmark_border_rounded,
                      title: list.name,
                      subtitle:
                          '${list.itemIds.length} ${list.itemIds.length == 1 ? 'title' : 'titles'}',
                      selected: list.itemIds.contains(widget.item.id),
                      onTap: () => _toggleList(context, list),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class DetailsSheetActionTile extends StatelessWidget {
  const DetailsSheetActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.18)
          : JuicrVisual.flatCardColor(colorScheme),
      borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? colorScheme.primary : colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.66),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 10),
                Icon(Icons.check_rounded, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class InlineCreateListCard extends StatefulWidget {
  const InlineCreateListCard({
    super.key,
    required this.onCancel,
    required this.onCreate,
  });

  final VoidCallback onCancel;
  final ValueChanged<String> onCreate;

  @override
  State<InlineCreateListCard> createState() => InlineCreateListCardState();
}

class InlineCreateListCardState extends State<InlineCreateListCard> {
  String _draftName = '';

  @override
  Widget build(BuildContext context) {
    return LibraryCreateListForm(
      draftName: _draftName,
      onChanged: (value) => setState(() => _draftName = value),
      onCancel: widget.onCancel,
      onCreate: () => widget.onCreate(_draftName),
    );
  }
}
