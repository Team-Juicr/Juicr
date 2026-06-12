import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/services.dart';

import 'ad_policy.dart';
import 'app_state.dart';
import 'catalog_item.dart';
import 'diagnostic_log.dart';
import 'details_save_sheet.dart';
import 'juicr_bottom_sheet.dart';
import 'libvlc_hls_relay.dart';
import 'motion.dart';
import 'native_player_page.dart';
import 'playback_provider.dart';
import 'stream_api.dart';
import 'system_ui.dart';
import 'visual_style.dart';

const MethodChannel _externalPlayerChannel = MethodChannel(
  'app.juicr.flutter/external_player',
);

class DetailsPage extends StatefulWidget {
  const DetailsPage({
    super.key,
    required this.item,
    this.autoOpenTrailer = false,
  });

  final CatalogItem item;
  final bool autoOpenTrailer;

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DefaultNativeProviderSelection {
  const _DefaultNativeProviderSelection({
    required this.providerIds,
    this.cappedColdScan = false,
  });

  final List<String> providerIds;
  final bool cappedColdScan;
}

class _DetailsPageState extends State<DetailsPage>
    with TickerProviderStateMixin {
  static const int _coldStartProviderProbeLimit = 4;
  static const String _videoUnavailableSnack = 'Video unavailable. Try later.';
  static const String _sourceSlowSnack = 'Taking longer. Try again soon.';
  static const String _unsupportedSourceSnack =
      'Juicr cannot play that source type yet.';
  static const String _localPlaybackLockedSnack =
      'Local playback is not ready yet.';
  static const double _detailsPrimaryActionHeight = 48;
  static const double _detailsPrimaryActionGap = 12;
  static const double _detailsPrimaryActionIconSize = 20;
  static const TextStyle _detailsPrimaryActionTextStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
  static const List<Duration> _liveTvResolveRetryDelays = <Duration>[
    Duration(milliseconds: 650),
    Duration(milliseconds: 1300),
  ];
  static const PlaybackResult _emptyPlaybackResult = PlaybackResult(
    sources: <PlaybackSource>[],
    embeds: <PlaybackCandidate>[],
    debug: PlaybackDebug.empty,
  );
  final StreamApi _api = StreamApi();
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _playbackBusyController;
  late final AnimationController _trailerBusyController;
  bool _disposed = false;
  late final Future<MetaDetails> _detailsFuture;
  late final Future<StreamConfig?> _configFuture;
  late final Future<List<TrailerItem>> _trailersFuture;
  late final Future<List<CatalogItem>> _recommendationsFuture;
  bool _showCollapsedTitle = false;
  bool _openingPlayback = false;
  bool _openingTrailer = false;
  String? _openingEpisodeKey;
  LibVlcHlsRelay? _externalPlayerRelay;
  final Map<String, DateTime> _playbackRetryAfterByKey = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    AppState.recordTasteForItem(widget.item, weight: 2);
    _playbackBusyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _trailerBusyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.item.isLocalCatalogItem) {
      _detailsFuture = Future<MetaDetails>.value(
        MetaDetails(item: widget.item),
      );
      _recommendationsFuture = Future<List<CatalogItem>>.value(
        const <CatalogItem>[],
      );
      _configFuture = Future<StreamConfig?>.value(null);
      _trailersFuture = Future<List<TrailerItem>>.value(const <TrailerItem>[]);
    } else {
      _detailsFuture = _loadDetailsMetadata(widget.item);
      _recommendationsFuture = widget.item.type.isLive
          ? Future<List<CatalogItem>>.value(const <CatalogItem>[])
          : _detailsFuture
                .then((details) {
                  final merged = _mergeDetailsMetadataArtwork(
                    details.item,
                    widget.item,
                  );
                  return _loadRecommendations(
                    _recommendationSourceForDetails(merged, details),
                  );
                })
                .catchError((Object error) {
                  DiagnosticLog.add(
                    'details recommendations skipped reason=metadata_unavailable id=${widget.item.id} error=$error',
                  );
                  return const <CatalogItem>[];
                });
      _configFuture = widget.item.type.isLive
          ? Future<StreamConfig?>.value(null)
          : StreamApi.cachedConfig == null
          ? _api
                .config()
                .then<StreamConfig?>((config) => config)
                .catchError((_) => null)
          : Future<StreamConfig?>.value(StreamApi.cachedConfig);
      _trailersFuture = widget.item.type.isLive
          ? Future.value(const <TrailerItem>[])
          : _detailsFuture.then(
              (details) => _api.resolveTrailers(
                _trailerSourceForDetails(widget.item, details),
              ),
            );
    }
    _scrollController.addListener(_handleScroll);
    if (widget.autoOpenTrailer) {
      _trailersFuture
          .then((trailers) {
            if (mounted && trailers.isNotEmpty) {
              unawaited(_openTrailer(widget.item.name, trailers));
            }
          })
          .catchError((_) => const <TrailerItem>[]);
    }
  }

  Future<MetaDetails> _loadDetailsMetadata(CatalogItem item) async {
    final details = await _loadDetailsMetadataWithSeriesRetry(item);
    return _loadAnimationMovieMetadataFallback(item, details);
  }

  Future<MetaDetails> _loadDetailsMetadataWithSeriesRetry(
    CatalogItem item,
  ) async {
    var details = await _api.meta(item);
    if (!item.type.isPlayableSeries || details.videos.isNotEmpty) {
      return details;
    }
    var bestDetails = details;
    for (var attempt = 1; attempt <= 2; attempt += 1) {
      await Future<void>.delayed(Duration(milliseconds: 450 * attempt));
      try {
        details = await _api.meta(item);
        if (_detailsMetadataScore(details) >
            _detailsMetadataScore(bestDetails)) {
          bestDetails = details;
        }
        if (details.videos.isNotEmpty) {
          DiagnosticLog.add(
            'details series metadata retry recovered type=${item.type.compatTypeValue} id=${item.id} attempt=$attempt episodes=${details.videos.length}',
          );
          return details;
        }
      } catch (error) {
        DiagnosticLog.add(
          'details series metadata retry skipped type=${item.type.compatTypeValue} id=${item.id} attempt=$attempt error=${error.runtimeType}',
        );
      }
    }
    if (bestDetails.videos.isEmpty) {
      DiagnosticLog.add(
        'details series metadata unavailable type=${item.type.compatTypeValue} id=${item.id} attempts=3',
      );
    }
    return bestDetails;
  }

  int _detailsMetadataScore(MetaDetails details) {
    var score = 0;
    if (_hasDetailsArtwork(details.item)) score += 3;
    if (details.item.description?.trim().isNotEmpty == true) score += 2;
    if (details.item.genres.isNotEmpty) score += 1;
    if (details.runtime?.trim().isNotEmpty == true) score += 1;
    score += details.videos.isEmpty
        ? 0
        : 10 + details.videos.length.clamp(0, 40);
    return score;
  }

  bool _shouldShowEpisodeLayout(CatalogItem item, MetaDetails details) {
    if (item.type == MediaType.series) return true;
    if (item.type == MediaType.animation) return details.videos.isNotEmpty;
    return false;
  }

  Future<MetaDetails> _loadAnimationMovieMetadataFallback(
    CatalogItem item,
    MetaDetails details,
  ) async {
    if (item.type != MediaType.animation || details.videos.isNotEmpty) {
      return details;
    }
    try {
      final movieDetails = await _api.meta(item.withType(MediaType.movie));
      final merged = _mergeAnimationMovieMetadata(details, movieDetails);
      DiagnosticLog.add(
        'details animation movie metadata fallback id=${item.id} '
        'people=${merged.cast.length + merged.director.length}',
      );
      return merged;
    } catch (error) {
      DiagnosticLog.add(
        'details animation movie metadata fallback skipped id=${item.id} '
        'error=${error.runtimeType}',
      );
      return details;
    }
  }

  MetaDetails _mergeAnimationMovieMetadata(
    MetaDetails animationDetails,
    MetaDetails movieDetails,
  ) {
    return MetaDetails(
      item: _mergeDetailsMetadataArtwork(
        animationDetails.item
            .merge(movieDetails.item)
            .withType(MediaType.animation),
        animationDetails.item,
      ),
      runtime: animationDetails.runtime?.trim().isNotEmpty == true
          ? animationDetails.runtime
          : movieDetails.runtime,
      director: animationDetails.director.isNotEmpty
          ? animationDetails.director
          : movieDetails.director,
      cast: animationDetails.cast.isNotEmpty
          ? animationDetails.cast
          : movieDetails.cast,
      directorPeople: animationDetails.directorPeople.isNotEmpty
          ? animationDetails.directorPeople
          : movieDetails.directorPeople,
      castPeople: animationDetails.castPeople.isNotEmpty
          ? animationDetails.castPeople
          : movieDetails.castPeople,
      videos: animationDetails.videos,
    );
  }

  CatalogItem _recommendationSourceForDetails(
    CatalogItem item,
    MetaDetails details,
  ) {
    if (item.type == MediaType.animation && details.videos.isEmpty) {
      return item.withType(MediaType.movie);
    }
    return item;
  }

  CatalogItem _trailerSourceForDetails(CatalogItem item, MetaDetails details) {
    if (item.type == MediaType.animation && details.videos.isEmpty) {
      return item.withType(MediaType.movie);
    }
    return item;
  }

  bool _hasDetailsArtwork(CatalogItem item) {
    return (item.poster?.trim().isNotEmpty ?? false) ||
        (item.background?.trim().isNotEmpty ?? false) ||
        (item.logo?.trim().isNotEmpty ?? false);
  }

  static CatalogItem _mergeDetailsMetadataArtwork(
    CatalogItem metadata,
    CatalogItem original,
  ) {
    final merged = metadata.merge(original);
    if (!original.isTmdbBackedItem && !metadata.isTmdbBackedItem) {
      return merged;
    }
    final metadataPoster = _safeDetailsArtworkUrl(metadata.poster);
    final metadataBackground = _safeDetailsArtworkUrl(metadata.background);
    final metadataLogo = _safeDetailsArtworkUrl(metadata.logo);
    if (metadataPoster == null &&
        metadataBackground == null &&
        metadataLogo == null) {
      return merged;
    }
    return CatalogItem(
      type: merged.type,
      id: merged.id,
      name: merged.name,
      poster: metadataPoster ?? merged.poster,
      background: metadataBackground ?? merged.background,
      logo: metadataLogo ?? merged.logo,
      year: merged.year,
      releaseDate: merged.releaseDate,
      tmdbId: merged.tmdbId,
      imdbId: merged.imdbId,
      genres: merged.genres,
      description: merged.description,
      imdbRating: merged.imdbRating,
      voteCount: merged.voteCount,
      adult: merged.adult,
      isUpcoming: merged.isUpcoming,
      isLocalCatalogItem: merged.isLocalCatalogItem,
      localPlaybackLocked: merged.localPlaybackLocked,
      localCatalogId: merged.localCatalogId,
      localCatalogItemId: merged.localCatalogItemId,
      localCatalogName: merged.localCatalogName,
      localMediaKind: merged.localMediaKind,
      localSourceLabel: merged.localSourceLabel,
      localRelinkNeededCount: merged.localRelinkNeededCount,
      personalServerTypeId: merged.personalServerTypeId,
      personalServerItemId: merged.personalServerItemId,
      personalServerSeriesItemId: merged.personalServerSeriesItemId,
    );
  }

  static String? _safeDetailsArtworkUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    return trimmed;
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackBusyController.dispose();
    _trailerBusyController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    unawaited(_stopExternalPlayerRelay('dispose'));
    _api.close();
    super.dispose();
  }

  void _handleScroll() {
    final shouldShow =
        _scrollController.hasClients && _scrollController.offset > 210;
    if (shouldShow == _showCollapsedTitle || !mounted) return;
    setState(() {
      _showCollapsedTitle = shouldShow;
    });
  }

  void _showPlaybackSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showLibrarySnackBar(CatalogItem item, {required bool saved}) {
    if (!mounted) return;
    final destination = item.type.pluralLabel;
    final message = saved
        ? '${item.name} saved to $destination'
        : '${item.name} removed from Library';
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openGenreInDiscovery(CatalogItem item, String genre) {
    final cleaned = genre.trim();
    if (cleaned.isEmpty) return;
    DiagnosticLog.add(
      'details genre chip opened type=${item.type.compatTypeValue} genre=$cleaned',
    );
    AppState.openDiscovery(
      type: item.type,
      sort: CatalogSort.top,
      genre: cleaned,
    );
    Navigator.of(context).maybePop();
  }

  Future<String?> _openNativePlayer(
    String title,
    List<NativePlaybackRequest> sources, {
    required Future<List<PlaybackSource>> Function(String providerId)
    resolveNativeProvider,
    Future<List<PlaybackSubtitle>> Function()? resolveSubtitles,
    String? logoUrl,
    CatalogItem? progressItem,
    String? playbackKey,
    String? progressSubtitle,
    String? nextEpisodeLabel,
    Future<NativePlayerNextEpisode?> Function()? onNextEpisode,
    bool limitToFirstQualityPass = false,
    bool liveMode = false,
  }) async {
    if (!mounted) return null;
    final routeStopwatch = Stopwatch()..start();
    DiagnosticLog.add(
      'native route opening titleLength=${title.length} requests=${sources.length} limitToFirstQualityPass=$limitToFirstQualityPass liveMode=$liveMode',
    );
    final result = await Navigator.of(context).push<String>(
      AppPageRoute<String>(
        builder: (_) => NativePlayerPage(
          title: title,
          sources: sources,
          resolveProvider: resolveNativeProvider,
          resolveSubtitles: resolveSubtitles,
          logoUrl: logoUrl,
          progressItem: progressItem,
          playbackKey: playbackKey,
          progressSubtitle: progressSubtitle,
          nextEpisodeLabel: nextEpisodeLabel,
          onNextEpisode: onNextEpisode,
          limitToFirstQualityPass: limitToFirstQualityPass,
          liveMode: liveMode,
          enableProviderWarmup: sources.any(
            (request) => request.sources.isNotEmpty,
          ),
        ),
      ),
    );
    DiagnosticLog.add(
      'native route finished result=${result ?? 'closed'} elapsed=${routeStopwatch.elapsedMilliseconds}ms',
    );
    return result;
  }

  Future<void> _runPlaybackLaunch(
    Future<void> Function() action, {
    required String launchKey,
  }) async {
    if (!mounted) return;
    final now = DateTime.now();
    _playbackRetryAfterByKey.removeWhere((_, until) => !now.isBefore(until));
    final retryAfter = _playbackRetryAfterByKey[launchKey];
    if (retryAfter != null && now.isBefore(retryAfter)) {
      DiagnosticLog.add(
        'details playback launch ignored reason=local_retry_window key=$launchKey remainingMs=${retryAfter.difference(now).inMilliseconds}',
      );
      _showPlaybackSnackBar('Try again in a few seconds.');
      return;
    }
    if (_openingPlayback) {
      DiagnosticLog.add(
        'details playback launch ignored reason=already_opening',
      );
      return;
    }
    setState(() => _openingPlayback = true);
    _playbackBusyController.repeat();
    try {
      await action();
    } finally {
      if (mounted) {
        _playbackBusyController.stop();
        _playbackBusyController.reset();
        setState(() => _openingPlayback = false);
      }
    }
  }

  Future<void> _openMovieFromDetailsPrimary(
    CatalogItem item, {
    required bool hasCompleted,
  }) async {
    await _runPlaybackLaunch(() async {
      DiagnosticLog.screen(
        context,
        item.type == MediaType.liveTv
            ? 'Details watch live press'
            : 'Details watch movie press',
      );
      DiagnosticLog.add(
        'details watch ${item.type.compatTypeValue} pressed id=${item.id} completed=$hasCompleted',
      );
      await _openMoviePlayerSafely(item.name, item);
    }, launchKey: item.id);
  }

  void _rememberTemporaryResolverBlock(String launchKey, Object error) {
    if (!_isTemporaryResolverBlock(error)) return;
    final retryAfterSeconds = error is StreamApiTemporaryBlockException
        ? error.retryAfterSeconds
        : 0;
    _playbackRetryAfterByKey[launchKey] = DateTime.now().add(
      Duration(
        seconds: retryAfterSeconds > 0
            ? retryAfterSeconds.clamp(5, 300).toInt()
            : 20,
      ),
    );
    DiagnosticLog.add(
      'details playback service temporary block observed key=$launchKey error=$error',
    );
  }

  void _rememberPlaybackLaunchFailure(String launchKey, Object error) {
    _rememberTemporaryResolverBlock(launchKey, error);
    final text = error.toString().toLowerCase();
    if (text.contains('playable sources')) {
      _playbackRetryAfterByKey[launchKey] = DateTime.now().add(
        const Duration(seconds: 5),
      );
      DiagnosticLog.add(
        'details playback local retry window set key=$launchKey reason=no_playable_sources',
      );
    }
  }

  Future<void> _openTrailer(String title, List<TrailerItem> trailers) async {
    if (trailers.isEmpty) return;
    if (_openingTrailer) return;
    DiagnosticLog.add(
      'details trailer pressed titleLength=${title.length} providers=${trailers.map((trailer) => trailer.providerId).join(',')} count=${trailers.length}',
    );
    setState(() => _openingTrailer = true);
    _trailerBusyController.repeat();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close trailer',
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (context) {
        return _TrailerDialog(
          title: title,
          trailers: trailers,
          onTrailerReady: _markTrailerReady,
        );
      },
    );
    _markTrailerReady();
    DiagnosticLog.add(
      'details trailer dialog closed titleLength=${title.length}',
    );
  }

  void _markTrailerReady() {
    if (!_openingTrailer) return;
    _trailerBusyController
      ..stop()
      ..reset();
    if (mounted) {
      setState(() => _openingTrailer = false);
    } else {
      _openingTrailer = false;
    }
  }

  Future<bool> _confirmRemoveFromLibrary(CatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text('This removes "${item.name}" from your saved library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showAddToListSheet(CatalogItem item) async {
    DiagnosticLog.add('details save menu opened id=${item.id}');
    final saved = AppState.library.value.containsKey(item.id);
    final action = await showJuicrBottomSheet<DetailsSaveMenuAction>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => DetailsSaveMenuSheet(item: item, saved: saved),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case DetailsSaveMenuAction.addToList:
        await _showListPickerSheet(item);
      case DetailsSaveMenuAction.toggleSaved:
        if (saved && !await _confirmRemoveFromLibrary(item)) {
          DiagnosticLog.add('details favorite removal cancelled id=${item.id}');
          return;
        }
        DiagnosticLog.add(
          'details favorite toggled id=${item.id} savedBefore=$saved',
        );
        AppState.toggleSaved(item);
        _showLibrarySnackBar(item, saved: !saved);
    }
  }

  Future<void> _showListPickerSheet(CatalogItem item) async {
    await showJuicrBottomSheet<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => ListPickerSheet(item: item),
    );
  }

  Future<void> _openResolvedPlayback(
    String title,
    PlaybackResult result, {
    required AdBlockConfig adBlock,
    required Future<List<PlaybackSource>> Function(String providerId)
    resolveNativeProvider,
    Future<List<PlaybackSubtitle>> Function()? resolveSubtitles,
    String? logoUrl,
    String? artworkUrl,
    CatalogItem? progressItem,
    String? playbackKey,
    String? progressSubtitle,
    EpisodeItem? nextEpisode,
    List<EpisodeItem> episodeList = const <EpisodeItem>[],
    bool liveMode = false,
    required String rewardedAdReason,
  }) async {
    DiagnosticLog.add(
      'openResolved titleLength=${title.length} nativeSources=${result.sources.map((source) => source.providerId).join(',')} trailerCandidates=${result.embeds.map((candidate) => candidate.providerId).join(',')}',
    );
    final sources = _orderSources(_nativeEligibleSources(result.sources));
    if (sources.length != result.sources.length) {
      DiagnosticLog.add(
        'openResolved source gate skipped count=${result.sources.length - sources.length}',
      );
    }
    AppState.recordResolvedNativeSources(
      mediaKey: playbackKey,
      sources: sources,
    );
    DiagnosticLog.add(
      'ordered playback native=${sources.map((source) => _nativeProviderDiagnosticLabel(source.providerId)).join('>')}',
    );
    if (sources.isEmpty &&
        !NativePlayerPage.hasVerifiedSourceFor(playbackKey)) {
      DiagnosticLog.add(
        'openResolved skipped reason=no_native_sources key=${playbackKey ?? progressItem?.id ?? 'none'}',
      );
      if (mounted) {
        _showPlaybackSnackBar(_videoUnavailableSnack);
      }
      return;
    }
    if (!AppState.playerBehaviorSettings.value.useNativePlayer) {
      await _tryExternalPlayer(
        title,
        sources,
        resolveNativeProvider: resolveNativeProvider,
      );
      return;
    }
    final playedNative = await _tryNativeSources(
      title,
      sources,
      resolveNativeProvider: resolveNativeProvider,
      resolveSubtitles: resolveSubtitles,
      logoUrl: logoUrl,
      progressItem: progressItem,
      playbackKey: playbackKey,
      progressSubtitle: progressSubtitle,
      nextEpisodeLabel: nextEpisode == null ? null : 'Next episode',
      onNextEpisode: nextEpisode == null || progressItem == null
          ? null
          : () =>
                _buildNativeNextEpisode(progressItem, nextEpisode, episodeList),
      liveMode: liveMode,
      rewardedAdReason: rewardedAdReason,
    );
    if (playedNative || !mounted) return;
    _showPlaybackSnackBar(_videoUnavailableSnack);
  }

  List<PlaybackSource> _nativeEligibleSources(List<PlaybackSource> sources) {
    return sources
        .where(
          (source) =>
              AppState.playbackSourceClassAllowedForNative(source.sourceClass),
        )
        .toList(growable: false);
  }

  Future<bool> _tryExternalPlayer(
    String title,
    List<PlaybackSource> sources, {
    required Future<List<PlaybackSource>> Function(String providerId)
    resolveNativeProvider,
  }) async {
    final settings = AppState.playerBehaviorSettings.value;
    final directSources = <PlaybackSource>[
      for (final source in sources)
        if (_externalPlayerSourceUsable(source)) source,
    ];
    if (directSources.isEmpty) {
      final seenProviders = <String>{};
      for (final source in sources) {
        if (!seenProviders.add(source.providerId)) continue;
        try {
          directSources.addAll(
            (await resolveNativeProvider(
              source.providerId,
            )).where(_externalPlayerSourceUsable),
          );
        } catch (error) {
          DiagnosticLog.add(
            'external player source resolve failed provider=${source.providerId} error=${error.runtimeType}',
          );
        }
        if (directSources.isNotEmpty) break;
      }
    }
    if (directSources.isEmpty) {
      DiagnosticLog.add('external player skipped: no usable stream URL');
      if (mounted) {
        _showPlaybackSnackBar('External apps cannot open this stream.');
      }
      return false;
    }

    try {
      final source = directSources.first;
      final handoffUrl = await _externalPlayerUrlForSource(source);
      if (handoffUrl == null) {
        DiagnosticLog.add(
          'external player skipped: unable to prepare handoff url',
        );
        if (mounted) {
          _showPlaybackSnackBar('External apps cannot open this stream.');
        }
        return false;
      }
      final packageLabel = settings.externalPlayerPackage ?? 'chooser';
      DiagnosticLog.add(
        'external player open package=$packageLabel provider=${source.providerId} quality=${source.quality ?? 'unknown'}',
      );
      final opened =
          await _externalPlayerChannel.invokeMethod<bool>('open', {
            'url': handoffUrl,
            'packageName': settings.externalPlayerPackage,
            'activityName': settings.externalPlayerActivity,
            'title': title,
          }) ??
          false;
      if (!opened && mounted) {
        _showPlaybackSnackBar('No player could open this.');
      }
      return opened;
    } catch (error) {
      DiagnosticLog.add(
        'external player open failed error=${error.runtimeType}',
      );
      if (mounted) {
        _showPlaybackSnackBar('External player could not start.');
      }
      return false;
    }
  }

  bool _externalPlayerSourceUsable(PlaybackSource source) {
    if (source.url.trim().isEmpty || (source.drm?.isPresent ?? false)) {
      return false;
    }
    return source.headers.isEmpty || Uri.tryParse(source.url) != null;
  }

  Future<String?> _externalPlayerUrlForSource(PlaybackSource source) async {
    final url = source.url.trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;
    await _stopExternalPlayerRelay('new_external_source');
    try {
      final relay = await LibVlcHlsRelay.start(
        upstreamUri: uri,
        headers: source.headers,
        resumePosition: Duration.zero,
        onEvent: (message) => DiagnosticLog.add(
          message.replaceFirst(
            'native libvlc hls relay',
            'external player relay',
          ),
        ),
      );
      _externalPlayerRelay = relay;
      DiagnosticLog.add(
        'external player relay started provider=${source.providerId} headers=${source.headers.length} url=[localhost-hidden]',
      );
      return relay.localUri.toString();
    } catch (error) {
      DiagnosticLog.add(
        'external player relay start failed error=${error.runtimeType}',
      );
      return null;
    }
  }

  Future<void> _stopExternalPlayerRelay(String reason) async {
    final relay = _externalPlayerRelay;
    if (relay == null) return;
    _externalPlayerRelay = null;
    try {
      final summary = relay.summary;
      await relay.stop();
      DiagnosticLog.add(
        'external player relay stopped reason=$reason $summary',
      );
    } catch (error) {
      DiagnosticLog.add(
        'external player relay stop failed reason=$reason error=${error.runtimeType}',
      );
    }
  }

  Future<bool> _tryNativeSources(
    String title,
    List<PlaybackSource> sources, {
    required Future<List<PlaybackSource>> Function(String providerId)
    resolveNativeProvider,
    Future<List<PlaybackSubtitle>> Function()? resolveSubtitles,
    String? logoUrl,
    CatalogItem? progressItem,
    String? playbackKey,
    String? progressSubtitle,
    String? nextEpisodeLabel,
    Future<NativePlayerNextEpisode?> Function()? onNextEpisode,
    bool liveMode = false,
    required String rewardedAdReason,
  }) async {
    final initialByProvider = <String, List<PlaybackSource>>{};
    for (final source in sources) {
      initialByProvider
          .putIfAbsent(source.providerId, () => <PlaybackSource>[])
          .add(source);
    }

    final addonProviderIds = initialByProvider.keys
        .where((providerId) => providerId.startsWith('addon-'))
        .toList();
    final personalProviderIds = initialByProvider.keys
        .where((providerId) => providerId.startsWith('personal-'))
        .toList();
    final publicIptvProviderIds = initialByProvider.keys
        .where((providerId) => providerId == 'public-iptv')
        .toList();
    final useAddonOnly =
        AppState.userAddons.value.any((addon) => addon.active) &&
        addonProviderIds.isNotEmpty;
    final defaultProviderSelection = _defaultNativeProviderSelectionForPlayback(
      playbackKey: playbackKey,
      mediaKey: progressItem?.id,
      initialProviderIds: initialByProvider.keys.toSet(),
      hasAddonSources: addonProviderIds.isNotEmpty,
      useAddonOnly:
          useAddonOnly ||
          publicIptvProviderIds.isNotEmpty ||
          personalProviderIds.isNotEmpty,
    );
    final verifiedCacheRequests = _verifiedCacheProviderRequestsFor(
      playbackKey,
      resolvedSourcesByProvider: initialByProvider,
    );
    final verifiedCacheProviderIds = verifiedCacheRequests
        .map((request) => request.providerId)
        .toSet();
    final prioritizedResolvedProviderIds = <String>{
      ...verifiedCacheProviderIds,
      ...personalProviderIds,
      ...publicIptvProviderIds,
      ...addonProviderIds,
      ...defaultProviderSelection.providerIds,
    };
    final remainingResolvedProviderIds = initialByProvider.keys
        .where(
          (providerId) =>
              !prioritizedResolvedProviderIds.contains(providerId) &&
              (initialByProvider[providerId]?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    final requests = [
      ...verifiedCacheRequests,
      for (final providerId in personalProviderIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      for (final providerId in publicIptvProviderIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      for (final providerId in addonProviderIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      if (publicIptvProviderIds.isEmpty)
        for (final providerId in defaultProviderSelection.providerIds)
          if (!verifiedCacheProviderIds.contains(providerId))
            NativePlaybackRequest(
              providerId: providerId,
              sources:
                  initialByProvider[providerId] ?? const <PlaybackSource>[],
            ),
      for (final providerId in remainingResolvedProviderIds)
        NativePlaybackRequest(
          providerId: providerId,
          sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
        ),
    ];
    DiagnosticLog.add(
      "native request order=${requests.map((request) => _nativeProviderDiagnosticLabel(request.providerId)).join('>')} key=${playbackKey ?? progressItem?.id ?? 'none'}",
    );
    if (requests.isEmpty) {
      DiagnosticLog.add('native skipped: no provider requests available');
      return false;
    }

    await JuicrAdPolicy.showRewardedBeforePlayback(
      context,
      reason: rewardedAdReason,
    );
    if (!mounted) return false;

    final result = await _openNativePlayer(
      title,
      requests,
      resolveNativeProvider: resolveNativeProvider,
      resolveSubtitles: resolveSubtitles,
      logoUrl: logoUrl,
      progressItem: progressItem,
      playbackKey: playbackKey,
      progressSubtitle: progressSubtitle,
      nextEpisodeLabel: nextEpisodeLabel,
      onNextEpisode: onNextEpisode,
      limitToFirstQualityPass: defaultProviderSelection.cappedColdScan,
      liveMode: liveMode,
    );
    DiagnosticLog.add('native route completed result=${result ?? 'closed'}');
    if (result?.startsWith('native_error') == true && mounted) {
      final detail = result!.contains(':')
          ? result.split(':').skip(1).join(':').trim()
          : '';
      _showPlaybackSnackBar(_friendlyNativePlaybackError(detail));
    }
    return true;
  }

  String _friendlyNativePlaybackError(String detail) {
    final text = detail.trim();
    if (text.isEmpty) {
      return _videoUnavailableSnack;
    }
    final normalized = text.toLowerCase();
    if (normalized == 'playback_service_temporary_block' ||
        normalized == 'resolver_temporary_block' ||
        _isTemporaryResolverBlock(text)) {
      return _sourceSlowSnack;
    }
    if (normalized == 'source_class_not_native') {
      return _unsupportedSourceSnack;
    }
    if (normalized == 'addon_route_unavailable' ||
        normalized == 'empty_addon_route' ||
        normalized == 'no_active_addon_route' ||
        normalized == 'no_playback_available' ||
        normalized == 'playback_unavailable' ||
        normalized == 'no_playable_source' ||
        normalized == 'no_working_source' ||
        normalized == 'source_unavailable') {
      return _videoUnavailableSnack;
    }
    return text;
  }

  List<NativePlaybackRequest> _verifiedCacheProviderRequestsFor(
    String? playbackKey, {
    Map<String, List<PlaybackSource>> resolvedSourcesByProvider =
        const <String, List<PlaybackSource>>{},
  }) {
    if (!NativePlayerPage.hasVerifiedSourceFor(playbackKey)) {
      return const <NativePlaybackRequest>[];
    }
    final providerIds = <String>[];
    for (final cached in AppState.verifiedPlaybackSourcesFor(playbackKey!)) {
      final providerId = cached.source.providerId;
      if (providerId.isEmpty || providerIds.contains(providerId)) continue;
      if (resolvedSourcesByProvider.isNotEmpty &&
          !resolvedSourcesByProvider.containsKey(providerId)) {
        DiagnosticLog.add(
          'native verified source cache skipped key=[redacted] provider=${_nativeProviderDiagnosticLabel(providerId)} sourceClass=${cached.source.sourceClass.wireName} reason=provider_not_in_current_route note=verified cache provider is outside current route',
        );
        continue;
      }
      providerIds.add(providerId);
    }
    if (providerIds.isEmpty) return const <NativePlaybackRequest>[];
    DiagnosticLog.add(
      'native verified request seed key=$playbackKey providers=${providerIds.map(_nativeProviderDiagnosticLabel).join('>')}',
    );
    return <NativePlaybackRequest>[
      for (final providerId in providerIds)
        NativePlaybackRequest(
          providerId: providerId,
          sources:
              resolvedSourcesByProvider[providerId] ?? const <PlaybackSource>[],
        ),
    ];
  }

  bool _shouldResolveFreshSourcesWithVerifiedCache({
    required bool hasVerifiedSource,
  }) {
    if (!hasVerifiedSource) return false;
    _activateSingleUserAddonIfItIsTheOnlySource();
    return AppState.userAddons.value.any((addon) => addon.active);
  }

  _DefaultNativeProviderSelection _defaultNativeProviderSelectionForPlayback({
    required String? playbackKey,
    required String? mediaKey,
    required Set<String> initialProviderIds,
    required bool hasAddonSources,
    required bool useAddonOnly,
  }) {
    if (useAddonOnly || !AppState.defaultProvidersEnabled.value) {
      return const _DefaultNativeProviderSelection(providerIds: <String>[]);
    }
    final providerIds = AppState.orderedNativeProviderIds(
      mediaKey: playbackKey ?? mediaKey,
    );
    final hasVerifiedSource = NativePlayerPage.hasVerifiedSourceFor(
      playbackKey,
    );
    final shouldCapScan = !hasVerifiedSource && !hasAddonSources;
    if (!shouldCapScan) {
      return _DefaultNativeProviderSelection(providerIds: providerIds);
    }
    final preview = <String>[];
    for (final providerId in providerIds) {
      if (!initialProviderIds.contains(providerId)) continue;
      preview.add(providerId);
      if (preview.length >= _coldStartProviderProbeLimit) break;
    }
    if (preview.isEmpty) {
      DiagnosticLog.add(
        'native provider scan skipped key=${playbackKey ?? mediaKey ?? 'none'} reason=no_resolved_sources total=${providerIds.length}',
      );
      return const _DefaultNativeProviderSelection(
        providerIds: <String>[],
        cappedColdScan: true,
      );
    }
    DiagnosticLog.add(
      'native provider scan resolved-only key=${playbackKey ?? mediaKey ?? 'none'} initial=${initialProviderIds.length} first=${preview.map(_nativeProviderDiagnosticLabel).join('>')} total=${providerIds.length}',
    );
    return _DefaultNativeProviderSelection(
      providerIds: preview,
      cappedColdScan: true,
    );
  }

  Future<void> _openMoviePlayerSafely(String title, CatalogItem item) async {
    if (item.isLocalCatalogItem) {
      DiagnosticLog.add(
        'details local playback locked id=${item.id} catalogId=${item.localCatalogId ?? 'unknown'} itemId=${item.localCatalogItemId ?? 'unknown'}',
      );
      _showPlaybackSnackBar(_localPlaybackLockedSnack);
      return;
    }
    final launchStopwatch = Stopwatch()..start();
    final basePlaybackKey = item.id;
    try {
      final cacheBasePlaybackKey = item.type.isLive
          ? 'liveTv:$basePlaybackKey'
          : basePlaybackKey;
      var playbackKey = _verifiedPlaybackKeyFor(cacheBasePlaybackKey);
      final hasVerifiedSource = playbackKey != null;
      final diagnosticType = item.type.isLive ? 'liveTv' : 'movie';
      DiagnosticLog.add(
        'details playback launch start type=$diagnosticType id=${item.id} titleLength=${title.length} verifiedCache=$hasVerifiedSource',
      );
      if (hasVerifiedSource) {
        DiagnosticLog.add(
          'details playback using verified source cache key=$playbackKey',
        );
      }
      final shouldResolveFreshSources =
          _shouldResolveFreshSourcesWithVerifiedCache(
            hasVerifiedSource: hasVerifiedSource,
          );
      final result = hasVerifiedSource && !shouldResolveFreshSources
          ? _emptyPlaybackResult
          : await _resolveMovieForActiveSources(item);
      playbackKey ??= _playbackCacheKeyForResult(cacheBasePlaybackKey, result);
      if (!mounted) return;
      final config = hasVerifiedSource && !shouldResolveFreshSources
          ? null
          : await _configFuture;
      if (!mounted) return;
      await _openResolvedPlayback(
        title,
        result,
        adBlock: config?.adBlock ?? AdBlockConfig.disabled,
        resolveNativeProvider: (providerId) =>
            _api.resolveMovieNativeSources(item, providerId: providerId),
        resolveSubtitles: () => _api.resolveMovieSubtitles(
          item,
          includeDefault: AppState.defaultSubtitlesEnabled.value,
        ),
        logoUrl: item.logo,
        artworkUrl: item.background ?? item.poster,
        progressItem: item.type.isLive ? null : item,
        playbackKey: playbackKey,
        progressSubtitle: item.type.isLive ? null : item.subtitle,
        liveMode: item.type.isLive,
        rewardedAdReason: item.type.isLive
            ? 'live_tv_playback'
            : 'movie_watch_now',
      );
      DiagnosticLog.add(
        'details playback launch ok type=$diagnosticType id=${item.id} elapsed=${launchStopwatch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      final diagnosticType = item.type.isLive ? 'liveTv' : 'movie';
      DiagnosticLog.add(
        'details playback launch failed type=$diagnosticType id=${item.id} elapsed=${launchStopwatch.elapsedMilliseconds}ms error=$error',
      );
      _rememberPlaybackLaunchFailure(basePlaybackKey, error);
      if (!mounted) return;
      _showPlaybackSnackBar(_friendlyPlaybackError(error));
    }
  }

  Future<void> _openSeriesPlayerSafely(
    String title,
    CatalogItem item, {
    List<EpisodeItem> episodes = const <EpisodeItem>[],
    EpisodeItem? startEpisode,
  }) async {
    final launchStopwatch = Stopwatch()..start();
    final effectiveStartEpisode =
        startEpisode ?? _firstPlayableEpisode(episodes);
    final season = effectiveStartEpisode?.season ?? 1;
    final episode = effectiveStartEpisode?.episode ?? 1;
    final basePlaybackKey = '${item.id}:$season:$episode';
    try {
      var playbackKey = _verifiedPlaybackKeyFor(basePlaybackKey);
      final nextEpisode = _nextEpisodeAfter(episodes, season, episode);
      final hasVerifiedSource = playbackKey != null;
      DiagnosticLog.add(
        'details playback launch start type=series id=${item.id} season=$season episode=$episode verifiedCache=$hasVerifiedSource',
      );
      if (hasVerifiedSource) {
        DiagnosticLog.add(
          'details playback using verified source cache key=$playbackKey',
        );
      }
      final shouldResolveFreshSources =
          _shouldResolveFreshSourcesWithVerifiedCache(
            hasVerifiedSource: hasVerifiedSource,
          );
      final result = hasVerifiedSource && !shouldResolveFreshSources
          ? _emptyPlaybackResult
          : await _resolveEpisodeForActiveSources(
              item,
              season: season,
              episode: episode,
              episodeItem: effectiveStartEpisode,
            );
      playbackKey ??= _playbackCacheKeyForResult(basePlaybackKey, result);
      if (!mounted) return;
      final config = hasVerifiedSource && !shouldResolveFreshSources
          ? null
          : await _configFuture;
      if (!mounted) return;
      await _openResolvedPlayback(
        effectiveStartEpisode == null ? title : '$title S$season E$episode',
        result,
        adBlock: config?.adBlock ?? AdBlockConfig.disabled,
        resolveNativeProvider: (providerId) => _api.resolveEpisodeNativeSources(
          item,
          season: season,
          episode: episode,
          providerId: providerId,
        ),
        resolveSubtitles: () => _api.resolveEpisodeSubtitles(
          item,
          season: season,
          episode: episode,
          includeDefault: AppState.defaultSubtitlesEnabled.value,
        ),
        logoUrl: item.logo,
        artworkUrl: item.background ?? item.poster,
        progressItem: item,
        playbackKey: playbackKey,
        progressSubtitle: 'S$season E$episode',
        nextEpisode: nextEpisode,
        episodeList: episodes,
        rewardedAdReason: 'episode_playback',
      );
      DiagnosticLog.add(
        'details playback launch ok type=series id=${item.id} season=$season episode=$episode elapsed=${launchStopwatch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      DiagnosticLog.add(
        'details playback launch failed type=series id=${item.id} elapsed=${launchStopwatch.elapsedMilliseconds}ms error=$error',
      );
      _rememberPlaybackLaunchFailure(basePlaybackKey, error);
      if (!mounted) return;
      _showPlaybackSnackBar(_friendlyPlaybackError(error));
    }
  }

  Future<void> _openEpisodePlayerSafely(
    String title,
    CatalogItem item, {
    required int season,
    required int episode,
    List<EpisodeItem> episodes = const <EpisodeItem>[],
  }) async {
    final launchStopwatch = Stopwatch()..start();
    final basePlaybackKey = '${item.id}:$season:$episode';
    try {
      var playbackKey = _verifiedPlaybackKeyFor(basePlaybackKey);
      final nextEpisode = _nextEpisodeAfter(episodes, season, episode);
      final hasVerifiedSource = playbackKey != null;
      DiagnosticLog.add(
        'details playback launch start type=episode id=${item.id} season=$season episode=$episode verifiedCache=$hasVerifiedSource',
      );
      if (hasVerifiedSource) {
        DiagnosticLog.add(
          'details playback using verified source cache key=$playbackKey',
        );
      }
      final shouldResolveFreshSources =
          _shouldResolveFreshSourcesWithVerifiedCache(
            hasVerifiedSource: hasVerifiedSource,
          );
      final result = hasVerifiedSource && !shouldResolveFreshSources
          ? _emptyPlaybackResult
          : await _resolveEpisodeForActiveSources(
              item,
              season: season,
              episode: episode,
              episodeItem: _episodeFor(episodes, season, episode),
            );
      playbackKey ??= _playbackCacheKeyForResult(basePlaybackKey, result);
      if (!mounted) return;
      final config = hasVerifiedSource && !shouldResolveFreshSources
          ? null
          : await _configFuture;
      if (!mounted) return;
      await _openResolvedPlayback(
        title,
        result,
        adBlock: config?.adBlock ?? AdBlockConfig.disabled,
        resolveNativeProvider: (providerId) => _api.resolveEpisodeNativeSources(
          item,
          season: season,
          episode: episode,
          providerId: providerId,
        ),
        resolveSubtitles: () => _api.resolveEpisodeSubtitles(
          item,
          season: season,
          episode: episode,
          includeDefault: AppState.defaultSubtitlesEnabled.value,
        ),
        logoUrl: item.logo,
        artworkUrl: item.background ?? item.poster,
        progressItem: item,
        playbackKey: playbackKey,
        progressSubtitle: 'S$season E$episode',
        nextEpisode: nextEpisode,
        episodeList: episodes,
        rewardedAdReason: 'episode_playback',
      );
      DiagnosticLog.add(
        'details playback launch ok type=episode id=${item.id} season=$season episode=$episode elapsed=${launchStopwatch.elapsedMilliseconds}ms',
      );
    } catch (error) {
      DiagnosticLog.add(
        'details playback launch failed type=episode id=${item.id} season=$season episode=$episode elapsed=${launchStopwatch.elapsedMilliseconds}ms error=$error',
      );
      _rememberPlaybackLaunchFailure(basePlaybackKey, error);
      if (!mounted) return;
      _showPlaybackSnackBar(_friendlyPlaybackError(error));
    }
  }

  String _friendlyPlaybackError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    if (text.isEmpty) return _videoUnavailableSnack;
    if (_isTemporaryResolverBlock(error)) {
      return _sourceSlowSnack;
    }
    if (text.contains('playable sources')) {
      return _videoUnavailableSnack;
    }
    return text;
  }

  Future<PlaybackResult> _resolveMovieForActiveSources(CatalogItem item) async {
    final stopwatch = Stopwatch()..start();
    if (item.type == MediaType.liveTv) {
      return _resolveLiveTvForPlayback(item, stopwatch: stopwatch);
    }
    _activateSingleUserAddonIfItIsTheOnlySource();
    if (AppState.userAddons.value.any((addon) => addon.active)) {
      try {
        final result = await _api.resolveMovieAddonStreams(item);
        DiagnosticLog.add(
          'details resolve movie addon ok id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms sources=${result.sources.length}',
        );
        return result;
      } on StreamApiException catch (error) {
        if (!_shouldTryDefaultAfterAddonError(error)) {
          rethrow;
        }
        DiagnosticLog.add(
          'details resolve movie addon fallback id=${item.id} reason=${_addonFallbackReason(error)}',
        );
      }
    }
    if (!AppState.defaultProvidersEnabled.value) {
      throw const StreamApiException('No stream source is active.');
    }
    final result = await _api.resolveMovie(item);
    DiagnosticLog.add(
      'details resolve movie default ok id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms sources=${result.sources.length}',
    );
    return result;
  }

  Future<PlaybackResult> _resolveLiveTvForPlayback(
    CatalogItem item, {
    required Stopwatch stopwatch,
  }) async {
    Object? lastError;
    for (
      var attempt = 0;
      attempt <= _liveTvResolveRetryDelays.length;
      attempt++
    ) {
      if (attempt > 0) {
        final delay = _liveTvResolveRetryDelays[attempt - 1];
        DiagnosticLog.add(
          'details resolve live tv retry wait id=${item.id} attempt=$attempt delayMs=${delay.inMilliseconds}',
        );
        await Future<void>.delayed(delay);
        if (!mounted) return _emptyPlaybackResult;
      }
      try {
        final sources = await _api.resolveMovieNativeSources(
          item,
          providerId: 'public-iptv',
        );
        DiagnosticLog.add(
          'details resolve live tv public-iptv ok id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms attempt=${attempt + 1} sources=${sources.length}',
        );
        if (sources.isNotEmpty) {
          return PlaybackResult(
            sources: sources,
            embeds: const <PlaybackCandidate>[],
            debug: PlaybackDebug.empty,
          );
        }
      } catch (error) {
        lastError = error;
        DiagnosticLog.add(
          'details resolve live tv public-iptv retryable id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms attempt=${attempt + 1} error=${error.runtimeType}',
        );
      }
    }

    if (lastError != null) {
      DiagnosticLog.add(
        'details resolve live tv exhausted id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms error=${lastError.runtimeType}',
      );
    } else {
      DiagnosticLog.add(
        'details resolve live tv exhausted id=${item.id} elapsed=${stopwatch.elapsedMilliseconds}ms sources=0',
      );
    }
    _playbackRetryAfterByKey[item.id] = DateTime.now().add(
      const Duration(seconds: 4),
    );
    return _emptyPlaybackResult;
  }

  Future<PlaybackResult> _resolveEpisodeForActiveSources(
    CatalogItem item, {
    required int season,
    required int episode,
    EpisodeItem? episodeItem,
  }) async {
    final stopwatch = Stopwatch()..start();
    if (item.isPersonalServerItem) {
      final episodeId = episodeItem?.id.trim() ?? '';
      final playableItem = episodeId.isEmpty
          ? item
          : CatalogItem(
              type: item.type,
              id: '${item.id}:$season:$episode',
              name: item.name,
              poster: episodeItem?.thumbnail ?? item.poster,
              background: item.background,
              logo: item.logo,
              year: item.year,
              genres: item.genres,
              description: episodeItem?.description ?? item.description,
              isLocalCatalogItem: item.isLocalCatalogItem,
              localPlaybackLocked: item.localPlaybackLocked,
              localCatalogId: item.localCatalogId,
              localCatalogItemId: item.localCatalogItemId,
              localCatalogName: item.localCatalogName,
              localMediaKind: item.localMediaKind,
              localSourceLabel: item.localSourceLabel,
              localRelinkNeededCount: item.localRelinkNeededCount,
              personalServerTypeId: item.personalServerTypeId,
              personalServerItemId: episodeId,
              personalServerSeriesItemId: item.personalServerItemId,
            );
      final result = await _api.resolveEpisode(
        playableItem,
        season: season,
        episode: episode,
      );
      DiagnosticLog.add(
        'details resolve episode personal-server ok type=${item.personalServerTypeId ?? "unknown"} elapsed=${stopwatch.elapsedMilliseconds}ms sources=${result.sources.length}',
      );
      return result;
    }
    _activateSingleUserAddonIfItIsTheOnlySource();
    if (AppState.userAddons.value.any((addon) => addon.active)) {
      try {
        final result = await _api.resolveEpisodeAddonStreams(
          item,
          season: season,
          episode: episode,
        );
        DiagnosticLog.add(
          'details resolve episode addon ok id=${item.id} season=$season episode=$episode elapsed=${stopwatch.elapsedMilliseconds}ms sources=${result.sources.length}',
        );
        return result;
      } on StreamApiException catch (error) {
        if (!_shouldTryDefaultAfterAddonError(error)) {
          rethrow;
        }
        DiagnosticLog.add(
          'details resolve episode addon fallback id=${item.id} season=$season episode=$episode reason=${_addonFallbackReason(error)}',
        );
      }
    }
    if (!AppState.defaultProvidersEnabled.value) {
      throw const StreamApiException('No stream source is active.');
    }
    final result = await _api.resolveEpisode(
      item,
      season: season,
      episode: episode,
    );
    DiagnosticLog.add(
      'details resolve episode default ok id=${item.id} season=$season episode=$episode elapsed=${stopwatch.elapsedMilliseconds}ms sources=${result.sources.length}',
    );
    return result;
  }

  void _activateSingleUserAddonIfItIsTheOnlySource() {
    if (AppState.defaultProvidersEnabled.value) return;
    final addons = AppState.userAddons.value;
    if (addons.length != 1 || addons.first.active) return;
    final addon = addons.first;
    DiagnosticLog.add(
      'details auto activated sole user add-on id=${addon.id} reason=no_other_stream_source',
    );
    AppState.updateUserAddon(addon.copyWith(active: true));
  }

  bool _shouldTryDefaultAfterAddonError(StreamApiException error) {
    if (!AppState.defaultProvidersEnabled.value) return false;
    final message = error.message;
    return message.contains('No active stream add-ons') ||
        message.contains('did not return playable sources');
  }

  String _addonFallbackReason(StreamApiException error) {
    final message = error.message;
    if (message.contains('did not return playable sources')) {
      return 'empty_addon_route';
    }
    if (message.contains('No active stream add-ons')) {
      return 'no_active_addon_route';
    }
    return 'addon_route_unavailable';
  }

  String? _verifiedPlaybackKeyFor(String? basePlaybackKey) {
    return NativePlayerPage.firstVerifiedSourceKey(
      _playbackCacheKeyCandidates(basePlaybackKey),
    );
  }

  List<String> _playbackCacheKeyCandidates(String? basePlaybackKey) {
    final base = basePlaybackKey?.trim();
    if (base == null || base.isEmpty) return const <String>[];
    return <String>[
      if (widget.item.isPersonalServerItem)
        'personal:${widget.item.personalServerTypeId}:$base',
      for (final addon in AppState.userAddons.value.where(
        (addon) => addon.active,
      ))
        'addon:${addon.id}:$base',
      'builtin:$base',
      // Compatibility for verified sources cached before namespacing existed.
      base,
    ];
  }

  String? _playbackCacheKeyForResult(
    String? basePlaybackKey,
    PlaybackResult result,
  ) {
    final base = basePlaybackKey?.trim();
    if (base == null || base.isEmpty) return null;
    for (final source in result.sources) {
      if (source.providerId.startsWith('personal-')) {
        return 'personal:${source.providerId.substring('personal-'.length)}:$base';
      }
      final addonId = _addonIdFromProvider(source.providerId);
      if (addonId != null) return 'addon:$addonId:$base';
    }
    return 'builtin:$base';
  }

  String? _addonIdFromProvider(String providerId) {
    final normalized = providerId.trim();
    if (!normalized.startsWith('addon-')) return null;
    final addonId = normalized.substring('addon-'.length).trim();
    return addonId.isEmpty ? null : addonId;
  }

  EpisodeItem? _nextEpisodeAfter(
    List<EpisodeItem> episodes,
    int season,
    int episode,
  ) {
    if (episodes.isEmpty) return null;
    final sorted = [...episodes]
      ..sort((a, b) {
        final seasonCompare = a.season.compareTo(b.season);
        if (seasonCompare != 0) return seasonCompare;
        return a.episode.compareTo(b.episode);
      });
    for (final item in sorted) {
      if (item.season > season ||
          (item.season == season && item.episode > episode)) {
        return item;
      }
    }
    return null;
  }

  EpisodeItem? _episodeFor(
    List<EpisodeItem> episodes,
    int season,
    int episode,
  ) {
    for (final item in episodes) {
      if (item.season == season && item.episode == episode) return item;
    }
    return null;
  }

  EpisodeItem? _firstPlayableEpisode(List<EpisodeItem> episodes) {
    if (episodes.isEmpty) return null;
    final sorted = episodes.toList(growable: false)
      ..sort((left, right) {
        final seasonCompare = left.season.compareTo(right.season);
        if (seasonCompare != 0) return seasonCompare;
        return left.episode.compareTo(right.episode);
      });
    return sorted.first;
  }

  Future<NativePlayerNextEpisode?> _buildNativeNextEpisode(
    CatalogItem item,
    EpisodeItem episode,
    List<EpisodeItem> episodes,
  ) async {
    final basePlaybackKey = '${item.id}:${episode.season}:${episode.episode}';
    var playbackKey = _verifiedPlaybackKeyFor(basePlaybackKey);
    final hasVerifiedSource = playbackKey != null;
    if (hasVerifiedSource) {
      DiagnosticLog.add(
        'details next episode using verified source cache key=$playbackKey',
      );
    }
    final result = hasVerifiedSource
        ? _emptyPlaybackResult
        : await _resolveEpisodeForActiveSources(
            item,
            season: episode.season,
            episode: episode.episode,
            episodeItem: episode,
          );
    playbackKey ??= _playbackCacheKeyForResult(basePlaybackKey, result);
    final sources = _orderSources(_nativeEligibleSources(result.sources));
    if (sources.length != result.sources.length) {
      DiagnosticLog.add(
        'nextEpisode source gate skipped count=${result.sources.length - sources.length}',
      );
    }
    final initialByProvider = <String, List<PlaybackSource>>{};
    for (final source in sources) {
      initialByProvider
          .putIfAbsent(source.providerId, () => <PlaybackSource>[])
          .add(source);
    }
    final addonProviderIds = initialByProvider.keys
        .where((providerId) => providerId.startsWith('addon-'))
        .toList();
    final personalProviderIds = initialByProvider.keys
        .where((providerId) => providerId.startsWith('personal-'))
        .toList();
    final useAddonOnly =
        AppState.userAddons.value.any((addon) => addon.active) &&
        addonProviderIds.isNotEmpty;
    final defaultProviderSelection = _defaultNativeProviderSelectionForPlayback(
      playbackKey: playbackKey,
      mediaKey: basePlaybackKey,
      initialProviderIds: initialByProvider.keys.toSet(),
      hasAddonSources: addonProviderIds.isNotEmpty,
      useAddonOnly: useAddonOnly || personalProviderIds.isNotEmpty,
    );
    final verifiedCacheRequests = _verifiedCacheProviderRequestsFor(
      playbackKey,
    );
    final verifiedCacheProviderIds = verifiedCacheRequests
        .map((request) => request.providerId)
        .toSet();
    final prioritizedResolvedProviderIds = <String>{
      ...verifiedCacheProviderIds,
      ...personalProviderIds,
      ...addonProviderIds,
      ...defaultProviderSelection.providerIds,
    };
    final remainingResolvedProviderIds = initialByProvider.keys
        .where(
          (providerId) =>
              !prioritizedResolvedProviderIds.contains(providerId) &&
              (initialByProvider[providerId]?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    final requests = [
      ...verifiedCacheRequests,
      for (final providerId in personalProviderIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      for (final providerId in addonProviderIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      for (final providerId in defaultProviderSelection.providerIds)
        if (!verifiedCacheProviderIds.contains(providerId))
          NativePlaybackRequest(
            providerId: providerId,
            sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
          ),
      for (final providerId in remainingResolvedProviderIds)
        NativePlaybackRequest(
          providerId: providerId,
          sources: initialByProvider[providerId] ?? const <PlaybackSource>[],
        ),
    ];
    final nextEpisode = _nextEpisodeAfter(
      episodes,
      episode.season,
      episode.episode,
    );

    return NativePlayerNextEpisode(
      title: '${item.name} S${episode.season} E${episode.episode}',
      sources: requests,
      resolveProvider: (providerId) => _api.resolveEpisodeNativeSources(
        item,
        season: episode.season,
        episode: episode.episode,
        providerId: providerId,
      ),
      resolveSubtitles: () => _api.resolveEpisodeSubtitles(
        item,
        season: episode.season,
        episode: episode.episode,
        includeDefault: AppState.defaultSubtitlesEnabled.value,
      ),
      logoUrl: item.logo,
      progressItem: item,
      playbackKey: playbackKey,
      progressSubtitle: 'S${episode.season} E${episode.episode}',
      nextEpisodeLabel: nextEpisode == null ? null : 'Next episode',
      onNextEpisode: nextEpisode == null
          ? null
          : () => _buildNativeNextEpisode(item, nextEpisode, episodes),
      limitToFirstQualityPass: defaultProviderSelection.cappedColdScan,
    );
  }

  List<PlaybackSource> _orderSources(List<PlaybackSource> sources) {
    final selected = AppState.selectedNativeProviderId;
    final selectedIndex = sources.indexWhere(
      (source) => source.providerId == selected,
    );
    if (selectedIndex < 0) return sources;
    return [...sources.skip(selectedIndex), ...sources.take(selectedIndex)];
  }

  ContinueWatchingEntry? _latestEpisodeProgress(
    CatalogItem item,
    List<EpisodeItem> episodes,
  ) {
    final progress = AppState.continueWatching.value;
    if (episodes.isEmpty) return null;

    final episodeKeys = {
      for (final episode in episodes) _episodeProgressKey(item, episode),
    };
    final entries =
        progress.values
            .where(
              (entry) => episodeKeys.contains(
                AppState.contentPlaybackKeyFor(item, entry.key),
              ),
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return entries.isNotEmpty ? entries.first : null;
  }

  EpisodeItem? _episodeForProgress(
    CatalogItem item,
    List<EpisodeItem> episodes,
    ContinueWatchingEntry? entry,
  ) {
    if (entry == null || episodes.isEmpty) return null;
    final contentKey = AppState.contentPlaybackKeyFor(item, entry.key);
    for (final episode in episodes) {
      if (_episodeProgressKey(item, episode) == contentKey) return episode;
    }
    return null;
  }

  CompletedWatchingEntry? _completedEntryForItem(
    Map<String, CompletedWatchingEntry> completed,
    CatalogItem item,
  ) {
    final direct = completed[item.id];
    if (direct != null) return direct;
    for (final entry in completed.values) {
      if (entry.item.id == item.id) return entry;
    }
    return null;
  }

  String? _completedSummaryLabel(
    Map<String, CompletedWatchingEntry> completed,
    CatalogItem item,
  ) {
    if (item.type.isPlayableSeries) {
      final entries = completed.values
          .where((entry) => entry.item.id == item.id)
          .toList(growable: false);
      if (entries.isEmpty) return null;
      final episodeCount = entries.length;
      final totalWatches = entries.fold<int>(
        0,
        (total, entry) => total + entry.completionCount,
      );
      if (totalWatches > episodeCount) {
        return '$episodeCount episodes watched, $totalWatches total finishes';
      }
      return episodeCount == 1
          ? '1 episode watched'
          : '$episodeCount episodes watched';
    }
    final entry = _completedEntryForItem(completed, item);
    if (entry == null) return null;
    return entry.completionCount > 1
        ? 'Watched ${entry.completionCount}x'
        : 'Watched once';
  }

  String _episodeProgressKey(CatalogItem item, EpisodeItem episode) {
    return '${item.id}:${episode.season}:${episode.episode}';
  }

  String _seriesResumeLabel(EpisodeItem? episode, ContinueWatchingEntry entry) {
    if (episode == null) {
      final subtitle = entry.subtitle?.trim();
      if (subtitle != null && subtitle.isNotEmpty) return 'Continue $subtitle';
      return 'Continue watching';
    }
    return 'Continue S${episode.season} E${episode.episode}';
  }

  Future<List<CatalogItem>> _loadRecommendations(CatalogItem item) async {
    if (item.type.isLive || item.type == MediaType.nsfw) {
      return const <CatalogItem>[];
    }
    final recommendations = <CatalogItem>[];
    final seen = <String>{item.id.toLowerCase()};
    final sourceGenres = _recommendationGenreSet(item);
    final sourceIsAnimation = _recommendationLooksAnimated(item);

    bool addCandidate(CatalogItem candidate) {
      final key = candidate.id.toLowerCase();
      final sameTmdb = item.tmdbId != null && candidate.tmdbId == item.tmdbId;
      if (key.isEmpty || seen.contains(key) || sameTmdb) return false;
      if ((candidate.poster ?? '').trim().isEmpty) return false;
      if (!_recommendationCandidateFits(
        source: item,
        candidate: candidate,
        sourceGenres: sourceGenres,
        sourceIsAnimation: sourceIsAnimation,
      )) {
        return false;
      }
      seen.add(key);
      recommendations.add(candidate);
      return true;
    }

    Future<void> addTmdbRecommendations() async {
      try {
        final result = await _api.recommendations(item);
        for (final candidate in result) {
          addCandidate(candidate);
          if (recommendations.length >= 12) return;
        }
      } catch (error) {
        if (_disposed) return;
        DiagnosticLog.add(
          'details tmdb recommendations failed type=${item.type.compatTypeValue} id=${item.id} error=$error',
        );
      }
    }

    await addTmdbRecommendations();
    if (_disposed) return const <CatalogItem>[];
    final tmdbCount = recommendations.length;
    DiagnosticLog.add(
      'details recommendations loaded id=${item.id} count=${recommendations.length} tmdb=$tmdbCount source=backend',
    );
    return List<CatalogItem>.unmodifiable(recommendations.take(12));
  }

  bool _recommendationCandidateFits({
    required CatalogItem source,
    required CatalogItem candidate,
    required Set<String> sourceGenres,
    required bool sourceIsAnimation,
  }) {
    if (source.type != candidate.type) return false;
    final candidateGenres = _recommendationGenreSet(candidate);
    if (sourceGenres.isNotEmpty && candidateGenres.isNotEmpty) {
      final hasOverlap = candidateGenres.any(sourceGenres.contains);
      if (!hasOverlap) return false;
    }
    if (source.type == MediaType.series &&
        !sourceIsAnimation &&
        _recommendationLooksAnimated(candidate)) {
      return false;
    }
    return true;
  }

  double _recommendationScore({
    required CatalogItem source,
    required CatalogItem candidate,
    required Set<String> sourceGenres,
    required bool sourceIsAnimation,
  }) {
    var score = 0.0;
    final candidateGenres = _recommendationGenreSet(candidate);
    for (final genre in candidateGenres) {
      if (sourceGenres.contains(genre)) score += 18;
    }
    score += _recommendationRating(candidate) * 2;
    score += math.min<double>((candidate.voteCount ?? 0) / 2500, 6.0);
    if (candidate.poster != null && candidate.background != null) score += 2;
    if (candidate.logo != null && candidate.logo!.trim().isNotEmpty) {
      score += 1.5;
    }
    if (sourceIsAnimation && _recommendationLooksAnimated(candidate)) {
      score += 8;
    }
    final sourceYear = _recommendationYear(source);
    final candidateYear = _recommendationYear(candidate);
    if (sourceYear != null && candidateYear != null) {
      final distance = (sourceYear - candidateYear).abs();
      score += math.max<double>(0.0, 8.0 - distance.toDouble());
    }
    if (candidate.isUpcoming && !source.isUpcoming) score -= 25;
    return score;
  }

  Set<String> _recommendationGenreSet(CatalogItem item) {
    return item.genres
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty && value != 'all genres')
        .toSet();
  }

  bool _recommendationLooksAnimated(CatalogItem item) {
    if (item.type == MediaType.animation) return true;
    final text = [item.name, ...item.genres].join(' ').toLowerCase();
    return text.contains('animation') || text.contains('animated');
  }

  double _recommendationRating(CatalogItem item) {
    return double.tryParse((item.imdbRating ?? '').trim()) ?? 0;
  }

  int? _recommendationYear(CatalogItem item) {
    final raw = item.year?.trim();
    if (raw == null || raw.length < 4) return null;
    return int.tryParse(raw.substring(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isLocalCatalogItem) {
      return _buildLocalDetailsPage(context);
    }
    return FutureBuilder<MetaDetails>(
      future: _detailsFuture,
      builder: (context, snapshot) {
        final details = snapshot.data;
        final item = details == null
            ? widget.item
            : _mergeDetailsMetadataArtwork(details.item, widget.item);
        final canStartPlayback = !item.isUpcoming;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          body: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: item.type.isLive ? 258 : 300,
                pinned: true,
                stretch: true,
                titleSpacing: 0,
                backgroundColor: colorScheme.surface,
                foregroundColor: _showCollapsedTitle
                    ? colorScheme.onSurface
                    : Colors.white,
                iconTheme: IconThemeData(
                  color: _showCollapsedTitle
                      ? colorScheme.onSurface
                      : Colors.white,
                ),
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: _showCollapsedTitle
                        ? colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.9,
                          )
                        : JuicrVisual.floatingActionSurface(colorScheme),
                    elevation: _showCollapsedTitle ? 0 : 3,
                    shadowColor: JuicrVisual.floatingActionShadow(colorScheme),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                      color: _showCollapsedTitle
                          ? colorScheme.onSurface
                          : Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: _showCollapsedTitle
                            ? colorScheme.onSurface
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
                actions: [
                  FutureBuilder<List<TrailerItem>>(
                    future: _trailersFuture,
                    builder: (context, trailerSnapshot) {
                      final trailers =
                          trailerSnapshot.data ?? const <TrailerItem>[];
                      if (loading || trailers.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: FilledButton.tonalIcon(
                          onPressed: _openingTrailer
                              ? null
                              : () => _openTrailer(item.name, trailers),
                          icon: _openingTrailer
                              ? _PlaybackBusyIcon(
                                  animation: _trailerBusyController,
                                )
                              : const Icon(
                                  Icons.movie_filter_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            _openingTrailer ? 'Loading...' : 'Watch trailer',
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.58,
                            ),
                            elevation: 3,
                            shadowColor: Colors.black.withValues(alpha: 0.42),
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                title: _showCollapsedTitle
                    ? JuicrAutoScrollText(text: item.name, height: 22)
                    : null,
                flexibleSpace: FlexibleSpaceBar(
                  background: _HeroMedia(item: item),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    item.type.isLive ? 12 : 10,
                    18,
                    18 + MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.name.trim().isNotEmpty) ...[
                        JuicrAutoScrollText(
                          text: item.name,
                          height: 34,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                      if (loading) ...[
                        const SizedBox(height: 12),
                        const _DetailsLoadingPill(),
                        const SizedBox(height: 12),
                        const _DetailsLoadingBody(),
                      ] else ...[
                        if (item.name.trim().isNotEmpty)
                          SizedBox(height: item.type.isLive ? 12 : 8),
                        AppReveal(
                          child: _MetadataStrip(item: item, details: details),
                        ),
                        ValueListenableBuilder<
                          Map<String, CompletedWatchingEntry>
                        >(
                          valueListenable: AppState.completedWatching,
                          builder: (context, completed, _) {
                            return ValueListenableBuilder<
                              Map<String, ContinueWatchingEntry>
                            >(
                              valueListenable: AppState.continueWatching,
                              builder: (context, progress, _) {
                                if (!item.type.isPlayableSeries &&
                                    _completedEntryForItem(completed, item) !=
                                        null) {
                                  return const SizedBox.shrink();
                                }
                                final entry = item.type.isPlayableSeries
                                    ? _latestEpisodeProgress(
                                        item,
                                        details?.videos ??
                                            const <EpisodeItem>[],
                                      )
                                    : item.type.isLive
                                    ? null
                                    : progress[item.id];
                                if (entry == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _ContinueProgressPill(entry: entry),
                                );
                              },
                            );
                          },
                        ),
                        if (!item.type.isLive)
                          ValueListenableBuilder<
                            Map<String, CompletedWatchingEntry>
                          >(
                            valueListenable: AppState.completedWatching,
                            builder: (context, completed, _) {
                              final label = _completedSummaryLabel(
                                completed,
                                item,
                              );
                              if (label == null) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: _EpisodeCompletedPill(label: label),
                              );
                            },
                          ),
                      ],
                      if (!loading) ...[
                        const SizedBox(height: 12),
                        ValueListenableBuilder<Map<String, CatalogItem>>(
                          valueListenable: AppState.library,
                          builder: (context, library, _) {
                            return AppReveal(
                              delay: const Duration(milliseconds: 70),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: !item.type.isPlayableSeries
                                        ? ValueListenableBuilder<
                                            Map<String, CompletedWatchingEntry>
                                          >(
                                            valueListenable:
                                                AppState.completedWatching,
                                            builder: (context, completed, _) {
                                              final hasCompleted =
                                                  !item.type.isLive &&
                                                  _completedEntryForItem(
                                                        completed,
                                                        item,
                                                      ) !=
                                                      null;
                                              final openPrimary =
                                                  _openingPlayback ||
                                                      !canStartPlayback
                                                  ? null
                                                  : () => unawaited(
                                                      _openMovieFromDetailsPrimary(
                                                        item,
                                                        hasCompleted:
                                                            hasCompleted,
                                                      ),
                                                    );
                                              return GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: openPrimary,
                                                child: FilledButton.icon(
                                                  onPressed: openPrimary,
                                                  style: FilledButton.styleFrom(
                                                    minimumSize: const Size(
                                                      0,
                                                      _detailsPrimaryActionHeight,
                                                    ),
                                                    fixedSize:
                                                        const Size.fromHeight(
                                                          _detailsPrimaryActionHeight,
                                                        ),
                                                    textStyle:
                                                        _detailsPrimaryActionTextStyle,
                                                  ),
                                                  icon: _openingPlayback
                                                      ? _PlaybackBusyIcon(
                                                          animation:
                                                              _playbackBusyController,
                                                          size:
                                                              _detailsPrimaryActionIconSize,
                                                        )
                                                      : Icon(
                                                          !canStartPlayback
                                                              ? Icons
                                                                    .event_available_rounded
                                                              : hasCompleted
                                                              ? Icons
                                                                    .replay_rounded
                                                              : Icons
                                                                    .play_arrow,
                                                          size:
                                                              _detailsPrimaryActionIconSize,
                                                        ),
                                                  label:
                                                      ValueListenableBuilder<
                                                        Map<
                                                          String,
                                                          ContinueWatchingEntry
                                                        >
                                                      >(
                                                        valueListenable: AppState
                                                            .continueWatching,
                                                        builder: (context, progress, _) {
                                                          if (_openingPlayback) {
                                                            return const Text(
                                                              'Please wait...',
                                                            );
                                                          }
                                                          if (!canStartPlayback) {
                                                            return const Text(
                                                              'Coming soon',
                                                            );
                                                          }
                                                          final hasProgress =
                                                              !item
                                                                  .type
                                                                  .isLive &&
                                                              progress[item
                                                                      .id] !=
                                                                  null;
                                                          return Text(
                                                            hasCompleted
                                                                ? 'Rewatch'
                                                                : hasProgress
                                                                ? 'Continue watching'
                                                                : 'Watch now',
                                                          );
                                                        },
                                                      ),
                                                ),
                                              );
                                            },
                                          )
                                        : ValueListenableBuilder<
                                            Map<String, ContinueWatchingEntry>
                                          >(
                                            valueListenable:
                                                AppState.continueWatching,
                                            builder: (context, _, __) {
                                              final episodes =
                                                  details?.videos ??
                                                  const <EpisodeItem>[];
                                              final entry =
                                                  _latestEpisodeProgress(
                                                    item,
                                                    episodes,
                                                  );
                                              final resumeEpisode =
                                                  _episodeForProgress(
                                                    item,
                                                    episodes,
                                                    entry,
                                                  );
                                              final label = entry == null
                                                  ? 'Watch now'
                                                  : _seriesResumeLabel(
                                                      resumeEpisode,
                                                      entry,
                                                    );
                                              return FilledButton.tonalIcon(
                                                onPressed:
                                                    _openingPlayback ||
                                                        !canStartPlayback
                                                    ? null
                                                    : () async {
                                                        final launchKey =
                                                            resumeEpisode ==
                                                                null
                                                            ? entry?.key ??
                                                                  '${item.id}:1:1'
                                                            : _episodeProgressKey(
                                                                item,
                                                                resumeEpisode,
                                                              );
                                                        if (mounted) {
                                                          setState(() {
                                                            _openingEpisodeKey =
                                                                launchKey;
                                                          });
                                                        }
                                                        try {
                                                          await _runPlaybackLaunch(
                                                            () async {
                                                              DiagnosticLog.screen(
                                                                context,
                                                                'Details open series press',
                                                              );
                                                              DiagnosticLog.add(
                                                                'details open series pressed id=${item.id} resumeKey=${entry?.key} launchKey=$launchKey',
                                                              );
                                                              await _openSeriesPlayerSafely(
                                                                item.name,
                                                                item,
                                                                episodes:
                                                                    episodes,
                                                                startEpisode:
                                                                    resumeEpisode,
                                                              );
                                                            },
                                                            launchKey:
                                                                launchKey,
                                                          );
                                                        } finally {
                                                          if (mounted &&
                                                              _openingEpisodeKey ==
                                                                  launchKey) {
                                                            setState(() {
                                                              _openingEpisodeKey =
                                                                  null;
                                                            });
                                                          }
                                                        }
                                                      },
                                                style: FilledButton.styleFrom(
                                                  minimumSize: const Size(
                                                    0,
                                                    _detailsPrimaryActionHeight,
                                                  ),
                                                  fixedSize: const Size.fromHeight(
                                                    _detailsPrimaryActionHeight,
                                                  ),
                                                  textStyle:
                                                      _detailsPrimaryActionTextStyle,
                                                ),
                                                icon: _openingPlayback
                                                    ? _PlaybackBusyIcon(
                                                        animation:
                                                            _playbackBusyController,
                                                        size:
                                                            _detailsPrimaryActionIconSize,
                                                      )
                                                    : Icon(
                                                        !canStartPlayback
                                                            ? Icons
                                                                  .event_available_rounded
                                                            : entry == null
                                                            ? Icons.play_arrow
                                                            : Icons
                                                                  .history_rounded,
                                                        size:
                                                            _detailsPrimaryActionIconSize,
                                                      ),
                                                label: Text(
                                                  _openingPlayback
                                                      ? 'Please wait...'
                                                      : !canStartPlayback
                                                      ? 'Coming soon'
                                                      : label,
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                  const SizedBox(
                                    width: _DetailsPageState
                                        ._detailsPrimaryActionGap,
                                  ),
                                  SizedBox.square(
                                    dimension: 48,
                                    child: Material(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.24,
                                      ),
                                      elevation: 3,
                                      shadowColor:
                                          JuicrVisual.floatingActionShadow(
                                            colorScheme,
                                          ),
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        tooltip: 'Save and lists',
                                        onPressed: () =>
                                            _showAddToListSheet(item),
                                        icon: const Icon(
                                          Icons.more_horiz_rounded,
                                        ),
                                        color: Colors.white,
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      if (snapshot.hasError) ...[
                        const SizedBox(height: 12),
                        AppReveal(
                          delay: const Duration(milliseconds: 95),
                          child: _InlineError(
                            message:
                                'Some details could not be refreshed right now.',
                          ),
                        ),
                      ],
                      if (!loading &&
                          item.description != null &&
                          item.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppReveal(
                          delay: const Duration(milliseconds: 120),
                          child: _DescriptionBlock(text: item.description!),
                        ),
                      ],
                      if (!loading && item.genres.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        AppReveal(
                          delay: const Duration(milliseconds: 150),
                          child: _ChipWrap(
                            values: item.genres,
                            onSelected: (genre) =>
                                _openGenreInDiscovery(item, genre),
                          ),
                        ),
                      ],
                      if (!loading && !item.type.isLive) ...[
                        const SizedBox(height: 18),
                        const SizedBox(
                          width: double.infinity,
                          child: JuicrBannerAdSlot(placement: 'details_lower'),
                        ),
                      ],
                      if (!loading)
                        AppReveal(
                          delay: const Duration(milliseconds: 165),
                          child: _RecommendationsSection(
                            item: item,
                            future: _recommendationsFuture,
                          ),
                        ),
                      if (details != null &&
                          _hasPeople(details.cast, details.director)) ...[
                        const SizedBox(height: 12),
                        AppReveal(
                          delay: const Duration(milliseconds: 180),
                          child: _PeopleSection(
                            cast: details.cast,
                            director: details.director,
                            castPeople: details.castPeople,
                            directorPeople: details.directorPeople,
                          ),
                        ),
                      ],
                      if (details != null &&
                          _shouldShowEpisodeLayout(item, details)) ...[
                        const SizedBox(height: 12),
                        AppReveal(
                          delay: const Duration(milliseconds: 220),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Episodes',
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 12),
                              _EpisodeList(
                                item: item,
                                episodes: details.videos,
                                playbackLocked: item.isUpcoming,
                                busy: _openingPlayback,
                                busyEpisodeKey: _openingEpisodeKey,
                                busyAnimation: _playbackBusyController,
                                onPlay: (episode) async {
                                  final episodeKey =
                                      '${item.id}:${episode.season}:${episode.episode}';
                                  if (mounted) {
                                    setState(() {
                                      _openingEpisodeKey = episodeKey;
                                    });
                                  }
                                  try {
                                    await _runPlaybackLaunch(() async {
                                      await _openEpisodePlayerSafely(
                                        '${item.name} S${episode.season} E${episode.episode}',
                                        item,
                                        season: episode.season,
                                        episode: episode.episode,
                                        episodes: details.videos,
                                      );
                                    }, launchKey: episodeKey);
                                  } finally {
                                    if (mounted &&
                                        _openingEpisodeKey == episodeKey) {
                                      setState(() {
                                        _openingEpisodeKey = null;
                                      });
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  CatalogItem _currentLocalCatalogItem() {
    final catalogId = widget.item.localCatalogId ?? '';
    final itemId = widget.item.localCatalogItemId ?? '';
    final catalog = AppState.localCatalogById(catalogId);
    final localItem = AppState.localCatalogItemById(itemId);
    if (catalog != null && localItem != null) {
      return widget.item.merge(
        AppState.localCatalogSurfaceItem(catalog, localItem),
      );
    }
    return widget.item;
  }

  String? _localRuntimeLabel(int? runtimeSeconds) {
    if (runtimeSeconds == null || runtimeSeconds <= 0) return null;
    final totalMinutes = (runtimeSeconds / 60).round();
    if (totalMinutes <= 0) return null;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${totalMinutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  Future<void> _showEditLocalCatalogItemDialog(CatalogItem item) async {
    final catalogId = item.localCatalogId ?? '';
    final itemId = item.localCatalogItemId ?? '';
    final catalog = AppState.localCatalogById(catalogId);
    final localItem = AppState.localCatalogItemById(itemId);
    if (catalog == null || localItem == null) {
      _showPlaybackSnackBar('This item cannot be edited.');
      return;
    }
    final result = await showDialog<_LocalDetailsEditResult>(
      context: context,
      builder: (context) =>
          _LocalDetailsEditDialog(catalogName: catalog.name, item: localItem),
    );
    if (result == null) return;
    AppState.updateLocalCatalogItemMetadata(
      id: localItem.id,
      title: result.title,
      description: result.description,
      mediaKind: result.mediaKind,
      tags: result.tags,
      releaseYear: result.releaseYear,
      runtimeSeconds: result.runtimeSeconds,
      posterUrl: result.posterUrl,
      backgroundUrl: result.backgroundUrl,
      preferredPlaybackEngine: result.preferredPlaybackEngine,
    );
    DiagnosticLog.add(
      'details local catalog item metadata updated containsPath=false containsUri=false containsHandle=false playbackLocked=true',
    );
    if (!mounted) return;
    setState(() {});
    _showPlaybackSnackBar('Details updated.');
  }

  Widget _buildLocalDetailsPage(BuildContext context) {
    final item = _currentLocalCatalogItem();
    final localItem = AppState.localCatalogItemById(
      item.localCatalogItemId ?? '',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final catalogName = item.localCatalogName?.trim().isNotEmpty == true
        ? item.localCatalogName!.trim()
        : 'Private shelf';
    final relinkNeededCount = item.localRelinkNeededCount ?? 0;
    final metadataValues = <String>[
      'Local',
      if (item.localMediaKind?.trim().isNotEmpty == true)
        item.localMediaKind!.trim(),
      if (item.year?.trim().isNotEmpty == true) item.year!.trim(),
      if ((localItem?.preferredPlaybackEngine ?? 'auto') != 'auto')
        'Prefers ${localItem!.preferredPlaybackEngine}',
      if (_localRuntimeLabel(localItem?.runtimeSeconds) case final runtime?)
        runtime,
    ];

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            titleSpacing: 0,
            backgroundColor: colorScheme.surface,
            foregroundColor: _showCollapsedTitle
                ? colorScheme.onSurface
                : Colors.white,
            iconTheme: IconThemeData(
              color: _showCollapsedTitle ? colorScheme.onSurface : Colors.white,
            ),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: _showCollapsedTitle
                    ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.9)
                    : JuicrVisual.floatingActionSurface(colorScheme),
                elevation: _showCollapsedTitle ? 0 : 3,
                shadowColor: JuicrVisual.floatingActionShadow(colorScheme),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                  color: _showCollapsedTitle
                      ? colorScheme.onSurface
                      : Colors.white,
                ),
              ),
            ),
            title: _showCollapsedTitle
                ? JuicrAutoScrollText(text: item.name, height: 22)
                : null,
            flexibleSpace: FlexibleSpaceBar(background: _HeroMedia(item: item)),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                12,
                18,
                18 + MediaQuery.paddingOf(context).bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.name.trim().isNotEmpty)
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  const SizedBox(height: 12),
                  if (metadataValues.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in metadataValues)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(
                                JuicrVisual.pillRadius,
                              ),
                              border: Border.all(
                                color: colorScheme.primary.withValues(
                                  alpha: 0.14,
                                ),
                              ),
                            ),
                            child: Text(
                              value,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.76,
                                    ),
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: JuicrVisual.softPanel(
                      colorScheme,
                      color: colorScheme.surfaceContainerHigh,
                      radius: JuicrVisual.cardRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          catalogName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          relinkNeededCount > 0
                              ? relinkNeededCount == 1
                                    ? '1 local video still needs to be re-picked on this device.'
                                    : '$relinkNeededCount local video references still need to be re-picked on this device.'
                              : 'Metadata is visible across Catalog Builder surfaces, but playback remains locked until scoped local playback proof is completed.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            _openMoviePlayerSafely(item.name, item),
                        icon: const Icon(Icons.lock_outline_rounded),
                        label: const Text('Playback locked'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showEditLocalCatalogItemDialog(item),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('Edit details'),
                      ),
                    ],
                  ),
                  if (item.description?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      item.description!.trim(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.45,
                        color: colorScheme.onSurface.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _ChipWrap(values: item.genres, onSelected: (_) {}),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalDetailsEditResult {
  const _LocalDetailsEditResult({
    required this.title,
    required this.description,
    required this.mediaKind,
    required this.tags,
    required this.releaseYear,
    required this.runtimeSeconds,
    required this.posterUrl,
    required this.backgroundUrl,
    required this.preferredPlaybackEngine,
  });

  final String title;
  final String description;
  final String mediaKind;
  final List<String> tags;
  final int? releaseYear;
  final int? runtimeSeconds;
  final String posterUrl;
  final String backgroundUrl;
  final String preferredPlaybackEngine;
}

class _LocalDetailsEditDialog extends StatefulWidget {
  const _LocalDetailsEditDialog({
    required this.catalogName,
    required this.item,
  });

  final String catalogName;
  final LocalCatalogItem item;

  @override
  State<_LocalDetailsEditDialog> createState() =>
      _LocalDetailsEditDialogState();
}

class _LocalDetailsEditDialogState extends State<_LocalDetailsEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _tagsController;
  late final TextEditingController _yearController;
  late final TextEditingController _runtimeController;
  late final TextEditingController _posterController;
  late final TextEditingController _backgroundController;
  late String _mediaKind;
  late String _preferredPlaybackEngine;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _descriptionController = TextEditingController(
      text: widget.item.description,
    );
    _tagsController = TextEditingController(text: widget.item.tags.join(', '));
    _yearController = TextEditingController(
      text: widget.item.releaseYear?.toString() ?? '',
    );
    final runtimeMinutes = widget.item.runtimeSeconds == null
        ? null
        : (widget.item.runtimeSeconds! / 60).round();
    _runtimeController = TextEditingController(
      text: runtimeMinutes == null || runtimeMinutes <= 0
          ? ''
          : runtimeMinutes.toString(),
    );
    _posterController = TextEditingController(text: widget.item.posterUrl);
    _backgroundController = TextEditingController(
      text: widget.item.backgroundUrl,
    );
    _mediaKind = _normalizedLocalMediaKind(widget.item.mediaKind);
    _preferredPlaybackEngine = _normalizedLocalPlaybackEngine(
      widget.item.preferredPlaybackEngine,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _yearController.dispose();
    _runtimeController.dispose();
    _posterController.dispose();
    _backgroundController.dispose();
    super.dispose();
  }

  String _normalizedLocalMediaKind(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'series' || 'episode' => 'series',
      'animation' => 'animation',
      _ => 'movie',
    };
  }

  String _normalizedLocalPlaybackEngine(String value) {
    final normalized = value.trim().toLowerCase();
    return switch (normalized) {
      'exoplayer' => 'exoplayer',
      'libvlc' => 'libvlc',
      _ => 'auto',
    };
  }

  String? _safeArtworkValidator(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Use an http(s) artwork URL, not a local path';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return 'Only http(s) artwork URLs are allowed here';
    }
    return null;
  }

  int? _optionalPositiveInt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final runtimeMinutes = _optionalPositiveInt(_runtimeController.text);
    Navigator.of(context).pop(
      _LocalDetailsEditResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        mediaKind: _mediaKind,
        tags: tags,
        releaseYear: _optionalPositiveInt(_yearController.text),
        runtimeSeconds: runtimeMinutes == null ? null : runtimeMinutes * 60,
        posterUrl: _posterController.text.trim(),
        backgroundUrl: _backgroundController.text.trim(),
        preferredPlaybackEngine: _preferredPlaybackEngine,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.item.title}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Private metadata only in ${widget.catalogName}. Artwork accepts http(s) image links only. No local files, paths, picker handles, or playback state are edited here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Add a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 2,
                maxLines: 4,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _mediaKind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'movie', child: Text('Movie')),
                  DropdownMenuItem(value: 'series', child: Text('Series')),
                  DropdownMenuItem(
                    value: 'animation',
                    child: Text('Animation'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _mediaKind = value);
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  helperText: 'Comma-separated, private details only',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(labelText: 'Release year'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _runtimeController,
                decoration: const InputDecoration(labelText: 'Runtime minutes'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _posterController,
                decoration: const InputDecoration(
                  labelText: 'Poster image URL',
                  helperText: 'http(s) only; local paths stay blocked',
                ),
                keyboardType: TextInputType.url,
                validator: _safeArtworkValidator,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _backgroundController,
                decoration: const InputDecoration(
                  labelText: 'Background image URL',
                  helperText: 'http(s) only; local paths stay blocked',
                ),
                keyboardType: TextInputType.url,
                validator: _safeArtworkValidator,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _preferredPlaybackEngine,
                decoration: const InputDecoration(
                  labelText: 'Preferred native engine',
                  helperText:
                      'Saved as private details; playback is still locked',
                ),
                items: const [
                  DropdownMenuItem(value: 'auto', child: Text('Auto')),
                  DropdownMenuItem(value: 'exoplayer', child: Text('Media3')),
                  DropdownMenuItem(value: 'libvlc', child: Text('libVLC')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _preferredPlaybackEngine = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

int _episodeMetadataScore(EpisodeItem episode) {
  var score = 0;
  if (episode.title.trim().isNotEmpty) score += 2;
  if (episode.description?.trim().isNotEmpty == true) score += 2;
  if (episode.thumbnail?.trim().isNotEmpty == true) score += 1;
  return score;
}

bool _isTemporaryResolverBlock(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('rate limit') ||
      text.contains('temporarily blocked') ||
      text.contains('taking longer than usual') ||
      text.contains('429') ||
      text.contains('too many requests');
}

class _MetadataStrip extends StatelessWidget {
  const _MetadataStrip({required this.item, required this.details});

  final CatalogItem item;
  final MetaDetails? details;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final values = <String>[
      item.type.label,
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.imdbRating != null && item.imdbRating!.isNotEmpty)
        'IMDb ${item.imdbRating}',
      if (details?.runtime != null && details!.runtime!.isNotEmpty)
        _formatRuntimeChip(details!.runtime!),
    ];
    if (values.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values
          .map(
            (value) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(JuicrVisual.pillRadius),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                ),
              ),
              child: Text(
                value,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.76),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _formatRuntimeChip(String value) {
    final trimmed = value.trim();
    final minuteMatch = RegExp(
      r'^(\d{1,4})\s*(?:min|mins|minute|minutes)\.?$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (minuteMatch == null) return trimmed;
    final totalMinutes = int.tryParse(minuteMatch.group(1) ?? '');
    if (totalMinutes == null || totalMinutes <= 0) return trimmed;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours <= 0) return '${totalMinutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

class _ContinueProgressPill extends StatelessWidget {
  const _ContinueProgressPill({required this.entry});

  final ContinueWatchingEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: JuicrVisual.softPanel(
        colorScheme,
        color: colorScheme.primary.withValues(alpha: 0.12),
        radius: JuicrVisual.cardRadius,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox.square(
                dimension: 18,
                child: Center(
                  child: Icon(
                    Icons.history_rounded,
                    color: colorScheme.primary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Continue watching',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: const StrutStyle(
                    forceStrutHeight: true,
                    height: 1.1,
                  ),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                entry.remainingLabel,
                strutStyle: const StrutStyle(
                  forceStrutHeight: true,
                  height: 1.1,
                ),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: entry.progress,
              backgroundColor: colorScheme.outlineVariant.withValues(
                alpha: 0.45,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaybackBusyIcon extends StatelessWidget {
  const _PlaybackBusyIcon({required this.animation, this.size});

  final Animation<double> animation;
  final double? size;

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: animation,
      child: Icon(Icons.hourglass_top_rounded, size: size),
    );
  }
}

class _DetailsLoadingPill extends StatelessWidget {
  const _DetailsLoadingPill();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final favoriteSize = 48.0;
        const gap = _DetailsPageState._detailsPrimaryActionGap;
        final mainWidth = (constraints.maxWidth - favoriteSize - gap)
            .clamp(160.0, constraints.maxWidth)
            .toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppShimmerBox(width: 70, height: 28, radius: 999),
                AppShimmerBox(width: 58, height: 28, radius: 999),
                AppShimmerBox(width: 84, height: 28, radius: 999),
                AppShimmerBox(width: 72, height: 28, radius: 999),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: mainWidth,
                  child: const AppShimmerBox(
                    height: _DetailsPageState._detailsPrimaryActionHeight,
                    radius: 999,
                  ),
                ),
                SizedBox(width: gap),
                AppShimmerBox(
                  width: favoriteSize,
                  height: favoriteSize,
                  radius: 999,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DetailsLoadingBody extends StatelessWidget {
  const _DetailsLoadingBody();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSkeletonCard(
          width: double.infinity,
          height: 104,
          radius: JuicrVisual.cardRadius,
        ),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppShimmerBox(width: 70, height: 36, radius: 999),
            AppShimmerBox(width: 84, height: 36, radius: 999),
          ],
        ),
        const SizedBox(height: 14),
        const AppSkeletonLine(width: 132, height: 25, radius: 8),
        const SizedBox(height: 12),
        SizedBox(
          height: 214,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = ((constraints.maxWidth - 24) / 3).clamp(
                108.0,
                136.0,
              );
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.only(right: 18),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  return SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: Container(
                              decoration: JuicrVisual.elevatedCardDecoration(
                                colorScheme,
                                radius: 18,
                                color: colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.52),
                                shadowAlpha: 0.08,
                              ),
                              child: const AppSkeletonCard(
                                width: double.infinity,
                                height: double.infinity,
                                radius: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppSkeletonLine(
                          width: index.isEven ? cardWidth * 0.78 : cardWidth,
                          height: 14,
                          radius: 8,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const AppSkeletonLine(width: 64, height: 25, radius: 8),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return const SizedBox(
                width: 78,
                child: Column(
                  children: [
                    AppSkeletonCircle(size: 70),
                    SizedBox(height: 10),
                    AppSkeletonLine(width: 62, height: 13, radius: 8),
                    SizedBox(height: 5),
                    AppSkeletonLine(width: 48, height: 13, radius: 8),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HeroMedia extends StatelessWidget {
  const _HeroMedia({required this.item});

  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final scaffoldBackground = Theme.of(context).scaffoldBackgroundColor;
    final background = item.background ?? item.poster;
    final posterCacheWidth = _detailsImageCacheWidth(context, 156);
    final fallbackIcon = item.type.isLive ? Icons.live_tv_rounded : Icons.movie;
    final liveArtwork = item.type.isLive;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (liveArtwork)
          _LiveHeroBackdrop(
            key: ValueKey<String>('live-artwork-${background ?? 'empty'}'),
            background: background,
          )
        else
          _HeroBackdrop(
            key: ValueKey<String>('artwork-${background ?? 'empty'}'),
            background: background,
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x22000000), Color(0x66000000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        if (!liveArtwork)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 46,
            child: ColoredBox(color: scaffoldBackground),
          ),
        if (!liveArtwork)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 0, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 132,
                  height: 196,
                  child: item.poster == null
                      ? ColoredBox(
                          color: const Color(0xFF171A1F),
                          child: Icon(fallbackIcon, color: Colors.white54),
                        )
                      : ValueListenableBuilder<String>(
                          valueListenable: AppState.posterImageIntensity,
                          builder: (context, intensity, _) {
                            return JuicrVisual.posterTone(
                              intensity,
                              child: Image.network(
                                item.poster!,
                                fit: BoxFit.cover,
                                cacheWidth: posterCacheWidth,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const AppSkeletonCard(radius: 10);
                                    },
                                errorBuilder: (_, __, ___) {
                                  return const ColoredBox(
                                    color: Color(0xFF171A1F),
                                    child: Icon(
                                      Icons.broken_image,
                                      color: Colors.white54,
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LiveHeroBackdrop extends StatelessWidget {
  const _LiveHeroBackdrop({super.key, required this.background});

  final String? background;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (background == null) {
      return ColoredBox(
        color: const Color(0xFF101116),
        child: Center(
          child: Icon(
            Icons.live_tv_rounded,
            color: colorScheme.onSurface.withValues(alpha: 0.42),
            size: 72,
          ),
        ),
      );
    }
    final cacheWidth = _detailsImageCacheWidth(
      context,
      MediaQuery.sizeOf(context).width * 0.82,
    );
    return ColoredBox(
      color: const Color(0xFF101116),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 50, 28, 20),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.82,
            heightFactor: 0.74,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ValueListenableBuilder<String>(
                valueListenable: AppState.posterImageIntensity,
                builder: (context, intensity, _) {
                  return JuicrVisual.posterTone(
                    intensity,
                    child: Image.network(
                      background!,
                      fit: BoxFit.contain,
                      cacheWidth: cacheWidth,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const AppSkeletonCard(radius: 18);
                      },
                      errorBuilder: (_, __, ___) {
                        return ColoredBox(
                          color: const Color(0xFF171A1F),
                          child: Icon(
                            Icons.live_tv_rounded,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.42,
                            ),
                            size: 72,
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({super.key, required this.background});

  final String? background;

  @override
  Widget build(BuildContext context) {
    if (background == null) {
      return const ColoredBox(color: Color(0xFF101116));
    }
    final cacheWidth = _detailsImageCacheWidth(
      context,
      MediaQuery.sizeOf(context).width,
    );
    return ValueListenableBuilder<String>(
      valueListenable: AppState.posterImageIntensity,
      builder: (context, intensity, _) {
        return JuicrVisual.posterTone(
          intensity,
          child: Image.network(
            background!,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const AppSkeletonCard(radius: 0);
            },
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xFF101116)),
          ),
        );
      },
    );
  }
}

class _HeroTrailerPlayer extends StatefulWidget {
  const _HeroTrailerPlayer({
    super.key,
    required this.title,
    required this.url,
    required this.youtubeId,
    required this.onEnded,
  });

  final String title;
  final String url;
  final String? youtubeId;
  final VoidCallback onEnded;

  @override
  State<_HeroTrailerPlayer> createState() => _HeroTrailerPlayerState();
}

class _HeroTrailerPlayerState extends State<_HeroTrailerPlayer> {
  bool _loading = true;
  bool _embedFailed = false;
  DateTime? _loadStartedAt;
  bool _maskLogged = false;
  InAppWebViewController? _webViewController;

  int? get _elapsedMs {
    final started = _loadStartedAt;
    if (started == null) return null;
    return DateTime.now().difference(started).inMilliseconds;
  }

  String get _embedUrl {
    final youtubeId = widget.youtubeId;
    if (youtubeId == null || youtubeId.isEmpty) return widget.url;
    final encodedId = Uri.encodeComponent(youtubeId);
    final params = <String, String>{
      'autoplay': '1',
      'playsinline': '1',
      'controls': '0',
      'fs': '0',
      'rel': '0',
      'modestbranding': '1',
      'iv_load_policy': '3',
      'cc_load_policy': '0',
      'disablekb': '1',
      'enablejsapi': '1',
      'origin': 'https://www.youtube-nocookie.com',
      'showinfo': '0',
      'hl': 'en',
      'cc_lang_pref': 'en',
    };
    return Uri.https(
      'www.youtube-nocookie.com',
      '/embed/$encodedId',
      params,
    ).toString();
  }

  InAppWebViewInitialData? get _initialEmbedData {
    if (widget.youtubeId == null || widget.youtubeId!.isEmpty) return null;
    final embedUrl = _embedUrl;
    return InAppWebViewInitialData(
      baseUrl: WebUri('https://www.youtube-nocookie.com/'),
      historyUrl: WebUri(widget.url),
      data:
          '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
      html, body {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: #000;
      }
      iframe {
        border: 0;
        width: 100%;
        height: 100%;
        display: block;
      }
    </style>
    <script src="https://www.youtube.com/iframe_api"></script>
    <script>
      function notifyFlutter(type, value) {
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('TrailerPlayer', type, value || '');
        }
      }
      function onYouTubeIframeAPIReady() {
        new YT.Player('trailer-player', {
          playerVars: {
            autoplay: 1,
            controls: 0,
            fs: 0,
            rel: 0,
            modestbranding: 1,
            iv_load_policy: 3,
            cc_load_policy: 0,
            disablekb: 1,
            playsinline: 1,
            hl: 'en',
            cc_lang_pref: 'en'
          },
          events: {
            onReady: function(event) {
              notifyFlutter('ready', JSON.stringify(readPlayerData(event.target)));
            },
            onStateChange: function(event) {
              if (event.data === YT.PlayerState.ENDED) {
                notifyFlutter('ended', JSON.stringify(readPlayerData(event.target)));
              } else if (event.data === YT.PlayerState.PLAYING) {
                notifyFlutter('playing', JSON.stringify(readPlayerData(event.target)));
              }
            },
            onError: function(event) { notifyFlutter('error', String(event.data)); }
          }
        });
      }
      function readPlayerData(player) {
        try {
          const data = player && player.getVideoData ? player.getVideoData() : {};
          return {
            videoId: data && data.video_id ? data.video_id : '',
            title: data && data.title ? data.title : '',
            author: data && data.author ? data.author : '',
            requestedLanguage: 'en',
            requestedControls: 'hidden',
            navigatorLanguage: navigator.language || ''
          };
        } catch (_) {
          return {
            requestedLanguage: 'en',
            requestedControls: 'hidden',
            navigatorLanguage: navigator.language || ''
          };
        }
      }
    </script>
  </head>
  <body>
    <iframe
      id="trailer-player"
      src="$embedUrl"
      title="YouTube trailer"
      allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share">
    </iframe>
  </body>
</html>
''',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: InAppWebView(
            initialUrlRequest: _initialEmbedData == null
                ? URLRequest(url: WebUri(_embedUrl))
                : null,
            initialData: _initialEmbedData,
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              transparentBackground: false,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              DiagnosticLog.add(
                'details hero trailer webview created youtubeId=${widget.youtubeId ?? 'none'} requestedControls=hidden requestedLanguage=en',
              );
              controller.addJavaScriptHandler(
                handlerName: 'TrailerPlayer',
                callback: (args) {
                  if (!mounted || args.isEmpty) return null;
                  final event = args.first?.toString() ?? '';
                  final data = args.length > 1 ? args[1]?.toString() ?? '' : '';
                  final elapsed = _elapsedMs;
                  if (event == 'ready') {
                    DiagnosticLog.add(
                      'details hero trailer iframe ready elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                    );
                    setState(() {
                      _loading = false;
                      _embedFailed = false;
                    });
                  } else if (event == 'error') {
                    DiagnosticLog.add(
                      'details hero trailer embed failed error=${args.length > 1 ? args[1] : 'unknown'}',
                    );
                    setState(() {
                      _loading = false;
                      _embedFailed = true;
                    });
                  } else if (event == 'ended') {
                    DiagnosticLog.add(
                      'details hero trailer ended elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                    );
                    widget.onEnded();
                  } else if (event == 'playing') {
                    DiagnosticLog.add(
                      'details hero trailer playing elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                    );
                    if (_loading) {
                      setState(() => _loading = false);
                    }
                  }
                  return null;
                },
              );
            },
            onLoadStart: (_, __) {
              _loadStartedAt = DateTime.now();
              _maskLogged = false;
              DiagnosticLog.add(
                'details hero trailer load start youtubeId=${widget.youtubeId ?? 'none'} controlsRequested=hidden languageRequested=en',
              );
              if (mounted) {
                setState(() {
                  _loading = true;
                  _embedFailed = false;
                });
              }
            },
            onLoadStop: (_, __) {
              final elapsed = _elapsedMs;
              DiagnosticLog.add(
                'details hero trailer load stop elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'}',
              );
              if (mounted) setState(() => _loading = false);
            },
          ),
        ),
        if (!_embedFailed)
          _TrailerChromeMask(
            onVisible: () {
              if (_maskLogged) return;
              _maskLogged = true;
              final elapsed = _elapsedMs;
              DiagnosticLog.add(
                'details hero trailer chrome mask visible elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} top=58 bottom=72 controlsObserved=unavailable',
              );
            },
          ),
        if (_loading)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            ),
          ),
        if (_embedFailed) _TrailerFallback(title: widget.title),
      ],
    );
  }
}

class _TrailerChromeMask extends StatelessWidget {
  const _TrailerChromeMask({this.onVisible});

  final VoidCallback? onVisible;

  @override
  Widget build(BuildContext context) {
    final callback = onVisible;
    if (callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback());
    }
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: const [
          Align(
            alignment: Alignment.topCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0x00000000)],
                ),
              ),
              child: SizedBox(height: 64),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Color(0x00000000)],
                ),
              ),
              child: SizedBox(height: 86),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrailerDialog extends StatefulWidget {
  const _TrailerDialog({
    required this.title,
    required this.trailers,
    required this.onTrailerReady,
  });

  final String title;
  final List<TrailerItem> trailers;
  final VoidCallback onTrailerReady;

  @override
  State<_TrailerDialog> createState() => _TrailerDialogState();
}

class _TrailerDialogState extends State<_TrailerDialog> {
  bool _loading = true;
  bool _embedFailed = false;
  bool _fullscreenLocked = false;
  DateTime? _loadStartedAt;
  int _trailerIndex = 0;
  InAppWebViewController? _webViewController;

  @override
  void dispose() {
    unawaited(_restoreTrailerOrientation());
    super.dispose();
  }

  int? get _elapsedMs {
    final started = _loadStartedAt;
    if (started == null) return null;
    return DateTime.now().difference(started).inMilliseconds;
  }

  TrailerItem get _currentTrailer => widget.trailers[_trailerIndex];

  String get _currentUrl {
    final youtubeId = _currentYoutubeId;
    return youtubeId == null
        ? _currentTrailer.url
        : 'https://www.youtube.com/watch?v=$youtubeId';
  }

  String? get _currentYoutubeId => _youtubeVideoId(_currentTrailer.url);

  bool get _hasNextTrailer => _trailerIndex + 1 < widget.trailers.length;

  void _tryNextTrailer(String reason) {
    if (!_hasNextTrailer) {
      DiagnosticLog.add(
        'details trailer dialog no more trailers failedIndex=$_trailerIndex reason=$reason',
      );
      setState(() {
        _loading = false;
        _embedFailed = true;
      });
      return;
    }
    final nextIndex = _trailerIndex + 1;
    final nextTrailer = widget.trailers[nextIndex];
    DiagnosticLog.add(
      'details trailer dialog auto next from=$_trailerIndex to=$nextIndex reason=$reason nextYoutubeId=${_youtubeVideoId(nextTrailer.url) ?? 'none'}',
    );
    setState(() {
      _trailerIndex = nextIndex;
      _loading = true;
      _embedFailed = false;
      _loadStartedAt = null;
      _webViewController = null;
    });
  }

  Future<void> _enterTrailerFullscreen() async {
    if (_fullscreenLocked) return;
    _fullscreenLocked = true;
    DiagnosticLog.add(
      'details trailer dialog fullscreen enter orientation=landscape',
    );
    beginJuicrImmersiveSession();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreTrailerOrientation() async {
    if (!_fullscreenLocked) return;
    _fullscreenLocked = false;
    DiagnosticLog.add(
      'details trailer dialog fullscreen exit orientation=fluid',
    );
    endJuicrImmersiveSession();
    await restoreJuicrSystemUi(force: true);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _closeTrailerDialog(String reason) async {
    DiagnosticLog.add(
      'details trailer dialog close reason=$reason fullscreen=$_fullscreenLocked',
    );
    await _restoreTrailerOrientation();
    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  bool _isAllowedTrailerNavigation(Uri? uri) {
    if (uri == null) return true;
    if (uri.scheme == 'about' || uri.scheme == 'data') return true;
    final current = Uri.tryParse(_currentUrl);
    final embed = Uri.tryParse(_embedUrl);
    if (current != null && _sameOriginAndPath(uri, current)) return true;
    if (embed != null && _sameOriginAndPath(uri, embed)) return true;
    final host = uri.host.toLowerCase();
    if (host == 'www.youtube-nocookie.com' && uri.path.startsWith('/embed/')) {
      return true;
    }
    return false;
  }

  bool _sameOriginAndPath(Uri left, Uri right) {
    return left.scheme == right.scheme &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.path == right.path;
  }

  String get _embedUrl {
    final youtubeId = _currentYoutubeId;
    if (youtubeId == null || youtubeId.isEmpty) return _currentUrl;
    final encodedId = Uri.encodeComponent(youtubeId);
    final params = <String, String>{
      'autoplay': '1',
      'controls': '1',
      'playsinline': '1',
      'fs': '1',
      'rel': '0',
      'modestbranding': '1',
      'iv_load_policy': '3',
      'enablejsapi': '1',
      'origin': 'https://www.youtube-nocookie.com',
      'hl': 'en',
      'cc_lang_pref': 'en',
    };
    return Uri.https(
      'www.youtube-nocookie.com',
      '/embed/$encodedId',
      params,
    ).toString();
  }

  InAppWebViewInitialData? get _initialEmbedData {
    if (_currentYoutubeId == null || _currentYoutubeId!.isEmpty) return null;
    final embedUrl = _embedUrl;
    return InAppWebViewInitialData(
      baseUrl: WebUri('https://www.youtube-nocookie.com/'),
      historyUrl: WebUri(_currentUrl),
      data:
          '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>
      html, body {
        margin: 0;
        width: 100%;
        height: 100%;
        overflow: hidden;
        background: #000;
      }
      iframe {
        border: 0;
        width: 100%;
        height: 100%;
        display: block;
      }
    </style>
    <script src="https://www.youtube.com/iframe_api"></script>
    <script>
      let trailerEndNotified = false;
      let trailerEndTimer = null;

      function notifyFlutter(type, value) {
        if (window.flutter_inappwebview) {
          window.flutter_inappwebview.callHandler('TrailerPlayer', type, value || '');
        }
      }

      function notifyEnded(player, reason) {
        if (trailerEndNotified) return;
        trailerEndNotified = true;
        const payload = readPlayerData(player);
        payload.reason = reason || 'ended';
        notifyFlutter('ended', JSON.stringify(payload));
      }

      function notifyAlmostEnded(player, reason) {
        if (trailerEndNotified) return;
        trailerEndNotified = true;
        const payload = readPlayerData(player);
        payload.reason = reason || 'almost_ended';
        try {
          if (document.fullscreenElement && document.exitFullscreen) {
            document.exitFullscreen();
          }
        } catch (_) {}
        notifyFlutter('almostEnded', JSON.stringify(payload));
      }

      function watchTrailerEnd(player) {
        if (trailerEndTimer) clearInterval(trailerEndTimer);
        trailerEndTimer = setInterval(function() {
          try {
            const duration = player && player.getDuration ? player.getDuration() : 0;
            const current = player && player.getCurrentTime ? player.getCurrentTime() : 0;
            const state = player && player.getPlayerState ? player.getPlayerState() : null;
            if (duration > 0 && current > 0 && duration - current <= 1.2) {
              notifyAlmostEnded(player, 'near_end_poll');
              clearInterval(trailerEndTimer);
            } else if (state === YT.PlayerState.ENDED) {
              notifyEnded(player, 'state_poll');
              clearInterval(trailerEndTimer);
            }
          } catch (_) {}
        }, 500);
      }

      function onYouTubeIframeAPIReady() {
        window.trailerPlayer = new YT.Player('trailer-player', {
          playerVars: {
            autoplay: 1,
            controls: 1,
            fs: 1,
            rel: 0,
            modestbranding: 1,
            iv_load_policy: 3,
            playsinline: 1,
            hl: 'en',
            cc_lang_pref: 'en'
          },
          events: {
            onReady: function(event) {
              notifyFlutter('ready', JSON.stringify(readPlayerData(event.target)));
              watchTrailerEnd(event.target);
            },
            onStateChange: function(event) {
              if (event.data === YT.PlayerState.ENDED) {
                notifyEnded(event.target, 'state_ended');
              } else if (event.data === YT.PlayerState.PLAYING) {
                watchTrailerEnd(event.target);
                notifyFlutter('playing', JSON.stringify(readPlayerData(event.target)));
              }
            },
            onError: function(event) { notifyFlutter('error', String(event.data)); }
          }
        });
      }
      function readPlayerData(player) {
        try {
          const data = player && player.getVideoData ? player.getVideoData() : {};
          return {
            videoId: data && data.video_id ? data.video_id : '',
            title: data && data.title ? data.title : '',
            author: data && data.author ? data.author : '',
            requestedLanguage: 'en',
            navigatorLanguage: navigator.language || ''
          };
        } catch (_) {
          return {
            requestedLanguage: 'en',
            navigatorLanguage: navigator.language || ''
          };
        }
      }
    </script>
  </head>
  <body>
    <iframe
      id="trailer-player"
      src="$embedUrl"
      title="YouTube trailer"
      allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture; web-share"
      sandbox="allow-scripts allow-same-origin allow-presentation"
      allowfullscreen>
    </iframe>
  </body>
</html>
''',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.sizeOf(context);
    final dialogWidth = (media.width - 32).clamp(300.0, 760.0).toDouble();
    final videoHeight = (dialogWidth * 9 / 16)
        .clamp(170.0, (media.height - 148).clamp(170.0, 520.0))
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: Colors.transparent,
      shadowColor: Colors.black,
      elevation: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: dialogWidth,
        decoration: BoxDecoration(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 26,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.72),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: JuicrAutoScrollText(
                      text: widget.title,
                      height: 22,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close trailer',
                    onPressed: () => unawaited(_closeTrailerDialog('button')),
                    icon: const Icon(Icons.close_rounded),
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  key: ValueKey<String>(
                    'trailer-dialog-$_trailerIndex-$_currentUrl',
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                  child: SizedBox(
                    height: videoHeight,
                    width: double.infinity,
                    child: InAppWebView(
                      initialUrlRequest: _initialEmbedData == null
                          ? URLRequest(url: WebUri(_embedUrl))
                          : null,
                      initialData: _initialEmbedData,
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        domStorageEnabled: true,
                        databaseEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                        allowsInlineMediaPlayback: true,
                        transparentBackground: false,
                        supportZoom: false,
                        useShouldOverrideUrlLoading: true,
                        javaScriptCanOpenWindowsAutomatically: false,
                        supportMultipleWindows: false,
                      ),
                      shouldOverrideUrlLoading: (_, navigationAction) async {
                        final uri = Uri.tryParse(
                          navigationAction.request.url?.toString() ?? '',
                        );
                        if (_isAllowedTrailerNavigation(uri)) {
                          return NavigationActionPolicy.ALLOW;
                        }
                        DiagnosticLog.add(
                          'details trailer navigation blocked host=${uri?.host ?? 'unknown'} path=${uri?.path ?? ''}',
                        );
                        return NavigationActionPolicy.CANCEL;
                      },
                      onCreateWindow: (_, __) async {
                        DiagnosticLog.add(
                          'details trailer popup blocked index=$_trailerIndex',
                        );
                        return false;
                      },
                      onWebViewCreated: (controller) {
                        _webViewController = controller;
                        DiagnosticLog.add(
                          'details trailer dialog webview created index=$_trailerIndex/${widget.trailers.length} youtubeId=${_currentYoutubeId ?? 'none'} provider=${_currentTrailer.providerId}',
                        );
                        controller.addJavaScriptHandler(
                          handlerName: 'TrailerPlayer',
                          callback: (args) {
                            if (!mounted || args.isEmpty) return null;
                            final event = args.first?.toString() ?? '';
                            final data = args.length > 1
                                ? args[1]?.toString() ?? ''
                                : '';
                            final elapsed = _elapsedMs;
                            if (event == 'ready') {
                              DiagnosticLog.add(
                                'details trailer dialog ready elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                              );
                              DiagnosticLog.viewTiming(
                                surface: 'trailer_dialog',
                                state: 'trailer_ready',
                                elapsed: elapsed == null
                                    ? null
                                    : Duration(milliseconds: elapsed),
                                mediaKind: 'trailer',
                                itemCount: widget.trailers.length,
                              );
                              widget.onTrailerReady();
                              setState(() {
                                _loading = false;
                                _embedFailed = false;
                              });
                            } else if (event == 'error') {
                              DiagnosticLog.add(
                                'details trailer embed failed index=$_trailerIndex error=${args.length > 1 ? args[1] : 'unknown'}',
                              );
                              _tryNextTrailer('embed_error');
                            } else if (event == 'almostEnded') {
                              DiagnosticLog.add(
                                'details trailer dialog almost ended elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                              );
                              unawaited(_closeTrailerDialog('near_end'));
                            } else if (event == 'ended') {
                              DiagnosticLog.add(
                                'details trailer dialog ended elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                              );
                              unawaited(_closeTrailerDialog('ended'));
                            } else if (event == 'playing') {
                              DiagnosticLog.add(
                                'details trailer dialog playing elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'} data=$data',
                              );
                              widget.onTrailerReady();
                              if (_loading) setState(() => _loading = false);
                            }
                            return null;
                          },
                        );
                      },
                      onLoadStart: (_, __) {
                        _loadStartedAt = DateTime.now();
                        DiagnosticLog.add(
                          'details trailer dialog load start index=$_trailerIndex youtubeId=${_currentYoutubeId ?? 'none'}',
                        );
                        if (mounted) {
                          setState(() {
                            _loading = true;
                            _embedFailed = false;
                          });
                        }
                      },
                      onLoadStop: (_, __) {
                        final elapsed = _elapsedMs;
                        DiagnosticLog.add(
                          'details trailer dialog load stop elapsed=${elapsed == null ? 'unknown' : '${elapsed}ms'}',
                        );
                        if (mounted) setState(() => _loading = false);
                      },
                      onEnterFullscreen: (_) {
                        unawaited(_enterTrailerFullscreen());
                      },
                      onExitFullscreen: (_) {
                        unawaited(_restoreTrailerOrientation());
                      },
                    ),
                  ),
                ),
                if (_loading)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                if (_embedFailed)
                  Positioned.fill(child: _TrailerFallback(title: widget.title)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TrailerFallback extends StatelessWidget {
  const _TrailerFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.ondemand_video_rounded,
                size: 38,
                color: Colors.white.withValues(alpha: 0.82),
              ),
              const SizedBox(height: 12),
              Text(
                'This trailer cannot be embedded.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              JuicrAutoScrollText(
                text: title,
                height: 17,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _youtubeVideoId(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '');
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  if (!host.endsWith('youtube.com')) return null;
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'embed') {
    return uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
  }
  return uri.queryParameters['v'];
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.values, this.onSelected});

  final List<String> values;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final cleaned = values.where((value) => value.isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: cleaned
          .map(
            (value) => Semantics(
              button: onSelected != null,
              label: value,
              hint: onSelected == null ? null : 'Open ${value} in Discovery',
              child: ExcludeSemantics(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onSelected == null ? null : () => onSelected!(value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          colorScheme.primary.withValues(alpha: 0.12),
                          JuicrVisual.flatCardColor(colorScheme),
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        value,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DescriptionBlock extends StatelessWidget {
  const _DescriptionBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: JuicrVisual.elevatedCardDecoration(colorScheme, radius: 18),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.76),
          height: 1.5,
        ),
      ),
    );
  }
}

bool _hasPeople(List<String> cast, List<String> director) {
  return cast.any((person) => person.trim().isNotEmpty) ||
      director.any((person) => person.trim().isNotEmpty);
}

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({required this.item, required this.future});

  final CatalogItem item;
  final Future<List<CatalogItem>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CatalogItem>>(
      future: future,
      builder: (context, snapshot) {
        final loading =
            snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.active;
        final recommendations = snapshot.data ?? const <CatalogItem>[];
        if (!loading && recommendations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'More like this',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 232,
                child: loading
                    ? const _RecommendationSkeletonRail()
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = ((constraints.maxWidth - 24) / 3)
                              .clamp(108.0, 136.0);
                          return ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(right: 18),
                            itemCount: recommendations.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, index) {
                              return _RecommendationCard(
                                item: recommendations[index],
                                width: cardWidth,
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendationSkeletonRail extends StatelessWidget {
  const _RecommendationSkeletonRail();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (context, index) {
        return SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AspectRatio(
                aspectRatio: 2 / 3,
                child: AppSkeletonCard(radius: 14),
              ),
              const SizedBox(height: 8),
              AppSkeletonLine(
                width: index.isEven ? 86 : 104,
                height: 14,
                radius: 99,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.item, required this.width});

  final CatalogItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final poster = item.poster;
    final cacheWidth = _detailsImageCacheWidth(context, width);
    final posterMissing = poster == null || poster.trim().isEmpty;
    return Semantics(
      button: true,
      label: 'Open ${item.name}',
      hint: 'Show details',
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Navigator.of(context).push<void>(
                AppPageRoute<void>(builder: (_) => DetailsPage(item: item)),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 2 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (!posterMissing)
                          Image.network(
                            poster!,
                            fit: BoxFit.cover,
                            cacheWidth: cacheWidth,
                            errorBuilder: (_, __, ___) =>
                                const AppShimmerBox(radius: 14),
                          )
                        else
                          const AppShimmerBox(radius: 14),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                JuicrAutoScrollText(
                  text: item.name,
                  height: 16,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeopleSection extends StatelessWidget {
  const _PeopleSection({
    required this.cast,
    required this.director,
    required this.castPeople,
    required this.directorPeople,
  });

  final List<String> cast;
  final List<String> director;
  final List<PersonCredit> castPeople;
  final List<PersonCredit> directorPeople;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (castPeople.isNotEmpty ||
          cast.any((person) => person.trim().isNotEmpty))
        _PeopleCarousel(
          title: 'Cast',
          people: _peopleCredits(castPeople, cast),
        ),
      if (directorPeople.isNotEmpty ||
          director.any((person) => person.trim().isNotEmpty))
        _PeopleCarousel(
          title: 'Director',
          people: _peopleCredits(directorPeople, director),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < sections.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 12),
          sections[index],
        ],
      ],
    );
  }
}

class _PeopleCarousel extends StatelessWidget {
  const _PeopleCarousel({required this.title, required this.people});

  final String title;
  final List<PersonCredit> people;

  @override
  Widget build(BuildContext context) {
    final cleaned = people
        .where((person) => person.name.trim().isNotEmpty)
        .take(12)
        .toList();
    if (cleaned.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cleaned.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              return _PersonCard(person: cleaned[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person});

  final PersonCredit person;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = person.name;
    final image = person.image?.trim();
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipOval(
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.alphaBlend(
                  colorScheme.primary.withValues(alpha: 0.16),
                  JuicrVisual.flatCardColor(colorScheme),
                ),
              ),
              child: image == null || image.isEmpty
                  ? Center(
                      child: Text(
                        _initialsFor(name),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary,
                            ),
                      ),
                    )
                  : Image.network(
                      image,
                      fit: BoxFit.cover,
                      width: 70,
                      height: 70,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          _initialsFor(name),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: colorScheme.primary,
                              ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

List<PersonCredit> _peopleCredits(
  List<PersonCredit> people,
  List<String> fallbackNames,
) {
  if (people.isNotEmpty) return people;
  return [
    for (final name in fallbackNames)
      if (name.trim().isNotEmpty) PersonCredit(name: name.trim()),
  ];
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

class _EpisodeList extends StatefulWidget {
  const _EpisodeList({
    required this.item,
    required this.episodes,
    required this.onPlay,
    required this.playbackLocked,
    required this.busy,
    required this.busyAnimation,
    this.busyEpisodeKey,
  });

  final CatalogItem item;
  final List<EpisodeItem> episodes;
  final ValueChanged<EpisodeItem> onPlay;
  final bool playbackLocked;
  final bool busy;
  final String? busyEpisodeKey;
  final Animation<double> busyAnimation;

  @override
  State<_EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<_EpisodeList> {
  late int _selectedSeason;
  String? _expandedEpisodeKey;

  @override
  void initState() {
    super.initState();
    final seasons = _seasonNumbers;
    _selectedSeason = seasons.isEmpty ? 1 : seasons.first;
  }

  @override
  void didUpdateWidget(covariant _EpisodeList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seasons = _seasonNumbers;
    if (seasons.isEmpty) {
      _selectedSeason = 1;
      return;
    }
    if (!seasons.contains(_selectedSeason)) {
      _selectedSeason = seasons.first;
      _expandedEpisodeKey = null;
    }
  }

  List<int> get _seasonNumbers {
    final values =
        _normalizedEpisodes.map((episode) => episode.season).toSet().toList()
          ..sort();
    return values;
  }

  List<EpisodeItem> get _normalizedEpisodes {
    final bySlot = <String, EpisodeItem>{};
    for (final episode in widget.episodes) {
      final key = '${episode.season}:${episode.episode}';
      final existing = bySlot[key];
      if (existing == null ||
          _episodeMetadataScore(episode) > _episodeMetadataScore(existing)) {
        bySlot[key] = episode;
      }
    }
    final normalized = bySlot.values.toList()
      ..sort((left, right) {
        final seasonCompare = left.season.compareTo(right.season);
        if (seasonCompare != 0) return seasonCompare;
        return left.episode.compareTo(right.episode);
      });
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.episodes.isEmpty) {
      return Text(
        'Episodes are not available for this title yet.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.68),
        ),
      );
    }

    final episodes = _normalizedEpisodes;
    final seasons = _seasonNumbers;
    final filteredEpisodes = episodes
        .where((episode) => episode.season == _selectedSeason)
        .take(80)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final season in seasons)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _SeasonChip(
                    label: 'Season $season',
                    selected: season == _selectedSeason,
                    onTap: widget.busy
                        ? null
                        : () {
                            DiagnosticLog.add(
                              'details season selected season=$season',
                            );
                            setState(() {
                              _selectedSeason = season;
                            });
                          },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<Map<String, ContinueWatchingEntry>>(
          valueListenable: AppState.continueWatching,
          builder: (context, progress, _) {
            return ValueListenableBuilder<Map<String, CompletedWatchingEntry>>(
              valueListenable: AppState.completedWatching,
              builder: (context, completed, _) {
                return Column(
                  children: [
                    for (final episode in filteredEpisodes)
                      Builder(
                        builder: (context) {
                          final episodeKey = _episodeProgressKey(episode);
                          final episodeBusy =
                              widget.busyEpisodeKey == episodeKey;
                          final episodeProgress = _entryForEpisodeKey(
                            progress,
                            episodeKey,
                          );
                          final episodeCompleted = _entryForEpisodeKey(
                            completed,
                            episodeKey,
                          );
                          return _EpisodeCard(
                            episode: episode,
                            busy: episodeBusy,
                            busyAnimation: widget.busyAnimation,
                            playbackLocked: widget.playbackLocked,
                            expanded: _expandedEpisodeKey == episodeKey,
                            onToggleExpanded: () {
                              setState(() {
                                _expandedEpisodeKey =
                                    _expandedEpisodeKey == episodeKey
                                    ? null
                                    : episodeKey;
                              });
                            },
                            progress: episodeProgress,
                            completed: episodeCompleted,
                            onPlay: widget.busy || widget.playbackLocked
                                ? null
                                : () {
                                    DiagnosticLog.add(
                                      'details episode play pressed season=${episode.season} episode=${episode.episode} titleLength=${episode.title.length}',
                                    );
                                    widget.onPlay(episode);
                                  },
                          );
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  String _episodeProgressKey(EpisodeItem episode) {
    return '${widget.item.id}:${episode.season}:${episode.episode}';
  }

  T? _entryForEpisodeKey<T>(Map<String, T> entries, String episodeKey) {
    final direct = entries[episodeKey];
    if (direct != null) return direct;
    for (final entry in entries.entries) {
      final contentKey = AppState.contentPlaybackKeyFor(widget.item, entry.key);
      if (contentKey == episodeKey) return entry.value;
    }
    return null;
  }
}

class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    required this.episode,
    required this.onPlay,
    required this.playbackLocked,
    required this.busy,
    required this.busyAnimation,
    required this.expanded,
    required this.onToggleExpanded,
    this.progress,
    this.completed,
  });

  final EpisodeItem episode;
  final ContinueWatchingEntry? progress;
  final CompletedWatchingEntry? completed;
  final VoidCallback? onPlay;
  final bool playbackLocked;
  final bool busy;
  final Animation<double> busyAnimation;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  bool _canExpandDescription = false;

  void _setCanExpandDescription(bool value) {
    if (_canExpandDescription == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _canExpandDescription == value) return;
      setState(() => _canExpandDescription = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final description =
        (widget.episode.description != null &&
            widget.episode.description!.trim().isNotEmpty)
        ? widget.episode.description!.trim()
        : 'Episode ${widget.episode.episode}';
    final entry = widget.progress;
    final thumbnailCacheWidth = _detailsImageCacheWidth(context, 90);
    final descriptionStyle = _episodeDescriptionStyle(context, colorScheme);
    final expanded = widget.expanded && _canExpandDescription;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(JuicrVisual.cardRadius),
                  onTap: _canExpandDescription ? widget.onToggleExpanded : null,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 74,
                          height: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: widget.episode.thumbnail == null
                                ? const ColoredBox(
                                    color: Color(0xFF20242E),
                                    child: Icon(
                                      Icons.smart_display,
                                      color: Colors.white54,
                                    ),
                                  )
                                : Image.network(
                                    widget.episode.thumbnail!,
                                    fit: BoxFit.cover,
                                    cacheWidth: thumbnailCacheWidth,
                                    errorBuilder: (_, __, ___) {
                                      return const ColoredBox(
                                        color: Color(0xFF20242E),
                                        child: Icon(
                                          Icons.smart_display,
                                          color: Colors.white54,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              JuicrAutoScrollText(
                                text:
                                    'E${widget.episode.episode} - ${widget.episode.title}',
                                height: 20,
                              ),
                              const SizedBox(height: 2),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final canExpand =
                                      constraints.maxWidth.isFinite &&
                                      _episodeDescriptionOverflows(
                                        context: context,
                                        description: description,
                                        style: descriptionStyle,
                                        maxWidth: constraints.maxWidth,
                                      );
                                  _setCanExpandDescription(canExpand);
                                  return AnimatedCrossFade(
                                    duration: const Duration(milliseconds: 180),
                                    sizeCurve: Curves.easeOutCubic,
                                    crossFadeState: expanded
                                        ? CrossFadeState.showSecond
                                        : CrossFadeState.showFirst,
                                    firstChild: _EpisodeDescription(
                                      description: description,
                                      expanded: false,
                                      style: descriptionStyle,
                                    ),
                                    secondChild: _EpisodeDescription(
                                      description: description,
                                      expanded: true,
                                      style: descriptionStyle,
                                    ),
                                  );
                                },
                              ),
                              if (widget.completed != null) ...[
                                const SizedBox(height: 9),
                                _EpisodeCompletedPill(
                                  label: _episodeCompletedLabel(
                                    widget.episode,
                                    widget.completed!,
                                  ),
                                ),
                              ] else if (entry != null) ...[
                                const SizedBox(height: 9),
                                _EpisodeProgressStatus(entry: entry),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _EpisodePlayButton(
                busy: widget.busy,
                busyAnimation: widget.busyAnimation,
                locked: widget.playbackLocked,
                onPressed: widget.onPlay,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EpisodeDescription extends StatelessWidget {
  const _EpisodeDescription({
    required this.description,
    required this.expanded,
    required this.style,
  });

  final String description;
  final bool expanded;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      description,
      maxLines: expanded ? null : 2,
      overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
      style: style,
    );
  }
}

TextStyle? _episodeDescriptionStyle(
  BuildContext context,
  ColorScheme colorScheme,
) {
  return Theme.of(context).textTheme.bodySmall?.copyWith(
    color: colorScheme.onSurface.withValues(alpha: 0.74),
    height: 1.22,
  );
}

bool _episodeDescriptionOverflows({
  required BuildContext context,
  required String description,
  required TextStyle? style,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: description, style: style),
    maxLines: 2,
    textDirection: Directionality.of(context),
  )..layout(maxWidth: maxWidth);
  return painter.didExceedMaxLines;
}

class _EpisodeCompletedPill extends StatelessWidget {
  const _EpisodeCompletedPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Color.alphaBlend(
            colorScheme.primary.withValues(alpha: 0.16),
            JuicrVisual.flatCardColor(colorScheme),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_rounded, size: 14, color: colorScheme.primary),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _episodeCompletedLabel(
  EpisodeItem episode,
  CompletedWatchingEntry completed,
) {
  final base = 'S${episode.season} E${episode.episode} watched';
  if (completed.completionCount <= 1) return base;
  return '$base ${completed.completionCount}x';
}

class _EpisodeProgressStatus extends StatelessWidget {
  const _EpisodeProgressStatus({required this.entry});

  final ContinueWatchingEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progressValue = entry.progress.clamp(0, 1).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Continue watching',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              progressValue >= 0.92 ? 'Almost done' : entry.remainingLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 4,
            value: progressValue,
            backgroundColor: colorScheme.outlineVariant.withValues(alpha: 0.36),
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
      ],
    );
  }
}

class _EpisodePlayButton extends StatelessWidget {
  const _EpisodePlayButton({
    required this.busy,
    required this.busyAnimation,
    required this.locked,
    required this.onPressed,
  });

  final bool busy;
  final Animation<double> busyAnimation;
  final bool locked;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final fill = enabled
        ? colorScheme.primary
        : Color.alphaBlend(
            colorScheme.onSurface.withValues(alpha: 0.06),
            JuicrVisual.flatCardColor(colorScheme),
          );
    final iconColor = enabled
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      child: IconButton(
        tooltip: locked
            ? 'Coming soon'
            : busy
            ? 'Please wait'
            : 'Play episode',
        onPressed: onPressed,
        color: iconColor,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: iconColor,
          disabledForegroundColor: iconColor,
        ),
        icon: busy
            ? _PlaybackBusyIcon(animation: busyAnimation)
            : Icon(locked ? Icons.lock_outline_rounded : Icons.play_arrow),
      ),
    );
  }
}

int _detailsImageCacheWidth(BuildContext context, double logicalWidth) {
  final width = logicalWidth * MediaQuery.devicePixelRatioOf(context);
  return width.clamp(120, 1200).round();
}

class _SeasonChip extends StatelessWidget {
  const _SeasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Ink(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? Color.alphaBlend(
                        colorScheme.primary.withValues(alpha: 0.16),
                        JuicrVisual.flatCardColor(colorScheme),
                      )
                    : Color.alphaBlend(
                        colorScheme.onSurface.withValues(alpha: 0.06),
                        JuicrVisual.flatCardColor(colorScheme),
                      ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final serviceDisabled = message.toLowerCase().contains(
      'service is currently unavailable',
    );
    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = serviceDisabled
        ? colorScheme.primary
        : const Color(0xFFFF8A80);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: JuicrVisual.elevatedCardDecoration(
        colorScheme,
        color: serviceDisabled
            ? colorScheme.surfaceContainer
            : const Color(0xFF3A1E22),
        radius: JuicrVisual.softRadius,
        borderAlpha: serviceDisabled ? 0.32 : 0.58,
        shadowAlpha: 0.14,
      ),
      child: Row(
        children: [
          Icon(
            serviceDisabled
                ? Icons.power_settings_new_rounded
                : Icons.error_outline,
            color: accentColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              serviceDisabled
                  ? 'Service unavailable. Please try again later.'
                  : message,
            ),
          ),
        ],
      ),
    );
  }
}

String _nativeProviderDiagnosticLabel(String providerId) {
  final normalized = providerId.trim().toLowerCase();
  if (normalized.startsWith('addon-')) return 'stream add-on';
  return switch (normalized) {
    'vidlink' => 'Alpha',
    'vidsrc' => 'Beta',
    'icefy' => 'Delta',
    'vidnest' => 'Epsilon',
    'primesrc' || 'xpass' => 'Zeta',
    'cineby' || 'moviesapi' => 'Eta',
    'vidking' => 'Nu',
    'popr' => 'Theta',
    'cinesu' => 'Rho',
    'vidapi' => 'Sigma',
    'videasy' => 'Tau',
    'vidfun' => 'Upsilon',
    'flixhq' => 'Phi',
    'rgshows' => 'Iota',
    'vixsrc' => 'Kappa',
    'vidrock' => 'Lambda',
    'vidzee' => 'Mu',
    'flixer' => 'Xi',
    '7xstream' => 'Omicron',
    'meowtv' => 'Pi',
    'public-iptv' => 'Live TV',
    '' => 'provider',
    _ => 'provider',
  };
}
