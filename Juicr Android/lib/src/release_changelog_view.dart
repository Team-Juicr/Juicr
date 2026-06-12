import 'package:flutter/material.dart';

class ReleaseChangelogView extends StatelessWidget {
  const ReleaseChangelogView({required this.body, super.key});

  final String body;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entries = _parseReleaseChangelog(body);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          if (entry.isSection)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                entry.text,
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '• ${entry.text}',
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.78),
                  height: 1.12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ReleaseChangelogEntry {
  const _ReleaseChangelogEntry.section(this.text) : isSection = true;

  const _ReleaseChangelogEntry.bullet(this.text) : isSection = false;

  final String text;
  final bool isSection;
}

List<_ReleaseChangelogEntry> _parseReleaseChangelog(String body) {
  final entries = <_ReleaseChangelogEntry>[];
  for (final rawLine in body.split('\n')) {
    var line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      line = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    }
    final bulletMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(line);
    if (bulletMatch != null) {
      final bullet = bulletMatch.group(1)?.trim() ?? '';
      if (bullet.isNotEmpty) entries.add(_ReleaseChangelogEntry.bullet(bullet));
      continue;
    }
    final numberedMatch = RegExp(r'^\d+[.)]\s+(.+)$').firstMatch(line);
    if (numberedMatch != null) {
      final bullet = numberedMatch.group(1)?.trim() ?? '';
      if (bullet.isNotEmpty) entries.add(_ReleaseChangelogEntry.bullet(bullet));
      continue;
    }
    entries.add(_ReleaseChangelogEntry.section(line));
  }
  return entries;
}
