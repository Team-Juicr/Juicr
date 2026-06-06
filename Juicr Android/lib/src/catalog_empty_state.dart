import 'package:flutter/material.dart';

import 'app_state.dart';
import 'visual_style.dart';

class CatalogEmptyState extends StatelessWidget {
  const CatalogEmptyState({
    super.key,
    this.searching = false,
    this.filtered = false,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final bool searching;
  final bool filtered;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pageTitle = title;
    final filterEmpty = searching || filtered;
    final emptyTitle = searching
        ? 'No titles matched that search.'
        : filtered
        ? 'No titles matched those filters.'
        : 'Juicr opened successfully.';
    final emptySubtitle = message?.trim().isNotEmpty == true
        ? message!.trim()
        : searching
        ? 'Try a different title, genre, or year.'
        : filtered
        ? 'Try another year, genre, origin, or sort.'
        : 'No sources are enabled yet. Fresh installs start empty until you choose what to connect.';
    final hasCustomAction =
        actionLabel?.trim().isNotEmpty == true && onAction != null;
    return Stack(
      children: [
        if (pageTitle != null && pageTitle.isNotEmpty)
          Positioned(
            left: JuicrVisual.topLevelTitleSpacing,
            top: JuicrVisual.topLevelEmptyTitleTop,
            child: Text(
              pageTitle,
              style: Theme.of(context).appBarTheme.titleTextStyle,
            ),
          ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  filterEmpty ? Icons.search_off : Icons.extension_rounded,
                  size: 46,
                  color: colorScheme.onSurface.withValues(alpha: 0.54),
                ),
                const SizedBox(height: 12),
                Text(
                  emptyTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  emptySubtitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasCustomAction) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(actionLabel!.trim()),
                  ),
                ] else if (!filterEmpty) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: AppState.openAddOnsSettings,
                    icon: const Icon(Icons.extension_rounded),
                    label: const Text('Set up add-ons'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Juicr does not provide media. You choose what to connect.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
