import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'local_notification_bridge.dart';
import 'stream_api.dart';
import 'system_ui.dart';

class NotificationOrchestrator {
  NotificationOrchestrator({
    required StreamApi api,
    required GlobalKey<NavigatorState> navigatorKey,
  }) : _api = api,
       _navigatorKey = navigatorKey;

  final StreamApi _api;
  final GlobalKey<NavigatorState> _navigatorKey;
  bool _running = false;
  bool _dialogShowing = false;
  int _interstitialContextRetryCount = 0;

  Future<void> check({required String reason}) async {
    if (_running || !AppState.preferencesReady.value) return;
    _running = true;
    try {
      await LocalNotificationBridge.syncSettings(
        notificationsEnabled: AppState.notificationsEnabled.value,
        metricsEnabled: false,
        dialogsEnabled: AppState.notificationDialogsEnabled.value,
        interstitialsEnabled: false,
      );
      final policy = await _api.notificationPolicy();
      if (policy == null || !policy.enabled) {
        DiagnosticLog.add('notification check skipped reason=policy_off');
        return;
      }
      final editorial = await _api.homeEditorial();
      if (editorial == null) {
        DiagnosticLog.add('notification editorial skipped reason=fetch_failed');
        return;
      }
      final dailyDelivered = await _handleDailyCuration(policy, editorial);
      if (!dailyDelivered) {
        DiagnosticLog.add(
          'notification synced surface skipped reason=not_ready',
        );
      }
      DiagnosticLog.add('notification check complete reason=$reason');
    } finally {
      _running = false;
    }
  }

  Future<bool> _handleSavedAvailability(NotificationPolicy policy) async {
    if (!policy.automatic.enabled ||
        !AppState.notificationsEnabled.value ||
        _insideQuietHours(policy.automatic.quietHours)) {
      return false;
    }
    final savedUpcoming = AppState.library.value.values
        .where((item) => item.isUpcoming && !item.type.isLive)
        .take(6)
        .toList(growable: false);
    if (savedUpcoming.isEmpty) {
      DiagnosticLog.add('saved availability skipped reason=no_upcoming_saved');
      return false;
    }
    for (final item in savedUpcoming) {
      final campaignId =
          'available:${item.type.compatTypeValue}:${item.tmdbId ?? item.id}';
      if (AppState.hasSeenNotificationCampaign(campaignId)) continue;
      try {
        final details = await _api
            .meta(item)
            .timeout(const Duration(seconds: 4));
        final freshItem = details.item;
        if (freshItem.isUpcoming) continue;
        final title = 'Now available!';
        final safeTitle = _safeNotificationCopy(
          freshItem.name,
          fallback: 'A saved title',
        );
        final message = '$safeTitle is ready to watch.';
        var shown = false;
        if (AppState.notificationDialogsEnabled.value &&
            policy.controls.allows('dialog')) {
          shown = await _showCards(
            title: 'New on Juicr',
            subtitle: 'A saved title just landed.',
            cards: [
              _NotificationCard(
                key: _notificationCardKey(freshItem, freshItem.type),
                title: safeTitle,
                subtitle: 'Ready to watch',
                imageUrl: freshItem.background ?? freshItem.poster,
                type: freshItem.type,
                sort: CatalogSort.top,
                genre: freshItem.genres.isEmpty
                    ? 'All genres'
                    : freshItem.genres.first,
              ),
            ],
          );
        }
        if (!shown && policy.controls.allows('notification')) {
          shown = await _showLocalNotification(
            title: title,
            message: message,
            id: 12010,
            dailyCap: policy.automatic.dailyCap,
          );
        }
        if (!shown) continue;
        await AppState.markNotificationCampaignSeen(campaignId);
        DiagnosticLog.add(
          'saved availability shown type=${freshItem.type.compatTypeValue}',
        );
        return true;
      } catch (error) {
        DiagnosticLog.add(
          'saved availability skipped reason=metadata_unavailable type=${item.type.compatTypeValue}',
        );
      }
    }
    DiagnosticLog.add('saved availability skipped reason=no_ready_titles');
    return false;
  }

