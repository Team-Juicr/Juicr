import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_state.dart' as juicr;
import 'diagnostic_log.dart';

class JuicrAdPolicy {
  JuicrAdPolicy._();

  static const _androidBannerAdUnitId =
      'ca-app-pub-3319548483346434/7346782798';
  static const _androidInterstitialAdUnitId =
      'ca-app-pub-3319548483346434/4720619451';
  static const _androidRewardedAdUnitId =
      'ca-app-pub-3319548483346434/4333606648';
  static const _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const _androidTestInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/1033173712';
  static const _androidTestRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const _iosBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';
  static const _iosInterstitialAdUnitId =
      'ca-app-pub-3940256099942544/4411468910';
  static const _iosRewardedAdUnitId = 'ca-app-pub-3940256099942544/1712485313';
  static final math.Random _random = math.Random();
  static Future<void>? _initializeFuture;
  static InterstitialAd? _interstitialAd;
  static RewardedAd? _rewardedAd;
  static Timer? _interstitialRetryTimer;
  static Timer? _rewardedRetryTimer;
  static DateTime? _lastInterstitialShownAt;
  static final Map<String, DateTime> _lastRewardedShownAtByReason =
      <String, DateTime>{};
  static bool _interstitialLoading = false;
  static bool _rewardedLoading = false;
  static bool _fullScreenAdShowing = false;
  static Completer<void>? _fullScreenAdClosedCompleter;
  static const List<DeviceOrientation> _playbackAdPortraitOrientations =
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ];
  static const List<DeviceOrientation> _allDeviceOrientations =
      <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ];

  static String get bannerAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS) return _iosBannerAdUnitId;
    return kReleaseMode ? _androidBannerAdUnitId : _androidTestBannerAdUnitId;
  }

  static String get _interstitialAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosInterstitialAdUnitId;
    }
    return kReleaseMode
        ? _androidInterstitialAdUnitId
        : _androidTestInterstitialAdUnitId;
  }

  static String get _rewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.iOS)
      return _iosRewardedAdUnitId;
    return kReleaseMode
        ? _androidRewardedAdUnitId
        : _androidTestRewardedAdUnitId;
  }

  static Future<void> initialize() async {
    if (kIsWeb) return;
    final existing = _initializeFuture;
    if (existing != null) return existing;
    _initializeFuture = () async {
      await MobileAds.instance.initialize();
      await _muteAds();
      DiagnosticLog.add(
        'ads initialized mode=${kReleaseMode ? 'release' : 'test'} '
        'banner=${juicr.AppState.bannerAdsEnabled.value} '
        'interstitial=${juicr.AppState.interstitialAdsEnabled.value} '
        'rewarded=${juicr.AppState.rewardedVideoAdsEnabled.value}',
      );
      _loadInterstitial();
      _loadRewarded();
    }();
    return _initializeFuture!.catchError((Object error, StackTrace stack) {
      _initializeFuture = null;
      DiagnosticLog.asyncError(error, stack);
    });
  }

  static Future<void> _muteAds() async {
    await MobileAds.instance.setAppMuted(true);
    await MobileAds.instance.setAppVolume(0.0);
    DiagnosticLog.add('ads muted');
  }

  static AdRequest _bannerRequest() {
    return const AdRequest();
  }

  static Future<void> maybeShowInterstitial({
    required String reason,
    double chance = 0.2,
  }) async {
    if (kIsWeb || !juicr.AppState.interstitialAdsEnabled.value) return;
    if (_fullScreenAdShowing) {
      await _waitForFullScreenAdToClose();
      return;
    }
    await initialize();
    final lastShownAt = _lastInterstitialShownAt;
    if (lastShownAt != null &&
        DateTime.now().difference(lastShownAt) < const Duration(minutes: 3)) {
      return;
    }
    if (_random.nextDouble() >= chance.clamp(0, 1)) return;

    final ad = _interstitialAd;
    if (ad == null) {
      DiagnosticLog.add('ads interstitial unavailable reason=$reason');
      _loadInterstitial();
      return;
    }

    _interstitialAd = null;
    _markFullScreenAdShowing();
    final completer = Completer<void>();
    void finish() {
      _markFullScreenAdClosed();
      if (!completer.isCompleted) completer.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _lastInterstitialShownAt = DateTime.now();
        DiagnosticLog.add('ads interstitial dismissed reason=$reason');
        _loadInterstitial();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        DiagnosticLog.add(
          'ads interstitial failed reason=$reason code=${error.code}',
        );
        _loadInterstitial();
        finish();
      },
    );
    await ad.show();
    unawaited(_logIfAdStillOpen(completer.future, reason, 'interstitial'));
    await completer.future;
  }

  static Future<void> showRewardedBeforePlayback(
    BuildContext context, {
    required String reason,
    bool restorePlayerLandscapeWhenDone = false,
  }) async {
    if (kIsWeb || !juicr.AppState.rewardedVideoAdsEnabled.value) return;
    await _lockPlaybackAdOrientation(reason);
    try {
      await _showRewarded(reason: reason, respectPlaybackCooldown: true);
    } finally {
      if (restorePlayerLandscapeWhenDone) {
        await _restoreNativePlayerOrientationsAfterPlaybackAd(reason);
      } else {
        await _restoreAppOrientationsAfterPlaybackAd(reason);
      }
    }
  }

  static Future<bool> showRewardedForAdControls({
    required String reason,
  }) async {
    return _showRewarded(reason: reason, respectPlaybackCooldown: false);
  }

  static Future<bool> _showRewarded({
    required String reason,
    required bool respectPlaybackCooldown,
  }) async {
    if (kIsWeb || !juicr.AppState.rewardedVideoAdsEnabled.value) return false;
    if (_fullScreenAdShowing) {
      DiagnosticLog.add('ads rewarded waiting for active ad reason=$reason');
      await _waitForFullScreenAdToClose();
      return false;
    }
    if (respectPlaybackCooldown) {
      final cooldown = _rewardedCooldownForReason(reason);
      final lastShownAt = _lastRewardedShownAtByReason[reason];
      if (lastShownAt != null &&
          cooldown > Duration.zero &&
          DateTime.now().difference(lastShownAt) < cooldown) {
        return true;
      }
    }
    await initialize();
    final ad = _rewardedAd;
    if (ad == null) {
      DiagnosticLog.add('ads rewarded unavailable reason=$reason');
      _loadRewarded();
      return false;
    }

    _rewardedAd = null;
    _lastRewardedShownAtByReason[reason] = DateTime.now();
    _markFullScreenAdShowing();
    final completer = Completer<void>();
    var rewarded = false;
    void finish() {
      _markFullScreenAdClosed();
      if (!completer.isCompleted) completer.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        DiagnosticLog.add(
          'ads rewarded dismissed reason=$reason rewarded=$rewarded',
        );
        _loadRewarded();
        finish();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        DiagnosticLog.add(
          'ads rewarded failed reason=$reason code=${error.code}',
        );
        _loadRewarded();
        finish();
      },
    );
    await ad.show(
      onUserEarnedReward: (_, reward) {
        rewarded = true;
        DiagnosticLog.add(
          'ads rewarded earned reason=$reason type=${reward.type}',
        );
      },
    );
    unawaited(_logIfAdStillOpen(completer.future, reason, 'rewarded'));
    await completer.future;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return rewarded;
  }

  static Future<void> _lockPlaybackAdOrientation(String reason) async {
    try {
      await SystemChrome.setPreferredOrientations(
        _playbackAdPortraitOrientations,
      );
      DiagnosticLog.add(
        'ads rewarded orientation portrait_locked reason=$reason',
      );
    } catch (error, stack) {
      DiagnosticLog.asyncError(error, stack);
    }
  }

  static Future<void> _restoreNativePlayerOrientationsAfterPlaybackAd(
    String reason,
  ) async {
    try {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      DiagnosticLog.add(
        'ads rewarded orientation native_landscape_restored reason=$reason',
      );
    } catch (error, stack) {
      DiagnosticLog.asyncError(error, stack);
    }
  }

  static Future<void> _restoreAppOrientationsAfterPlaybackAd(
    String reason,
  ) async {
    try {
      await SystemChrome.setPreferredOrientations(_allDeviceOrientations);
      DiagnosticLog.add('ads rewarded orientation restored reason=$reason');
    } catch (error, stack) {
      DiagnosticLog.asyncError(error, stack);
    }
  }

  static void _markFullScreenAdShowing() {
    _fullScreenAdShowing = true;
    _fullScreenAdClosedCompleter = Completer<void>();
  }

  static void _markFullScreenAdClosed() {
    _fullScreenAdShowing = false;
    final completer = _fullScreenAdClosedCompleter;
    _fullScreenAdClosedCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  static Future<void> _waitForFullScreenAdToClose() async {
    final completer = _fullScreenAdClosedCompleter;
    if (completer == null || completer.isCompleted) return;
    await completer.future;
  }

  static Future<void> _logIfAdStillOpen(
    Future<void> closed,
    String reason,
    String kind,
  ) async {
    try {
      await closed.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      DiagnosticLog.add('ads $kind still open reason=$reason');
    }
  }

  static Duration _rewardedCooldownForReason(String reason) {
    if (reason == 'movie_watch_now') return Duration.zero;
    if (reason == 'episode_playback' || reason == 'live_tv_playback') {
      return const Duration(minutes: 12);
    }
    return const Duration(minutes: 12);
  }

  static String _adLoadFailureReason(LoadAdError error) {
    return switch (error.code) {
      0 => 'internal',
      1 => 'invalid_request',
      2 => 'network',
      3 => 'no_fill',
      _ => 'other',
    };
  }

  static void _loadInterstitial() {
    if (kIsWeb || !juicr.AppState.interstitialAdsEnabled.value) return;
    if (_interstitialLoading || _interstitialAd != null) return;
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = null;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitialAd?.dispose();
          _interstitialAd = ad;
          DiagnosticLog.add('ads interstitial loaded');
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          _interstitialAd = null;
          DiagnosticLog.add(
            'ads interstitial load failed code=${error.code}',
          );
          _scheduleInterstitialRetry();
        },
      ),
    );
  }

  static void _loadRewarded() {
    if (kIsWeb || !juicr.AppState.rewardedVideoAdsEnabled.value) return;
    if (_rewardedLoading || _rewardedAd != null) return;
    _rewardedRetryTimer?.cancel();
    _rewardedRetryTimer = null;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewardedAd?.dispose();
          _rewardedAd = ad;
          DiagnosticLog.add('ads rewarded loaded');
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          _rewardedAd = null;
          DiagnosticLog.add('ads rewarded load failed code=${error.code}');
          _scheduleRewardedRetry();
        },
      ),
    );
  }

  static void _scheduleInterstitialRetry() {
    if (kIsWeb || !juicr.AppState.interstitialAdsEnabled.value) return;
    _interstitialRetryTimer?.cancel();
    _interstitialRetryTimer = Timer(const Duration(seconds: 45), () {
      _interstitialRetryTimer = null;
      _loadInterstitial();
    });
  }

  static void _scheduleRewardedRetry() {
    if (kIsWeb || !juicr.AppState.rewardedVideoAdsEnabled.value) return;
    _rewardedRetryTimer?.cancel();
    _rewardedRetryTimer = Timer(const Duration(seconds: 45), () {
      _rewardedRetryTimer = null;
      _loadRewarded();
    });
  }
}

