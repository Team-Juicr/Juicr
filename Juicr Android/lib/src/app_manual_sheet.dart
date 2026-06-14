import 'package:flutter/material.dart';

import 'juicr_bottom_sheet.dart';
import 'visual_style.dart';

Future<void> showAppManualSheet(BuildContext context) {
  return showJuicrBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: JuicrVisual.bottomSheetShape,
    builder: (context) => const AppManualSheet(),
  );
}

class AppManualSheet extends StatelessWidget {
  const AppManualSheet({super.key});

  static const _sections = <_ManualSection>[
    _ManualSection(
      icon: Icons.flag_rounded,
      title: 'Start here',
      body:
          'Juicr helps you browse, save, resume, and play from sources you choose. Start with Home or Discovery, open a title, then use Details to save it, watch it, or find related titles.',
    ),
    _ManualSection(
      icon: Icons.home_rounded,
      title: 'Home',
      body:
          'Home is the calm front page. It shows daily picks, trending shelves, top lists, saved items, and upcoming titles when those are available. Tap a poster to open Details. Swipe shelves sideways to see more.',
    ),
    _ManualSection(
      icon: Icons.explore_rounded,
      title: 'Discovery',
      body:
          'Discovery is for searching and filtering. Pick a type, sort, year, genre, origin, or language. If a filter shows fewer titles than expected, clear one filter at a time and search again.',
    ),
    _ManualSection(
      icon: Icons.info_outline_rounded,
      title: 'Details',
      body:
          'Details shows the title, artwork, metadata, description, genres, recommendations, and available actions. Use Watch to play, Trailer to preview when available, and Library to save or organize the title.',
    ),
    _ManualSection(
      icon: Icons.smart_display_rounded,
      title: 'Playback',
      body:
          'The in-app player has play or pause, back and forward skip, sources, settings, screen cast, picture-in-picture, and lock controls. Swipe up or down on the left side for brightness and on the right side for volume.',
    ),
    _ManualSection(
      icon: Icons.skip_next_rounded,
      title: 'Skip recap, intro, and outro',
      body:
          'When timing is available, Juicr can show a skip button for recap, intro, or outro segments. In Playback settings, Auto-skip can do this for you. If no trusted timing exists, Juicr leaves playback alone.',
    ),
    _ManualSection(
      icon: Icons.favorite_rounded,
      title: 'Library',
      body:
          'Library keeps Continue, Lists, Movies, Series, Animation, Live TV, saved favorites, completed items, metrics, and ranking surfaces. Use Lists when you want your own watchlists instead of one big saved pile.',
    ),
    _ManualSection(
      icon: Icons.extension_rounded,
      title: 'Add-ons and sources',
      body:
          'Add-ons are optional tools you choose to import or enable. Only use add-ons you trust. Juicr keeps private configuration out of normal screens and diagnostics where possible.',
    ),
    _ManualSection(
      icon: Icons.dns_rounded,
      title: 'Personal servers',
      body:
          'Personal servers connect your own library. Add the server details in Settings, then use the personal server lane for your media. If catalog results look incomplete, refresh the server and try the matching search.',
    ),
    _ManualSection(
      icon: Icons.person_rounded,
      title: 'Account and sync',
      body:
          'Signing in can keep supported library changes, watch time, and account-backed settings in sync. If a change reappears after deleting it, wait for sync to finish and try again from the device with the newest changes.',
    ),
    _ManualSection(
      icon: Icons.battery_charging_full_rounded,
      title: 'Battery and data',
      body:
          'Battery & data settings help keep playback gentle on the device. Use saver mode for lighter browsing, Wi-Fi only for heavier playback features, and background controls when you want playback cleanup to be stricter.',
    ),
    _ManualSection(
      icon: Icons.settings_rounded,
      title: 'General settings',
      body:
          'General controls theme, accent, text size, layout density, motion, haptics, start page, status messages, system bars, and the portrait lock for browsing screens.',
    ),
    _ManualSection(
      icon: Icons.update_rounded,
      title: 'Updates',
      body:
          'Updates checks the current release channel, shows the latest changelog, and can open the release page when an update is available. Stable builds follow stable releases; nightly builds follow nightly releases.',
    ),
    _ManualSection(
      icon: Icons.bug_report_outlined,
      title: 'About and diagnostics',
      body:
          'About shows app information, safe quick links, diagnostics, reports, and credits. Diagnostic reports are meant for support and keep private playback, source, and account details out of shared reports.',
    ),
    _ManualSection(
      icon: Icons.help_outline_rounded,
      title: 'When something feels stuck',
      body:
          'Try closing the sheet, clearing the filter, refreshing the title, or switching playback options. If the issue repeats, copy or send a diagnostic report from About & diagnostics so support can see safe evidence.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          10,
          18,
          JuicrVisual.bottomSheetBottomBreathingRoom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Juicr guide',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'A simple manual for the main things Juicr can do.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.66),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return _ManualExpansionTile(section: _sections[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualExpansionTile extends StatelessWidget {
  const _ManualExpansionTile({required this.section});

  final _ManualSection section;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(60, 0, 14, 14),
        leading: JuicrVisual.iconBadge(
          context,
          icon: section.icon,
          boxSize: 38,
          iconSize: 18,
          radius: 14,
          shadowAlpha: 0.1,
        ),
        title: Text(
          section.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        iconColor: colorScheme.primary,
        collapsedIconColor: colorScheme.onSurface.withValues(alpha: 0.7),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              section.body,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualSection {
  const _ManualSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