  Future<bool> _handleDailyCuration(
    NotificationPolicy policy,
    HomeEditorialEdition editorial,
  ) async {
    if (!policy.automatic.enabled ||
        !policy.automatic.dailyCurationEnabled ||
        !AppState.notificationsEnabled.value ||
        _insideQuietHours(policy.automatic.quietHours)) {
      DiagnosticLog.add('daily curation skipped reason=gated');
      return false;
    }
    final dialogAlreadyShown =
        AppState.hasShownCurationDialogToday() ||
        AppState.lastCurationDialogEdition() == editorial.editionId;
    if (dialogAlreadyShown) {
      DiagnosticLog.add('daily curation skipped reason=already_delivered');
      return false;
    }
    final preview = await _dailyCurationPreview(editorial);
    if (preview == null) {
      DiagnosticLog.add('daily curation skipped reason=preview_empty');
      return false;
    }
    var shown = false;
    if (!dialogAlreadyShown &&
        AppState.notificationDialogsEnabled.value &&
        policy.controls.allows('dialog')) {
      shown = await _showCards(
        title: preview.title,
        subtitle: preview.message,
        cards: preview.cards,
        onPresented: () async {
          await AppState.markCurationDialogShownToday();
          await AppState.setLastCurationDialogEdition(editorial.editionId);
        },
      );
    }
    if (shown) {
      DiagnosticLog.add('notification daily surface delivered');
      return true;
    } else {
      DiagnosticLog.add('daily curation skipped reason=not_delivered');
      return false;
    }
  }

  Future<void> _handleInterstitialCards(
    NotificationPolicy policy,
    HomeEditorialEdition editorial,
  ) async {
    if (!policy.interstitial.enabled ||
        !policy.automatic.enabled ||
        !policy.automatic.interstitialCardsEnabled ||
        !AppState.notificationDialogsEnabled.value) {
      DiagnosticLog.add('interstitial cards skipped reason=gated');
      return;
    }
    final last = AppState.lastNotificationInterstitialAt();
    if (last != null &&
        DateTime.now().difference(last).inHours <
            policy.interstitial.minHoursBetweenShows) {
      DiagnosticLog.add('interstitial cards skipped reason=cooldown');
      return;
    }
    final cards = await _curationCards(editorial, policy.interstitial.maxCards);
    if (cards.isEmpty) {
      DiagnosticLog.add('interstitial cards skipped reason=empty');
      return;
    }
    final shown = await _showCards(
      title: 'New on Juicr',
      subtitle: 'Fresh picks and timely updates.',
      cards: cards,
    );
    if (shown) {
      _interstitialContextRetryCount = 0;
      await AppState.setLastNotificationInterstitialAt(DateTime.now());
    } else {
      DiagnosticLog.add('interstitial cards skipped reason=not_presented');
      _retryWhenContextReady(
        reason: 'interstitial_context',
        counter: _interstitialContextRetryCount,
        onCounter: (value) => _interstitialContextRetryCount = value,
      );
    }
  }

  Future<bool> _showLocalNotification({
    required String title,
    required String message,
    required int id,
    required int dailyCap,
  }) async {
    final cap = dailyCap <= 0 ? 1 : dailyCap;
    if (AppState.notificationDailyCount() >= cap) {
      DiagnosticLog.add('local notification skipped reason=daily_cap');
      return false;
    }
    var enabled = await LocalNotificationBridge.areEnabled();
    if (!enabled) enabled = await LocalNotificationBridge.requestPermission();
    if (!enabled) {
      DiagnosticLog.add('local notification skipped reason=permission');
      return false;
    }
    final shown = await LocalNotificationBridge.show(
      id: id,
      title: title,
      message: message,
    );
    if (shown) await AppState.recordNotificationDelivery();
    DiagnosticLog.add(
      'local notification ${shown ? 'shown' : 'skipped'} id=$id',
    );
    return shown;
  }