class JuicrBannerAdSlot extends StatefulWidget {
  const JuicrBannerAdSlot({super.key, required this.placement});

  final String placement;

  @override
  State<JuicrBannerAdSlot> createState() => _JuicrBannerAdSlotState();
}

AdSize _bannerSizeForContext(BuildContext context) {
  return AdSize.banner;
}

Size _bannerGeometry(BannerAd ad, BuildContext context) {
  return Size(ad.size.width.toDouble(), ad.size.height.toDouble());
}

bool _bannerGeometryAllowed(
  String placement,
  BannerAd ad,
  AdSize requestedSize,
) {
  final width = ad.size.width;
  final height = ad.size.height;
  if (width <= 0 || height <= 0) return false;
  if (width > requestedSize.width || height > requestedSize.height) {
    return false;
  }
  if (placement == 'details_lower') {
    return width == AdSize.banner.width && height == AdSize.banner.height;
  }
  if (placement == 'shell_bottom' || placement.startsWith('library_empty')) {
    return width == requestedSize.width && height == requestedSize.height;
  }
  return width == requestedSize.width && height == requestedSize.height;
}

class _JuicrBannerAdSlotState extends State<JuicrBannerAdSlot> {
  static const _bannerPlacementsPaused = false;
  static const _bannerRetryDelay = Duration(seconds: 12);
  static const _bannerNoFillRetryDelay = Duration(seconds: 45);
  static const _placementBannerNoFillCooldown = Duration(minutes: 2);
  static final Map<String, DateTime> _bannerNoFillUntilByPlacement =
      <String, DateTime>{};

