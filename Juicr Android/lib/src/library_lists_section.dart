import 'package:flutter/material.dart';

import 'app_state.dart';
import 'catalog_item.dart';
import 'motion.dart';
import 'visual_style.dart';

typedef LibraryImageCacheWidthBuilder =
    int Function(BuildContext context, double logicalWidth);
typedef LibraryListItemBuilder =
    Widget Function(BuildContext context, CatalogItem item, int index);

class LibraryCreateListSheet extends StatelessWidget {
  const LibraryCreateListSheet({
    super.key,
    required this.draftName,
    required this.onChanged,
    required this.onCancel,
    required this.onCreate,
  });

  final String draftName;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Create list',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
        LibraryCreateListForm(
          draftName: draftName,
          onChanged: onChanged,
          onCancel: onCancel,
          onCreate: onCreate,
        ),
      ],
    );
  }
}

class LibraryCreateListForm extends StatelessWidget {
  const LibraryCreateListForm({
    super.key,
    required this.draftName,
    required this.onChanged,
    required this.onCancel,
    required this.onCreate,
  });

  final String draftName;
  final ValueChanged<String> onChanged;
  final VoidCallback onCancel;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final canCreate = draftName.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          autofocus: true,
          maxLength: 48,
          textInputAction: TextInputAction.done,
          onChanged: onChanged,
          onSubmitted: (_) {
            if (canCreate) onCreate();
          },
          decoration: const InputDecoration(
            labelText: 'List name',
            hintText: 'Weekend picks',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            const Spacer(),
            FilledButton(
              onPressed: canCreate ? onCreate : null,
              child: const Text('Create'),
            ),
          ],
        ),
      ],
    );
  }
}

class LibraryListsGrid extends StatelessWidget {
  const LibraryListsGrid({
    super.key,
    required this.lists,
    required this.onCreate,
    required this.onRename,
    required this.onDelete,
    required this.imageCacheWidthBuilder,
    required this.itemBuilder,
  });

  final List<LibraryList> lists;
  final VoidCallback onCreate;
  final ValueChanged<LibraryList> onRename;
  final ValueChanged<LibraryList> onDelete;
  final LibraryImageCacheWidthBuilder imageCacheWidthBuilder;
  final LibraryListItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compactLandscape ? 5 : 3,
        crossAxisSpacing: compactLandscape ? 8 : 12,
        mainAxisSpacing: compactLandscape ? 8 : 12,
        childAspectRatio: 2 / 3,
      ),
      itemCount: lists.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return CreateLibraryListTile(onTap: onCreate);
        }
        final list = lists[index - 1];
        return LibraryListTile(
          list: list,
          imageCacheWidthBuilder: imageCacheWidthBuilder,
          itemBuilder: itemBuilder,
          onRename: () => onRename(list),
          onDelete: () => onDelete(list),
        );
      },
    );
  }
}

class CreateLibraryListTile extends StatelessWidget {
  const CreateLibraryListTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compactLandscape = JuicrVisual.compactLandscape(context);
    return Material(
      color: JuicrVisual.flatCardColor(colorScheme),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: compactLandscape ? 36 : 46,
              height: compactLandscape ? 36 : 46,
              decoration: JuicrVisual.elevatedIconDecoration(
                colorScheme,
                radius: compactLandscape ? 11 : 13,
                shadowAlpha: 0.08,
                glowAlpha: 0.09,
              ),
              child: Icon(
                Icons.add_rounded,
                color: colorScheme.primary,
                size: compactLandscape ? 21 : 24,
              ),
            ),
            SizedBox(height: compactLandscape ? 8 : 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Create new list',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryListTile extends StatelessWidget {
  const LibraryListTile({
    super.key,
    required this.list,
    required this.imageCacheWidthBuilder,
    required this.itemBuilder,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryList list;
  final LibraryImageCacheWidthBuilder imageCacheWidthBuilder;
  final LibraryListItemBuilder itemBuilder;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = AppState.itemsForLibraryList(list);
    final preview = items.take(3).toList(growable: false);
    return Material(
      color: JuicrVisual.flatCardColor(colorScheme),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            AppPageRoute<void>(
              builder: (_) => LibraryCustomListPage(
                listId: list.id,
                itemBuilder: itemBuilder,
              ),
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (preview.isEmpty)
              Center(
                child: Icon(
                  Icons.bookmarks_outlined,
                  color: colorScheme.primary,
                  size: 32,
                ),
              )
            else
              Row(
                children: [
                  for (final item in preview)
                    Expanded(
                      child: item.poster == null
                          ? ColoredBox(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.7),
                              child: Icon(
                                Icons.movie_outlined,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.38,
                                ),
                              ),
                            )
                          : Image.network(
                              item.poster!,
                              fit: BoxFit.cover,
                              cacheWidth: imageCacheWidthBuilder(context, 120),
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.38,
                                  ),
                                ),
                              ),
                            ),
                    ),
                ],
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: PopupMenuButton<String>(
                tooltip: 'List options',
                icon: const Icon(Icons.more_vert_rounded, size: 18),
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    list.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${list.itemIds.length} ${list.itemIds.length == 1 ? 'title' : 'titles'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LibraryCustomListPage extends StatelessWidget {
  const LibraryCustomListPage({
    super.key,
    required this.listId,
    required this.itemBuilder,
  });

  final String listId;
  final LibraryListItemBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LibraryList>>(
      valueListenable: AppState.libraryLists,
      builder: (context, lists, _) {
        LibraryList? list;
        for (final candidate in lists) {
          if (candidate.id == listId) {
            list = candidate;
            break;
          }
        }
        if (list == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('List')),
            body: const Center(child: Text('This list was deleted.')),
          );
        }
        final currentList = list;
        final items = AppState.itemsForLibraryList(currentList);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Text(currentList.name),
            actions: [
              IconButton(
                tooltip: 'Delete list',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete list?'),
                      content: Text(
                        'This deletes "${currentList.name}" but keeps saved titles.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true || !context.mounted) return;
                  AppState.deleteLibraryList(currentList.id);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: items.isEmpty
              ? const Center(child: Text('No titles in this list yet.'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    return itemBuilder(context, items[index], index);
                  },
                ),
        );
      },
    );
  }
}