  Future<bool> _showCards({
    required String title,
    required String subtitle,
    required List<_NotificationCard> cards,
    Future<void> Function()? onPresented,
  }) async {
    if (_dialogShowing) {
      DiagnosticLog.add('notification cards skipped reason=dialog_active');
      return false;
    }
    if (juicrImmersiveSessionActive) {
      DiagnosticLog.add('notification cards skipped reason=immersive_player');
      return false;
    }
    final context = _navigatorKey.currentContext;
    if (context == null) {
      DiagnosticLog.add(
        'notification cards skipped reason=context_unavailable',
      );
      return false;
    }
    if (cards.isEmpty) return false;
    _dialogShowing = true;
    try {
      await onPresented?.call();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _NotificationCardDialog(
          title: title,
          subtitle: subtitle,
          cards: cards,
        ),
      );
      DiagnosticLog.add('notification cards surface_shown');
      return true;
    } finally {
      _dialogShowing = false;
    }
  }

  Future<List<_NotificationCard>> _curationCards(
    HomeEditorialEdition editorial,
    int maxCards,
  ) async {
    final rails = [
      editorial.hero,
      editorial.todaySignal,
      editorial.movie,
      editorial.series,
      editorial.animation,
    ];
    final cards = <_NotificationCard>[];
    final seenKeys = <String>{};
    for (final rail in rails) {
      final genre = rail.genres.isNotEmpty ? rail.genres.first : 'All genres';
      final items = await _curationItemsForRail(rail);
      for (final item in items) {
        final cardKey = _notificationCardKey(item, item.type);
        if (!seenKeys.add(cardKey)) {
          DiagnosticLog.add('notification card skipped reason=duplicate');
          continue;
        }
        cards.add(
          _NotificationCard(
            key: cardKey,
            title: _safeNotificationCopy(item.name, fallback: 'Fresh pick'),
            subtitle: _contentMomentLabel(rail),
            imageUrl: item.background ?? item.poster,
            type: item.type,
            sort: rail.sort,
            genre: genre,
          ),
        );
        if (cards.length >= maxCards) break;
      }
      if (cards.length >= maxCards) break;
    }
    return cards;
  }

  Future<_DailyCurationPreview?> _dailyCurationPreview(
    HomeEditorialEdition editorial,
  ) async {
    final rail = editorial.hero;
    final items = await _curationItemsForRail(rail);
    if (items.length < _minimumNotificationCurationItems) return null;
    final firstTwo = items
        .take(2)
        .map((item) => _safeNotificationCopy(item.name, fallback: 'Fresh pick'))
        .toList();
    final title = _dailyCurationTitleFromRail(rail);
    final hook = _dailyCurationHook(rail);
    final message =
        '${firstTwo.join(', ')} and more. ${_safeNotificationCopy(hook, fallback: 'Fresh picks are ready when you are.')}';
    final genre = rail.genres.isNotEmpty ? rail.genres.first : 'All genres';
    final type = rail.types.isNotEmpty ? rail.types.first : items.first.type;
    final cards = [
      for (final item in items.take(10))
        _NotificationCard(
          key: _notificationCardKey(item, item.type),
          title: _safeNotificationCopy(item.name, fallback: 'Fresh pick'),
          subtitle: _contentMomentLabel(rail),
          imageUrl: item.background ?? item.poster,
          type: item.type,
          sort: rail.sort,
          genre: genre,
        ),
    ];
    return _DailyCurationPreview(title: title, message: message, cards: cards);
  }

  Future<List<CatalogItem>> _curationItemsForRail(
    HomeEditorialRail rail,
  ) async {
    final genre = rail.genres.isNotEmpty ? rail.genres.first : null;
    final type = rail.types.isNotEmpty ? rail.types.first : MediaType.movie;
    return _catalogPreviewBucket(
      type: type,
      rail: rail,
      genre: genre,
      limit: rail.limit,
    );
  }

  Future<List<CatalogItem>> _catalogPreviewBucket({
    required MediaType type,
    required HomeEditorialRail rail,
    required String? genre,
    required int limit,
  }) async {
    final gathered = <CatalogItem>[];
    final seenKeys = <String>{};
    var skip = 0;
    final maxPages = _notificationPreviewMaxPages(rail);
    try {
      for (var page = 0; page < maxPages; page += 1) {
        final result = await _api
            .catalog(
              type: type,
              sort: rail.sort,
              skip: skip,
              genre: genre,
              search: rail.query.isEmpty ? null : rail.query,
              deepSearch: rail.query.isNotEmpty,
              preferDefaultCatalog: true,
            )
            .timeout(const Duration(seconds: 4));
        final before = gathered.length;
        for (final item in result.items) {
          if (!_isCurationPreviewCandidate(item, rail)) continue;
          if (seenKeys.add(_notificationCardKey(item, type))) {
            gathered.add(item);
          }
        }
        DiagnosticLog.add(
          'daily curation preview page rail=${rail.id} type=${type.compatTypeValue} sort=${rail.sort.id} skip=$skip page=${page + 1}/$maxPages fetched=${result.items.length} added=${gathered.length - before} gathered=${gathered.length} hasMore=${result.hasMore ?? false}',
        );
        if (gathered.length >= limit) break;
        final delta = result.skipDelta ?? result.items.length;
        if (result.items.isEmpty || delta <= 0 || result.hasMore == false) {
          break;
        }
        skip += delta;
      }
      return gathered.take(limit.clamp(1, 20)).toList(growable: false);
    } catch (_) {
      DiagnosticLog.add('daily curation preview fetch skipped rail=${rail.id}');
      return const <CatalogItem>[];
    }
  }

  int _notificationPreviewMaxPages(HomeEditorialRail rail) {
    final curationKind = rail.curationKind.trim().toLowerCase();
    if (curationKind == 'tmdb_daily_genre') return 1;
    if (_isNotificationSourceBoundRail(rail)) return 5;
    return rail.pageOneOnly ? 1 : 3;
  }

  String _notificationCardKey(CatalogItem item, MediaType fallbackType) {
    final type = item.type.compatTypeValue.isNotEmpty
        ? item.type.compatTypeValue
        : fallbackType.compatTypeValue;
    final tmdbId = item.tmdbId;
    if (tmdbId != null) return '$type:tmdb:$tmdbId';
    final rawId = item.id.trim().toLowerCase();
    if (rawId.isNotEmpty) return '$type:id:$rawId';
    return '$type:title:${item.name.trim().toLowerCase()}';
  }

  String _contentMomentLabel(HomeEditorialRail rail) {
    if (rail.notificationHook.trim().isNotEmpty) return rail.title;
    final intent = rail.intent.toLowerCase();
    if (intent.contains('taste')) return 'Fresh for your taste';
    if (intent.contains('current') ||
        rail.releaseWindow.toLowerCase().contains('current')) {
      return 'New this year';
    }
    if (rail.kind.toLowerCase() == 'ranked') return 'Trending now';
    if (rail.theme.trim().isNotEmpty) return 'A timely shelf';
    return 'Picked for today';
  }

  bool _insideQuietHours(String quietHours) {
    final parts = quietHours.split('-');
    if (parts.length != 2) return false;
    final start = _minutesFromClock(parts[0]);
    final end = _minutesFromClock(parts[1]);
    if (start == null || end == null) return false;
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    if (start <= end) return current >= start && current < end;
    return current >= start || current < end;
  }

  int? _minutesFromClock(String value) {
    final parts = value.trim().split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return hour * 60 + minute;
  }

  void _retryWhenContextReady({
    required String reason,
    required int counter,
    required ValueChanged<int> onCounter,
  }) {
    if (counter >= 2) {
      DiagnosticLog.add(
        'notification retry skipped reason=$reason attempts=$counter',
      );
      return;
    }
    final nextCounter = counter + 1;
    onCounter(nextCounter);
    final delayMs = 650 * nextCounter;
    DiagnosticLog.add(
      'notification retry scheduled reason=$reason attempt=$nextCounter delayMs=$delayMs',
    );
    unawaited(
      Future<void>.delayed(Duration(milliseconds: delayMs)).then((_) async {
        if (_navigatorKey.currentContext == null) return;
        await check(reason: '${reason}_retry_$nextCounter');
      }),
    );
  }
}