  BannerAd? _bannerAd;
  BannerAd? _candidateBannerAd;
  Timer? _retryTimer;
  bool _loaded = false;
  bool _dependenciesReady = false;

  @override
  void initState() {
    super.initState();
    juicr.AppState.bannerAdsEnabled.addListener(_syncBanner);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _syncBanner();
  }

  @override
  void dispose() {
    juicr.AppState.bannerAdsEnabled.removeListener(_syncBanner);
    _retryTimer?.cancel();
    _disposeBanner();
    super.dispose();
  }

  void _syncBanner() {
    if (!mounted || kIsWeb || !_dependenciesReady) return;
    if (_bannerPlacementsPaused) {
      _retryTimer?.cancel();
      if (_bannerAd != null || _candidateBannerAd != null || _loaded) {
        setState(_disposeBanner);
      }
      DiagnosticLog.add(
        'ads banner skipped reason=placements_paused '
        'placement=${widget.placement}',
      );
      return;
    }
    if (!juicr.AppState.bannerAdsEnabled.value) {
      _retryTimer?.cancel();
      setState(_disposeBanner);
      return;
    }
    if (_candidateBannerAd != null) return;
    if (_bannerAd != null && _loaded) return;
    unawaited(_loadBanner());
  }

  Future<void> _loadBanner() async {
    final bannerSize = _bannerSizeForContext(context);
    await JuicrAdPolicy.initialize();
    if (!mounted ||
        !juicr.AppState.bannerAdsEnabled.value ||
        _candidateBannerAd != null ||
        (_bannerAd != null && _loaded)) {
      return;
    }
    final noFillUntil = _bannerNoFillUntil();
    if (noFillUntil != null && DateTime.now().isBefore(noFillUntil)) {
      DiagnosticLog.add(
        'ads banner skipped reason=placement_no_fill_cooldown '
        'placement=${widget.placement}',
      );
      _scheduleRetry(delay: _bannerNoFillRetryDelay);
      return;
    }
    final ad = BannerAd(
      adUnitId: JuicrAdPolicy.bannerAdUnitId,
      size: bannerSize,
      request: JuicrAdPolicy._bannerRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          final loadedAd = ad as BannerAd;
          if (!_bannerGeometryAllowed(widget.placement, loadedAd, bannerSize)) {
            DiagnosticLog.add(
              'ads banner rejected reason=oversized_or_invalid '
              'placement=${widget.placement}',
            );
            if (identical(_candidateBannerAd, loadedAd)) {
              setState(() {
                _candidateBannerAd = null;
                _loaded = _bannerAd != null;
              });
              _scheduleRetry();
            } else if (identical(_bannerAd, loadedAd)) {
              setState(() {
                _bannerAd = null;
                _loaded = false;
              });
              _scheduleRetry();
            }
            loadedAd.dispose();
            return;
          }
          final previousAd = _bannerAd;
          setState(() {
            _bannerAd = loadedAd;
            _candidateBannerAd = null;
            _loaded = true;
          });
          if (previousAd != null && !identical(previousAd, loadedAd)) {
            previousAd.dispose();
          }
          DiagnosticLog.add(
            'ads banner loaded placement=${widget.placement}',
          );
        },
        onAdImpression: (ad) {
          DiagnosticLog.add(
            'ads banner impression placement=${widget.placement}',
          );
        },
        onAdFailedToLoad: (ad, error) {
          if (_loaded && identical(_bannerAd, ad)) {
            DiagnosticLog.add(
              'ads banner refresh failed; keeping visible banner '
              'placement=${widget.placement} code=${error.code}',
            );
            return;
          }
          ad.dispose();
          if (mounted) {
            setState(() {
              if (identical(_candidateBannerAd, ad)) {
                _candidateBannerAd = null;
              }
              _loaded = _bannerAd != null;
            });
            if (error.code == 3) {
              _markBannerNoFillCooldown();
            }
            _scheduleRetry(
              delay: error.code == 3
                  ? _bannerNoFillRetryDelay
                  : _bannerRetryDelay,
            );
          }
          DiagnosticLog.add(
            'ads banner load failed code=${error.code} '
            'reason=${JuicrAdPolicy._adLoadFailureReason(error)} '
            'placement=${widget.placement}',
          );
        },
      ),
    );
    setState(() {
      _candidateBannerAd = ad;
      _loaded = _bannerAd != null;
    });
    DiagnosticLog.add(
      'ads banner request placement=${widget.placement} '
      'size=${bannerSize.width}x${bannerSize.height}',
    );
    await ad.load();
  }

  DateTime? _bannerNoFillUntil() {
    return _bannerNoFillUntilByPlacement[widget.placement];
  }

  void _markBannerNoFillCooldown() {
    _bannerNoFillUntilByPlacement[widget.placement] = DateTime.now().add(
      _placementBannerNoFillCooldown,
    );
  }

  void _disposeBanner() {
    _bannerAd?.dispose();
    _candidateBannerAd?.dispose();
    _bannerAd = null;
    _candidateBannerAd = null;
    _loaded = false;
  }

  void _scheduleRetry({Duration delay = _bannerRetryDelay}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted || !juicr.AppState.bannerAdsEnabled.value) return;
      _syncBanner();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ad = _bannerAd;
    if (_bannerPlacementsPaused) {
      return const SizedBox.shrink();
    }
    if (!juicr.AppState.bannerAdsEnabled.value) {
      return const SizedBox.shrink();
    }
    if (ad == null || !_loaded) return const SizedBox.shrink();

    final geometry = _bannerGeometry(ad, context);
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
        child: Center(
          child: ClipRect(
            child: SizedBox(
              width: geometry.width,
              height: geometry.height,
              child: AdWidget(ad: ad),
            ),
          ),
        ),
      ),
    );
  }
}