List<CatalogItem> _interleavePreviewBuckets(List<List<CatalogItem>> buckets) {
  final output = <CatalogItem>[];
  final seen = <String>{};
  var index = 0;
  while (true) {
    var added = false;
    for (final bucket in buckets) {
      if (index >= bucket.length) continue;
      final item = bucket[index];
      final key = '${item.type.compatTypeValue}:${item.id}';
      if (seen.add(key)) {
        output.add(item);
        added = true;
      }
    }
    if (!added) break;
    index += 1;
  }
  return output;
}

bool _isCurationPreviewCandidate(CatalogItem item, HomeEditorialRail rail) {
  final artwork = _notificationItemArtwork(item);
  if (artwork.isEmpty) return false;
  if (!AppState.showMatureContent.value && item.hasMatureContentSignal) {
    return false;
  }
  if (_isNotificationInTheatersRail(rail)) {
    return item.type == MediaType.movie;
  }
  final allowsUpcoming =
      rail.sort == CatalogSort.upcoming ||
      rail.intent.trim().toLowerCase() == 'upcoming';
  if (item.isUpcoming && !allowsUpcoming) return false;
  final rating = double.tryParse(item.imdbRating?.trim() ?? '');
  if (rating != null && rating <= 0.1) return false;
  final voteCount = item.voteCount;
  if (voteCount != null && voteCount <= 0) return false;
  return true;
}

String _notificationItemArtwork(CatalogItem item) {
  return (item.background ?? item.poster ?? item.logo ?? '').trim();
}

bool _isNotificationInTheatersRail(HomeEditorialRail rail) {
  final intent = rail.intent.trim().toLowerCase();
  final window = rail.releaseWindow.trim().toLowerCase();
  final title = rail.title.trim().toLowerCase();
  return title == 'in theaters' ||
      intent == 'theatrical_trailers' ||
      window == 'now_playing' ||
      rail.sort == CatalogSort.nowPlaying;
}

bool _isNotificationSourceBoundRail(HomeEditorialRail rail) {
  final intent = rail.intent.trim().toLowerCase();
  final kind = rail.curationKind.trim().toLowerCase();
  final window = rail.releaseWindow.trim().toLowerCase();
  final title = rail.title.trim().toLowerCase();
  return title == 'in theaters' ||
      intent == 'theatrical_trailers' ||
      intent == 'upcoming' ||
      intent == 'external_trending' ||
      kind == 'tmdb_list_top10' ||
      window == 'now_playing' ||
      rail.sort == CatalogSort.nowPlaying ||
      rail.sort == CatalogSort.upcoming ||
      rail.sort == CatalogSort.airingToday ||
      rail.sort == CatalogSort.onTv;
}

const int _minimumNotificationCurationItems = 3;

String _dailyCurationTitleFromRail(HomeEditorialRail rail) {
  final title = _safeNotificationCopy(rail.title, fallback: 'Daily Picks');
  if (title.isEmpty) return 'Daily Picks';
  return title;
}

String _dailyCurationHook(HomeEditorialRail rail) {
  final hook = _safeNotificationCopy(rail.notificationHook, fallback: '');
  if (hook.isNotEmpty) return hook;
  final title = _safeNotificationCopy(rail.title, fallback: '');
  if (title.isNotEmpty) return '$title is ready when you are.';
  return 'Fresh picks are ready when you are.';
}

String _firstNonEmpty(List<String> values) {
  return values.firstWhere((value) => value.trim().isNotEmpty).trim();
}

String _dailyCurationMessage(HomeEditorialEdition editorial) {
  for (final rail in [
    editorial.hero,
    editorial.todaySignal,
    editorial.topSignal,
    editorial.movie,
    editorial.series,
    editorial.animation,
  ]) {
    final title = _safeNotificationCopy(rail.title, fallback: '');
    final subtitle = _safeNotificationCopy(rail.subtitle, fallback: '');
    if (title.isNotEmpty && subtitle.isNotEmpty) return '$title - $subtitle';
    if (title.isNotEmpty) return title;
    if (subtitle.isNotEmpty) return subtitle;
  }
  return 'Fresh movie, series, and animation picks are waiting.';
}

String _safeNotificationCopy(String value, {required String fallback}) {
  final redacted = value
      .replaceAll(RegExp(r'https?:\/\/[^\s,)]+', caseSensitive: false), '')
      .replaceAll(RegExp(r'magnet:\?[^\s,)]+', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'''\b(infoHash|trackerAddresses|peerAddresses|headers|tokens|localRuntimeEndpoints|manifestUrls|streamUrls|externalUrls)\b\s*[:=]\s*["']?[^"',;)]+''',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'''\b(api[_-]?key|token|secret|password|authorization|bearer)\b\s*[:=]\s*["']?[^"'\s,;)]+''',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'''\b(?:manifest|stream|source|local)\s+url\s*[:=]\s*["']?[^"'\s,;)]+''',
          caseSensitive: false,
        ),
        '[redacted]',
      )
      .replaceAll(
        RegExp(
          r'''\blocal\s+endpoint\s*[:=]\s*["']?[^"'\s,;)]+''',
          caseSensitive: false,
        ),
        '[redacted]',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final clean = redacted.length > 120
      ? redacted.substring(0, 120).trim()
      : redacted;
  return clean.isEmpty ? fallback : clean;
}

String _dailyCurationTitle(HomeEditorialEdition editorial) {
  return _pickNotificationCopy(
    seed: editorial.editionId,
    values: const [
      "Today's Juicr picks",
      'Fresh picks from Juicr',
      'Your Juicr shelf is ready',
      'Tonight on Juicr',
      'A fresh row is waiting',
    ],
  );
}

String _pickNotificationCopy({
  required String seed,
  required List<String> values,
}) {
  if (values.isEmpty) return '';
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return values[hash % values.length];
}

class _NotificationCard {
  const _NotificationCard({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.type,
    required this.sort,
    required this.genre,
  });

  final String key;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final MediaType type;
  final CatalogSort sort;
  final String genre;
}

class _DailyCurationPreview {
  const _DailyCurationPreview({
    required this.title,
    required this.message,
    required this.cards,
  });

  final String title;
  final String message;
  final List<_NotificationCard> cards;
}

class _NotificationCardDialog extends StatefulWidget {
  const _NotificationCardDialog({
    required this.title,
    required this.subtitle,
    required this.cards,
  });

  final String title;
  final String subtitle;
  final List<_NotificationCard> cards;

  @override
  State<_NotificationCardDialog> createState() =>
      _NotificationCardDialogState();
}

class _NotificationCardDialogState extends State<_NotificationCardDialog> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = widget.cards[_index.clamp(0, widget.cards.length - 1)];
    final size = MediaQuery.sizeOf(context);
    final maxDialogHeight = math.max(220.0, size.height - 64);
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(420, size.width - 40),
            maxHeight: maxDialogHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(widget.subtitle, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  AspectRatio(
                    aspectRatio: 16 / 10,
                    child: PageView.builder(
                      itemCount: widget.cards.length,
                      onPageChanged: (index) => setState(() => _index = index),
                      itemBuilder: (context, index) {
                        final item = widget.cards[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if ((item.imageUrl ?? '').isNotEmpty)
                                Image.network(
                                  item.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                )
                              else
                                ColoredBox(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.78),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 16,
                                right: 16,
                                bottom: 16,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.subtitle,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < widget.cards.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            color: i == _index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context, rootNavigator: true).pop(),
                        child: const Text('Later'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          AppState.openDiscovery(
                            type: card.type,
                            sort: card.sort,
                            genre: card.genre,
                          );
                          Navigator.of(context, rootNavigator: true).pop();
                        },
                        child: const Text('Explore'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
