import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'mobile_libvlc_models.dart';

class LibVlcHlsRelay {
  LibVlcHlsRelay._({
    required this.localUri,
    required HttpServer server,
    required HttpClient client,
    required Map<String, Uri> uriById,
    required Set<String> playlistIds,
    required Map<String, String> headers,
    required bool limitHeadersToUpstreamOrigin,
    required Duration resumePosition,
    required String token,
    required bool continuousTsMode,
    required int continuousTsTargetHeight,
    required Set<int> continuousTsExcludedHeights,
    required Duration Function()? currentPlaybackPosition,
    required void Function(Duration duration)? onDuration,
    required void Function(int streamedSegments)? onContinuousTsProgress,
    required void Function(int streamedBytes)? onContinuousTsBytes,
    required void Function()? onContinuousTsTransportActivity,
    required void Function()? onContinuousTsStartupLeadReady,
    required void Function(Duration bufferedPosition)?
        onContinuousTsBufferedPosition,
    required void Function(int selectedHeight)? onContinuousTsRenditionSelected,
    required void Function(int failedHeight)? onContinuousTsRenditionFailure,
    required void Function(Duration offset)? onTimelineOffset,
    required void Function(int upstreamErrors, String lastStatusBucket)?
        onContinuousTsUpstreamError,
    required void Function(String message) onEvent,
  })  : _server = server,
        _client = client,
        _uriById = uriById,
        _playlistIds = playlistIds,
        _headers = headers,
        _limitHeadersToUpstreamOrigin = limitHeadersToUpstreamOrigin,
        _resumePosition = resumePosition,
        _token = token,
        _continuousTsMode = continuousTsMode,
        _continuousTsTargetHeight = continuousTsTargetHeight,
        _continuousTsExcludedHeights =
            Set<int>.unmodifiable(continuousTsExcludedHeights),
        _currentPlaybackPosition = currentPlaybackPosition,
        _onDuration = onDuration,
        _onContinuousTsProgress = onContinuousTsProgress,
        _onContinuousTsBytes = onContinuousTsBytes,
        _onContinuousTsTransportActivity = onContinuousTsTransportActivity,
        _onContinuousTsStartupLeadReady = onContinuousTsStartupLeadReady,
        _onContinuousTsBufferedPosition = onContinuousTsBufferedPosition,
        _onContinuousTsRenditionSelected = onContinuousTsRenditionSelected,
        _onContinuousTsRenditionFailure = onContinuousTsRenditionFailure,
        _onTimelineOffset = onTimelineOffset,
        _onContinuousTsUpstreamError = onContinuousTsUpstreamError,
        _onEvent = ((message) => onEvent(_redactRelayEvent(message, token))) {
    _subscription = _server.listen(_handleRequest);
  }

  static Future<LibVlcHlsRelay> start({
    required Uri upstreamUri,
    required Map<String, String> headers,
    bool limitHeadersToUpstreamOrigin = false,
    required Duration resumePosition,
    bool continuousTsMode = false,
    int continuousTsTargetHeight = 720,
    Set<int> continuousTsExcludedHeights = const <int>{},
    Duration Function()? currentPlaybackPosition,
    void Function(Duration duration)? onDuration,
    void Function(int streamedSegments)? onContinuousTsProgress,
    void Function(int streamedBytes)? onContinuousTsBytes,
    void Function()? onContinuousTsTransportActivity,
    void Function()? onContinuousTsStartupLeadReady,
    void Function(Duration bufferedPosition)? onContinuousTsBufferedPosition,
    void Function(int selectedHeight)? onContinuousTsRenditionSelected,
    void Function(int failedHeight)? onContinuousTsRenditionFailure,
    void Function(Duration offset)? onTimelineOffset,
    void Function(int upstreamErrors, String lastStatusBucket)?
        onContinuousTsUpstreamError,
    required void Function(String message) onEvent,
  }) async {
    final token = _randomToken();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient()..autoUncompress = false;
    final uriById = <String, Uri>{'root': upstreamUri};
    final playlistIds = <String>{'root'};
    final localExtension = continuousTsMode ? 'ts' : 'm3u8';
    final localUri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      pathSegments: <String>['juicr-libvlc-hls', token, 'root.$localExtension'],
    );
    return LibVlcHlsRelay._(
      localUri: localUri,
      server: server,
      client: client,
      uriById: uriById,
      playlistIds: playlistIds,
      headers: Map<String, String>.unmodifiable(headers),
      limitHeadersToUpstreamOrigin: limitHeadersToUpstreamOrigin,
      resumePosition: resumePosition,
      token: token,
      continuousTsMode: continuousTsMode,
      continuousTsTargetHeight: continuousTsTargetHeight,
      continuousTsExcludedHeights: continuousTsExcludedHeights,
      currentPlaybackPosition: currentPlaybackPosition,
      onDuration: onDuration,
      onContinuousTsProgress: onContinuousTsProgress,
      onContinuousTsBytes: onContinuousTsBytes,
      onContinuousTsTransportActivity: onContinuousTsTransportActivity,
      onContinuousTsStartupLeadReady: onContinuousTsStartupLeadReady,
      onContinuousTsBufferedPosition: onContinuousTsBufferedPosition,
      onContinuousTsRenditionSelected: onContinuousTsRenditionSelected,
      onContinuousTsRenditionFailure: onContinuousTsRenditionFailure,
      onTimelineOffset: onTimelineOffset,
      onContinuousTsUpstreamError: onContinuousTsUpstreamError,
      onEvent: onEvent,
    );
  }

  static Future<bool?> hasReadableMediaSegment({
    required Uri manifestUri,
    required String manifestBody,
    required Map<String, String> headers,
    Duration resumePosition = Duration.zero,
    Duration timeout = const Duration(seconds: 3),
    int maxPlaylistDepth = 2,
    int continuousTsTargetHeight = 720,
    Set<int> continuousTsExcludedHeights = const <int>{},
    void Function(String message)? onEvent,
  }) async {
    var currentUri = manifestUri;
    var currentBody = manifestBody;
    final deadline = DateTime.now().add(timeout);
    final cachedSegmentUris = <Uri>[];

    for (var depth = 0; depth <= maxPlaylistDepth; depth += 1) {
      final childIsPlaylist = _playlistLooksLikeMaster(currentBody);
      Uri? childUri;
      if (childIsPlaylist) {
        final variants = _masterPlaylistVariants(currentUri, currentBody);
        if (variants.isNotEmpty) {
          try {
            childUri = _selectContinuousTsMasterVariant(
              variants,
              targetHeight: continuousTsTargetHeight,
              excludedHeights: continuousTsExcludedHeights,
            ).variant.uri;
          } on StateError {
            return false;
          }
        } else {
          final reference = _firstHlsMediaReference(currentBody);
          if (reference == null) return null;
          childUri = _resolvePlaylistReference(currentUri, reference);
        }
      } else {
        final references =
            _hlsMediaReferencesForPosition(currentBody, resumePosition);
        if (references.isEmpty) return null;
        for (var offset = 0;
            offset < references.length;
            offset += _continuousTsPreflightConcurrency) {
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) {
            _discardPreflightSegments(cachedSegmentUris);
            return null;
          }
          final batchReferences = references.skip(offset).take(
                _continuousTsPreflightConcurrency,
              );
          final batchCandidates = batchReferences
              .map(
                (reference) => _hlsPreflightMediaCandidates(
                  currentUri,
                  reference,
                ),
              )
              .toList(growable: false);
          final batchResponses = await Future.wait(
            batchCandidates.map(
              (candidates) => _readHlsPreflightChild(
                rootUri: manifestUri,
                childUri: candidates.first,
                fallbackChildUris: candidates.skip(1),
                headers: headers,
                timeout: remaining,
                expectPlaylist: false,
                onEvent: onEvent,
              ),
            ),
          );
          for (var index = 0; index < batchResponses.length; index += 1) {
            final response = batchResponses[index];
            if (response == null) {
              _discardPreflightSegments(cachedSegmentUris);
              return null;
            }
            if (!response.readable || response.mediaBytes == null) {
              _discardPreflightSegments(cachedSegmentUris);
              return false;
            }
            final segmentUri = response.requestUri;
            _cachePreflightSegment(
              segmentUri,
              response.mediaBytes!,
              response.contentTypeBucket,
            );
            cachedSegmentUris.add(segmentUri);
          }
        }
        return true;
      }
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) return null;
      final response = await _readHlsPreflightChild(
        rootUri: manifestUri,
        childUri: childUri,
        headers: headers,
        timeout: remaining,
        expectPlaylist: childIsPlaylist,
        onEvent: onEvent,
      );
      if (response == null) return null;
      if (!response.readable) return false;
      if (!childIsPlaylist) return true;
      if (response.body == null ||
          !response.body!.trimLeft().startsWith('#EXTM3U')) {
        return false;
      }
      currentUri = response.effectiveUri;
      currentBody = response.body!;
    }
    return null;
  }

  static List<String> _hlsMediaReferencesForPosition(
    String body,
    Duration resumePosition,
  ) {
    final references = <String>[];
    final durations = <Duration>[];
    double? pendingDurationSeconds;
    for (final line
        in body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('#EXTINF:')) {
        pendingDurationSeconds = _parseExtInfSeconds(trimmed);
        continue;
      }
      if (trimmed.isEmpty || trimmed.startsWith('#') || _isDataUri(trimmed)) {
        continue;
      }
      references.add(trimmed);
      final milliseconds = ((pendingDurationSeconds ?? 0) * 1000).round();
      durations.add(Duration(milliseconds: milliseconds));
      pendingDurationSeconds = null;
    }
    if (references.isEmpty) return const <String>[];

    var playbackStartSegment = 0;
    if (resumePosition > Duration.zero &&
        durations.any((duration) => duration > Duration.zero)) {
      var skippedSegments = 0;
      var skippedDuration = Duration.zero;
      for (final duration in durations) {
        if (duration <= Duration.zero) break;
        final nextSkipped = skippedDuration + duration;
        if (nextSkipped > resumePosition - const Duration(seconds: 1)) {
          break;
        }
        skippedSegments += 1;
        skippedDuration = nextSkipped;
      }
      if (skippedSegments > 0 && skippedSegments < references.length) {
        playbackStartSegment = math.max(
          0,
          skippedSegments - _continuousTsResumePrerollSegments,
        );
      }
    }
    final startupDurations =
        durations.skip(playbackStartSegment).toList(growable: false);
    final startupSegmentCount =
        _continuousTsStartupLeadSegmentCount(startupDurations);
    return List<String>.unmodifiable(
      references.skip(playbackStartSegment).take(startupSegmentCount),
    );
  }

  static String? _firstHlsMediaReference(String body) {
    for (final line
        in body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || _isDataUri(trimmed)) {
        continue;
      }
      return trimmed;
    }
    return null;
  }

  static List<Uri> _hlsPreflightMediaCandidates(
    Uri baseUri,
    String reference,
  ) {
    final canonical = baseUri.resolve(reference.trim());
    if (baseUri.query.isEmpty ||
        canonical.query.isNotEmpty ||
        !_sameOrigin(baseUri, canonical)) {
      return <Uri>[canonical];
    }
    return <Uri>[
      canonical,
      canonical.replace(query: baseUri.query),
    ];
  }

  static void _cachePreflightSegment(
    Uri uri,
    List<int> bytes,
    String contentTypeBucket,
  ) {
    _discardExpiredPreflightSegments();
    _continuousTsPreflightCache[uri.toString()] =
        _HlsPreflightSegmentCacheEntry(
      bytes: Uint8List.fromList(bytes),
      contentTypeBucket: contentTypeBucket,
      expiresAt: DateTime.now().add(_continuousTsPreflightCacheTtl),
    );
  }

  static _HlsPreflightSegmentCacheEntry? _takePreflightSegment(Uri uri) {
    _discardExpiredPreflightSegments();
    return _continuousTsPreflightCache.remove(uri.toString());
  }

  static void _discardPreflightSegments(Iterable<Uri> uris) {
    for (final uri in uris) {
      _continuousTsPreflightCache.remove(uri.toString());
    }
  }

  static void _discardExpiredPreflightSegments() {
    final now = DateTime.now();
    _continuousTsPreflightCache.removeWhere(
      (_, entry) => !entry.expiresAt.isAfter(now),
    );
  }

  static Future<_HlsPreflightChildResponse?> _readHlsPreflightChild({
    required Uri rootUri,
    required Uri childUri,
    Iterable<Uri> fallbackChildUris = const <Uri>[],
    required Map<String, String> headers,
    required Duration timeout,
    required bool expectPlaylist,
    void Function(String message)? onEvent,
  }) async {
    var sawUnreadableResponse = false;
    var sawInconclusiveResponse = false;
    final requestUris = <Uri>[childUri, ...fallbackChildUris];
    for (var requestIndex = 0;
        requestIndex < requestUris.length;
        requestIndex += 1) {
      final requestUri = requestUris[requestIndex];
      final context = requestIndex == 0 ? 'canonical' : 'inherited_query';
      final sameOrigin = _sameOrigin(rootUri, requestUri);
      final canonicalHeaders = <String, String>{
        for (final entry in headers.entries)
          if (sameOrigin ||
              _continuousTsCrossOriginSafeHeaders.contains(
                entry.key.trim().toLowerCase(),
              ))
            entry.key: entry.value,
      };
      final attempts = <Map<String, String>>[
        canonicalHeaders,
        if (!sameOrigin && canonicalHeaders.isNotEmpty)
          const <String, String>{},
      ];

      for (var headerIndex = 0;
          headerIndex < attempts.length;
          headerIndex += 1) {
        final attemptHeaders = attempts[headerIndex];
        final headerContext = headerIndex == 0 ? 'configured' : 'stripped';
        final client = HttpClient()..autoUncompress = false;
        try {
          final request = await client.getUrl(requestUri).timeout(timeout);
          request.persistentConnection = false;
          for (final header in attemptHeaders.entries) {
            final name = header.key.trim();
            final value = header.value.trim();
            if (name.isEmpty ||
                value.isEmpty ||
                name.toLowerCase() == HttpHeaders.acceptEncodingHeader) {
              continue;
            }
            request.headers.set(name, value);
          }
          request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
          request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
          request.headers.set('Pragma', 'no-cache');

          final response = await request.close().timeout(timeout);
          final effectiveUri = _effectiveResponseUri(
            requestUri,
            response.redirects,
          );
          if (response.statusCode < 200 || response.statusCode >= 300) {
            sawUnreadableResponse = true;
            onEvent?.call(
              'segment result context=$context headers=$headerContext '
              'status=${_statusBucket(response.statusCode)} body=unreadable',
            );
            await response.drain<void>().timeout(timeout);
            continue;
          }
          if (expectPlaylist) {
            final body =
                await utf8.decoder.bind(response).join().timeout(timeout);
            return _HlsPreflightChildResponse(
              readable: true,
              requestUri: requestUri,
              effectiveUri: effectiveUri,
              body: body,
            );
          }
          final mediaBytes =
              await _collectBoundedPreflightBytes(response).timeout(
            timeout,
          );
          if (mediaBytes.length < 188) {
            sawUnreadableResponse = true;
            onEvent?.call(
              'segment result context=$context headers=$headerContext '
              'status=ok body=unreadable bytes=${_byteBucket(mediaBytes.length)} '
              'magic=${_magicBucket(mediaBytes)}',
            );
            continue;
          }
          onEvent?.call(
            'segment result context=$context headers=$headerContext '
            'status=ok body=readable bytes=${_byteBucket(mediaBytes.length)} '
            'magic=${_magicBucket(mediaBytes)}',
          );
          return _HlsPreflightChildResponse(
            readable: true,
            requestUri: requestUri,
            effectiveUri: effectiveUri,
            mediaBytes: mediaBytes,
            contentTypeBucket: _contentTypeBucket(response.headers.contentType),
          );
        } on TimeoutException {
          sawInconclusiveResponse = true;
          onEvent?.call(
            'segment result context=$context headers=$headerContext '
            'status=timeout body=inconclusive',
          );
        } on SocketException {
          sawInconclusiveResponse = true;
          onEvent?.call(
            'segment result context=$context headers=$headerContext '
            'status=socket body=inconclusive',
          );
        } on HttpException {
          sawInconclusiveResponse = true;
          onEvent?.call(
            'segment result context=$context headers=$headerContext '
            'status=http body=inconclusive',
          );
        } on _HlsPreflightSegmentTooLarge {
          sawUnreadableResponse = true;
          onEvent?.call(
            'segment result context=$context headers=$headerContext '
            'status=ok body=too_large',
          );
        } finally {
          client.close(force: true);
        }
      }
    }
    if (sawInconclusiveResponse) return null;
    return sawUnreadableResponse
        ? _HlsPreflightChildResponse(
            readable: false,
            requestUri: childUri,
            effectiveUri: childUri,
          )
        : null;
  }

  final Uri localUri;
  final HttpServer _server;
  HttpClient _client;
  final Map<String, Uri> _uriById;
  final Set<String> _playlistIds;
  final Map<String, String> _headers;
  final bool _limitHeadersToUpstreamOrigin;
  final Duration _resumePosition;
  final String _token;
  final bool _continuousTsMode;
  final int _continuousTsTargetHeight;
  final Set<int> _continuousTsExcludedHeights;
  final Duration Function()? _currentPlaybackPosition;
  final void Function(Duration duration)? _onDuration;
  final void Function(int streamedSegments)? _onContinuousTsProgress;
  final void Function(int streamedBytes)? _onContinuousTsBytes;
  final void Function()? _onContinuousTsTransportActivity;
  final void Function()? _onContinuousTsStartupLeadReady;
  final void Function(Duration bufferedPosition)?
      _onContinuousTsBufferedPosition;
  final void Function(int selectedHeight)? _onContinuousTsRenditionSelected;
  final void Function(int failedHeight)? _onContinuousTsRenditionFailure;
  final void Function(Duration offset)? _onTimelineOffset;
  final void Function(int upstreamErrors, String lastStatusBucket)?
      _onContinuousTsUpstreamError;
  final void Function(String message) _onEvent;
  late final StreamSubscription<HttpRequest> _subscription;
  var _closed = false;
  var _nextId = 0;
  var _requestCount = 0;
  var _playlistCount = 0;
  var _mediaCount = 0;
  var _headCount = 0;
  var _rangeCount = 0;
  var _ignoredRangeCount = 0;
  var _notFoundCount = 0;
  var _upstreamErrorCount = 0;
  var _transientRetryCount = 0;
  var _lastStatusBucket = 'none';
  var _continuousTsRequestGeneration = 0;
  _ContinuousTsSegmentRequestPreference? _continuousTsSegmentRequestPreference;
  var _continuousTsSelectedHeight = 0;
  var _continuousTsRenditionFailureReported = false;
  final List<_RelaySessionCookie> _sessionCookies = <_RelaySessionCookie>[];
  final Map<Uri, Uri> _continuousTsSegmentQueryFallbacks = <Uri, Uri>{};
  final Set<String> _continuousTsRequestShapesLogged = <String>{};
  static const int _continuousTsResumePrerollSegments = 2;
  static const Duration _continuousTsPreflightCacheTtl = Duration(seconds: 30);
  static const int _continuousTsPreflightConcurrency = 3;
  static final Map<String, _HlsPreflightSegmentCacheEntry>
      _continuousTsPreflightCache = <String, _HlsPreflightSegmentCacheEntry>{};
  static const int _continuousTsStartupSegmentSkipBudget = 12;
  static const Duration _continuousTsStartupLeadTarget = Duration(seconds: 120);
  static const Duration _continuousTsStartupLeadMaxElapsed =
      Duration(seconds: 18);
  static const int _continuousTsStartupLeadMaxSegments = 24;
  static const int _continuousTsStartupConsecutiveFailureLimit = 6;
  static const int _continuousTsSustainPrefetchWindow = 1;
  static const Duration _continuousTsLeadHighWatermark = Duration(seconds: 180);
  static const Duration _continuousTsLeadResumeWatermark =
      Duration(seconds: 120);
  static const Duration _continuousTsLeadPollInterval = Duration(
    milliseconds: 250,
  );
  static const Duration _continuousTsSustainGapRetryDelay = Duration(
    milliseconds: 250,
  );
  static const int _continuousTsSustainGapRetryMaxRounds = 4;
  static const Duration _continuousTsSustainGapRetryMaxElapsed = Duration(
    seconds: 8,
  );
  static const int _continuousTsStartupSegmentMaxAttempts = 1;
  static const int _continuousTsSustainSegmentMaxAttempts = 6;
  static const int _continuousTsSustainStatusMaxAttempts = 3;
  static const int _continuousTsPlaylistRefreshMaxAttempts = 2;
  static const Duration _continuousTsSustainRetryLeadFloor = Duration(
    seconds: 20,
  );
  static const Duration _continuousTsSustainRetryMaxElapsed = Duration(
    seconds: 75,
  );
  static const int _continuousTsSegmentMaxBytes = 32 * 1024 * 1024;
  static const Duration _continuousTsSegmentIdleTimeout = Duration(seconds: 10);
  static const Set<String> _continuousTsCrossOriginSafeHeaders = <String>{
    HttpHeaders.userAgentHeader,
    HttpHeaders.refererHeader,
    'origin',
    HttpHeaders.acceptHeader,
    HttpHeaders.acceptLanguageHeader,
  };

  String get summary =>
      'requests=$_requestCount playlists=$_playlistCount media=$_mediaCount '
      'heads=$_headCount ranges=$_rangeCount ignoredRanges=$_ignoredRangeCount '
      'notFound=$_notFoundCount upstreamErrors=$_upstreamErrorCount '
      'transientRetries=$_transientRetryCount '
      'lastStatus=$_lastStatusBucket';

  void _notifyContinuousTsUpstreamError() {
    if (_continuousTsSelectedHeight > 0 &&
        !_continuousTsRenditionFailureReported) {
      _continuousTsRenditionFailureReported = true;
      _onContinuousTsRenditionFailure?.call(_continuousTsSelectedHeight);
    }
    _onContinuousTsUpstreamError?.call(
      _upstreamErrorCount,
      _lastStatusBucket,
    );
  }

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
    _continuousTsRequestGeneration += 1;
    await _subscription.cancel();
    _client.close(force: true);
    await _server.close(force: true);
    _uriById.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_closed) {
      await _closeWith(request.response, HttpStatus.gone);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      await _closeWith(request.response, HttpStatus.methodNotAllowed);
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length != 3 ||
        segments[0] != 'juicr-libvlc-hls' ||
        segments[1] != _token) {
      _notFoundCount += 1;
      await _closeWith(request.response, HttpStatus.notFound);
      return;
    }
    final id = segments[2].split('.').first;
    final upstream = _uriById[id];
    if (upstream == null) {
      _notFoundCount += 1;
      await _closeWith(request.response, HttpStatus.notFound);
      return;
    }
    _requestCount += 1;
    if (request.method == 'HEAD') _headCount += 1;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final knownPlaylistRequest = _playlistIds.contains(id);
    if (range != null && range.trim().isNotEmpty) {
      _rangeCount += 1;
      _ignoredRangeCount += 1;
    }

    if (_continuousTsMode && id == 'root') {
      await _handleContinuousTsRequest(request, upstream);
      return;
    }

    HttpClientRequest upstreamRequest;
    try {
      upstreamRequest = await _openUpstream(upstream);
    } catch (_) {
      _upstreamErrorCount += 1;
      _onEvent('native libvlc hls relay request failed stage=open ${summary}');
      await _closeWith(request.response, HttpStatus.badGateway);
      return;
    }

    try {
      final upstreamResponse = await upstreamRequest.close();
      final effectiveUpstream = _effectiveResponseUri(
        upstream,
        upstreamResponse.redirects,
      );
      _captureSessionCookies(effectiveUpstream, upstreamResponse.cookies);
      final contentType = upstreamResponse.headers.contentType;
      final encodingBucket = _encodingBucket(
        upstreamResponse.headers.value(HttpHeaders.contentEncodingHeader),
      );
      final looksLikePlaylist = knownPlaylistRequest ||
          _pathLooksLikePlaylist(effectiveUpstream.path) ||
          (contentType?.mimeType.toLowerCase().contains('mpegurl') ?? false);
      if (looksLikePlaylist) _playlistIds.add(id);
      _lastStatusBucket = _statusBucket(upstreamResponse.statusCode);
      if (looksLikePlaylist) {
        _playlistCount += 1;
      } else {
        _mediaCount += 1;
      }
      if (_requestCount <= 12 || _requestCount % 10 == 0) {
        _onEvent(
          'native libvlc hls relay request ok kind=${looksLikePlaylist ? 'playlist' : 'media'} '
          'method=${request.method.toLowerCase()} encoding=$encodingBucket '
          'extension=${looksLikePlaylist ? 'm3u8' : _extensionBucket(upstream.path)} ${summary}',
        );
      }

      if (upstreamResponse.statusCode < 200 ||
          upstreamResponse.statusCode >= 300) {
        if (upstreamResponse.statusCode == HttpStatus.notFound) {
          _notFoundCount += 1;
        } else {
          _upstreamErrorCount += 1;
        }
        _onEvent(
          'native libvlc hls relay upstream rejected kind=${looksLikePlaylist ? 'playlist' : 'media'} '
          'status=$_lastStatusBucket ${summary}',
        );
        await upstreamResponse.drain<void>();
        await _closeWith(request.response, upstreamResponse.statusCode);
        return;
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');

      if (request.method == 'HEAD') {
        final length = upstreamResponse.contentLength;
        if (length >= 0) request.response.contentLength = length;
        await request.response.close();
        return;
      }

      if (looksLikePlaylist) {
        final bytes = await _collectBytes(upstreamResponse);
        final body = _decodePlaylist(bytes, encodingBucket);
        _onEvent(
          'native libvlc hls relay playlist shape ${_playlistShape(body)}',
        );
        final rewritten = _rewritePlaylist(effectiveUpstream, body);
        final rewrittenBytes = utf8.encode(rewritten);
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.contentLength = rewrittenBytes.length;
        request.response.add(rewrittenBytes);
        await request.response.close();
        return;
      }

      final extensionBucket = _extensionBucket(upstream.path);
      final relayContentType = _relayMediaContentType(
        contentType,
        extensionBucket,
      );
      if (relayContentType != null) {
        request.response.headers.contentType = relayContentType;
      }
      await _pipeMediaResponse(
        upstreamResponse,
        request.response,
        contentTypeBucket: _contentTypeBucket(relayContentType ?? contentType),
        normalizeTs: extensionBucket == 'ts',
      );
      await request.response.close();
    } catch (error) {
      _upstreamErrorCount += 1;
      _onEvent(
        'native libvlc hls relay request failed stage=response error=${error.runtimeType} ${summary}',
      );
      try {
        await _closeWith(request.response, HttpStatus.badGateway);
      } catch (_) {}
    }
  }

  Future<void> _handleContinuousTsRequest(
    HttpRequest request,
    Uri playlistUri,
  ) async {
    final requestGeneration = ++_continuousTsRequestGeneration;
    _playlistCount += 1;
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    if (request.method == 'HEAD') {
      request.response.headers.contentType = ContentType('video', 'mp2t');
      await request.response.close();
      return;
    }

    var streamedSegments = 0;
    var streamedBytes = 0;
    var rejectedSegments = 0;
    var bufferedDuration = Duration.zero;
    final startupSegments = <_TvSequentialSegment>[];
    try {
      final plan = _trimPlanForResume(await _continuousTsPlan(playlistUri));
      request.response.headers.contentType = plan.isFragmentedMp4
          ? ContentType('video', 'mp4')
          : ContentType('video', 'mp2t');
      if (plan.segmentUris.isEmpty) {
        _upstreamErrorCount += 1;
        _notifyContinuousTsUpstreamError();
        _onEvent(
          'native libvlc hls relay continuous-ts rejected reason=no_segments $summary',
        );
        await request.response.close();
        return;
      }
      if (plan.duration > Duration.zero) {
        _onDuration?.call(plan.duration);
      }
      _onTimelineOffset?.call(plan.timelineOffset);
      _onEvent(
        'native libvlc hls relay continuous-ts start lifecycle=tv_sequential '
        'segments=${_countBucket(plan.segmentUris.length)} '
        'playlistDepth=${plan.playlistDepth} '
        'duration=${_durationBucket(plan.duration)} $summary',
      );

      final segmentQueue = List<Uri>.of(plan.segmentUris);
      final durationQueue = List<Duration>.of(plan.segmentDurations);
      final remainingPlaylistDuration = durationQueue.fold<Duration>(
        Duration.zero,
        (total, duration) => total + duration,
      );
      final completePlaylistDuration = remainingPlaylistDuration > Duration.zero
          ? remainingPlaylistDuration
          : plan.duration;
      final startupLeadCoversCompletePlaylist =
          completePlaylistDuration > Duration.zero &&
              completePlaylistDuration < _continuousTsStartupLeadTarget;
      var startupLeadTarget = startupLeadCoversCompletePlaylist
          ? completePlaylistDuration
          : _continuousTsStartupLeadTarget;
      var startupLeadReported = false;
      var freshTransportAttemptedForFailureStreak = false;

      Future<void> emitSegment(_TvSequentialSegment segment) async {
        _mediaCount += 1;
        final bytesBeforeSegment = streamedBytes;
        final segmentBytes = await _pipeMediaResponse(
          Stream<List<int>>.value(segment.bytes),
          request.response,
          contentTypeBucket: segment.contentTypeBucket,
          normalizeTs: false,
          onBytes: (bytes) {
            _onContinuousTsBytes?.call(bytesBeforeSegment + bytes);
          },
        );
        await request.response.flush();
        streamedBytes += segmentBytes;
        _onContinuousTsBytes?.call(streamedBytes);
        if (segment.isInitialization) return;
        streamedSegments += 1;
        if (streamedSegments == 1 || streamedSegments % 20 == 0) {
          _onContinuousTsProgress?.call(streamedSegments);
          _onEvent(
            'native libvlc hls relay continuous-ts progress '
            'streamed=${_countBucket(streamedSegments)} '
            'bytes=${_byteBucket(streamedBytes)} $summary',
          );
        }
      }

      final initializationUri = plan.initializationUri;
      if (initializationUri != null) {
        final initialization = await _readTvSequentialSegment(
          initializationUri,
          segmentDuration: Duration.zero,
          requestGeneration: requestGeneration,
          establishedLead: false,
          allowFreshTransport: true,
          expectedFragmentedMp4: true,
          onFreshTransportAttempted: () {
            freshTransportAttemptedForFailureStreak = true;
          },
        );
        if (initialization == null || initialization.nestedPlan != null) {
          _upstreamErrorCount += 1;
          _notifyContinuousTsUpstreamError();
          _onEvent(
            'native libvlc hls relay continuous-ts rejected '
            'reason=fragmented_mp4_initialization_unavailable $summary',
          );
          await request.response.close();
          return;
        }
        startupSegments.add(
          _TvSequentialSegment.initialization(
            bytes: initialization.bytes,
            contentTypeBucket: initialization.contentTypeBucket,
          ),
        );
        freshTransportAttemptedForFailureStreak = false;
        _onEvent(
          'native libvlc hls relay continuous-ts initialization ready '
          'format=fragmented_mp4 $summary',
        );
      }

      while (segmentQueue.isNotEmpty &&
          _continuousTsRequestIsActive(requestGeneration)) {
        final segmentUri = segmentQueue.removeAt(0);
        final segmentDuration = durationQueue.isNotEmpty
            ? durationQueue.removeAt(0)
            : Duration.zero;
        final establishedLead = hasEstablishedMobileLibVlcHlsLead(
          startupLeadReady: startupLeadReported,
          emittedSegments: streamedSegments,
          stagedStartupSegments: startupSegments.length,
        );
        var segment = await _readTvSequentialSegment(
          segmentUri,
          segmentDuration: segmentDuration,
          requestGeneration: requestGeneration,
          establishedLead: establishedLead,
          allowFreshTransport: !freshTransportAttemptedForFailureStreak,
          expectedFragmentedMp4: plan.isFragmentedMp4,
          onFreshTransportAttempted: () {
            freshTransportAttemptedForFailureStreak = true;
          },
        );
        if (segment == null && establishedLead) {
          final retryElapsed = Stopwatch()..start();
          var retryRound = 0;

          Duration remainingLead() {
            final currentPlaybackPosition = _currentPlaybackPosition;
            if (currentPlaybackPosition == null) return bufferedDuration;
            try {
              final lead = plan.timelineOffset +
                  bufferedDuration -
                  currentPlaybackPosition();
              return lead > Duration.zero ? lead : Duration.zero;
            } catch (_) {
              return Duration.zero;
            }
          }

          while (segment == null &&
              retryRound < _continuousTsSustainGapRetryMaxRounds &&
              retryElapsed.elapsed < _continuousTsSustainGapRetryMaxElapsed &&
              remainingLead() >= _continuousTsSustainRetryLeadFloor) {
            retryRound += 1;
            _onEvent(
              'native libvlc hls relay continuous-ts segment retry '
              'reason=sustain_segment_retry_bounded '
              'round=$retryRound '
              'lead=${remainingLead().inSeconds}s $summary',
            );
            await Future<void>.delayed(
              _continuousTsSustainGapRetryDelay * retryRound,
            );
            if (!_continuousTsRequestIsActive(requestGeneration)) return;
            freshTransportAttemptedForFailureStreak = false;
            segment = await _readTvSequentialSegment(
              segmentUri,
              segmentDuration: segmentDuration,
              requestGeneration: requestGeneration,
              establishedLead: true,
              allowFreshTransport: true,
              expectedFragmentedMp4: plan.isFragmentedMp4,
              onFreshTransportAttempted: () {
                freshTransportAttemptedForFailureStreak = true;
              },
            );
          }
        }
        if (segment == null) {
          _upstreamErrorCount += 1;
          rejectedSegments += 1;
          if (establishedLead) {
            _notifyContinuousTsUpstreamError();
            _onEvent(
              'native libvlc hls relay continuous-ts rejected '
              'reason=sustain_segment_gap_requires_recovery '
              'rejected=${_countBucket(rejectedSegments)} $summary',
            );
            break;
          }
          if (!startupLeadReported) {
            final remainingPlaylistDuration = durationQueue.fold<Duration>(
              bufferedDuration,
              (total, duration) => total + duration,
            );
            if (remainingPlaylistDuration > Duration.zero &&
                remainingPlaylistDuration < startupLeadTarget) {
              startupLeadTarget = remainingPlaylistDuration;
              _onEvent(
                'native libvlc hls relay continuous-ts startup lead adjusted '
                'reason=available_playlist_window '
                'target=${startupLeadTarget.inSeconds}s $summary',
              );
            }
          }
          _onEvent(
            'native libvlc hls relay continuous-ts segment skipped '
            'reason=startup_segment_skipped '
            'rejected=${_countBucket(rejectedSegments)} $summary',
          );
          const failureLimit = 6;
          if (rejectedSegments >= failureLimit) {
            _notifyContinuousTsUpstreamError();
            _onEvent(
              'native libvlc hls relay continuous-ts rejected '
              'reason=startup_segment_failure_limit '
              'failures=$rejectedSegments limit=$failureLimit $summary',
            );
            break;
          }
          continue;
        }

        rejectedSegments = 0;
        freshTransportAttemptedForFailureStreak = false;
        if (segment.nestedPlan != null) {
          final nestedPlan = segment.nestedPlan!;
          _onEvent(
            'native libvlc hls relay continuous-ts segment playlist expanded '
            'children=${_countBucket(nestedPlan.segmentUris.length)} '
            'lifecycle=tv_sequential',
          );
          if (nestedPlan.segmentUris.isEmpty) {
            _upstreamErrorCount += 1;
            rejectedSegments += 1;
            final failureLimit = streamedSegments == 0 ? 6 : 12;
            if (rejectedSegments >= failureLimit) {
              _notifyContinuousTsUpstreamError();
              break;
            }
            continue;
          }
          segmentQueue.insertAll(0, nestedPlan.segmentUris);
          durationQueue.insertAll(0, nestedPlan.segmentDurations);
          continue;
        }

        bufferedDuration += segmentDuration;
        _onContinuousTsBufferedPosition?.call(
          plan.timelineOffset + bufferedDuration,
        );
        if (!startupLeadReported) {
          startupSegments.add(segment);
          if (bufferedDuration < startupLeadTarget) {
            if (startupSegments.length >= _continuousTsStartupLeadMaxSegments) {
              _notifyContinuousTsUpstreamError();
              _onEvent(
                'native libvlc hls relay continuous-ts rejected '
                'reason=startup_lead_duration_unavailable '
                'segments=${_countBucket(startupSegments.length)} '
                'duration=${bufferedDuration.inSeconds}s '
                'target=${startupLeadTarget.inSeconds}s $summary',
              );
              break;
            }
            continue;
          }
          startupLeadReported = true;
          _onContinuousTsStartupLeadReady?.call();
          _onEvent(
            'native libvlc hls relay continuous-ts startup lead ready '
            'segments=${_countBucket(startupSegments.length)} '
            'duration=${bufferedDuration.inSeconds}s '
            'lifecycle=tv_sequential $summary',
          );
          for (final startupSegment in startupSegments) {
            await emitSegment(startupSegment);
          }
          startupSegments.clear();
        } else {
          await emitSegment(segment);
        }
        final mayContinue = await _waitForContinuousTsLeadBudget(
          requestGeneration: requestGeneration,
          bufferedPosition: plan.timelineOffset + bufferedDuration,
        );
        if (!mayContinue) break;
      }
      _onEvent(
        'native libvlc hls relay continuous-ts finished '
        'streamed=${_countBucket(streamedSegments)} $summary',
      );
      if (streamedSegments == 0) {
        _onEvent(
          'native libvlc hls relay continuous-ts rejected '
          'reason=startup_lead_unavailable $summary',
        );
      }
      await request.response.close();
    } catch (error) {
      if (!_closed) {
        _upstreamErrorCount += 1;
        _notifyContinuousTsUpstreamError();
        _onEvent(
          'native libvlc hls relay continuous-ts failed '
          'error=${error.runtimeType} $summary',
        );
      }
      try {
        await request.response.close();
      } catch (_) {}
    } finally {
      _invalidateContinuousTsRequest(requestGeneration);
    }
  }

  Future<bool> _waitForContinuousTsLeadBudget({
    required int requestGeneration,
    required Duration bufferedPosition,
  }) async {
    final currentPlaybackPosition = _currentPlaybackPosition;
    if (currentPlaybackPosition == null) return true;

    Duration playbackPosition() {
      try {
        return currentPlaybackPosition();
      } catch (_) {
        return bufferedPosition;
      }
    }

    var lead = bufferedPosition - playbackPosition();
    if (lead < _continuousTsLeadHighWatermark) return true;
    _onEvent(
      'native libvlc hls relay continuous-ts lead held '
      'lead=${lead.inSeconds}s high=${_continuousTsLeadHighWatermark.inSeconds}s',
    );
    while (_continuousTsRequestIsActive(requestGeneration)) {
      await Future<void>.delayed(_continuousTsLeadPollInterval);
      lead = bufferedPosition - playbackPosition();
      if (lead <= _continuousTsLeadResumeWatermark) {
        _onEvent(
          'native libvlc hls relay continuous-ts lead released '
          'lead=${lead.inSeconds}s resume=${_continuousTsLeadResumeWatermark.inSeconds}s',
        );
        return true;
      }
    }
    return false;
  }

  Future<_TvSequentialSegment?> _readTvSequentialSegment(
    Uri segmentUri, {
    required Duration segmentDuration,
    required int requestGeneration,
    required bool establishedLead,
    required bool allowFreshTransport,
    required bool expectedFragmentedMp4,
    required void Function() onFreshTransportAttempted,
  }) async {
    final fallbackUri = _continuousTsSegmentQueryFallbacks[segmentUri];
    _discardExpiredPreflightSegments();
    final preflightCacheEntries = _continuousTsPreflightCache.length;
    final preflightSegment = _takePreflightSegment(segmentUri) ??
        (fallbackUri == null ? null : _takePreflightSegment(fallbackUri));
    _onEvent(
      'native libvlc hls relay continuous-ts preflight cache '
      'result=${preflightSegment == null ? 'miss' : 'hit'} '
      'entries=${_countBucket(preflightCacheEntries)} '
      'queryFallback=${fallbackUri == null ? 'absent' : 'present'}',
    );
    if (preflightSegment != null) {
      if (!_continuousTsRequestIsActive(requestGeneration)) return null;
      final normalizedBytes = expectedFragmentedMp4
          ? preflightSegment.bytes
          : _trimToMpegTsSync(preflightSegment.bytes);
      final validMedia = expectedFragmentedMp4
          ? _magicBucket(normalizedBytes) == 'mp4_box'
          : normalizedBytes.isNotEmpty && normalizedBytes.first == 0x47;
      if (validMedia) {
        _onContinuousTsTransportActivity?.call();
        _onEvent(
          'native libvlc hls relay continuous-ts segment reused '
          "phase=${establishedLead ? 'sustain' : 'startup'} "
          'source=validated_preflight',
        );
        return _TvSequentialSegment.media(
          bytes: normalizedBytes,
          contentTypeBucket: preflightSegment.contentTypeBucket,
        );
      }
    }
    final requestPlans = <_ContinuousTsSegmentRequestPlan>[];
    void addRequestPlan(_ContinuousTsSegmentRequestPlan plan) {
      final duplicate = requestPlans.any(
        (existing) =>
            existing.uri == plan.uri &&
            existing.suppressConfiguredHeaders ==
                plan.suppressConfiguredHeaders &&
            existing.useFreshTransport == plan.useFreshTransport,
      );
      if (!duplicate) requestPlans.add(plan);
    }

    final preferredRequest = _continuousTsSegmentRequestPreference;
    if (allowFreshTransport && preferredRequest != null) {
      addRequestPlan(
        _ContinuousTsSegmentRequestPlan(
          uri: segmentUri,
          context: preferredRequest.context,
          suppressConfiguredHeaders: preferredRequest.suppressConfiguredHeaders,
          useFreshTransport: true,
        ),
      );
    }
    addRequestPlan(
      _ContinuousTsSegmentRequestPlan(
        uri: segmentUri,
        context: 'canonical',
      ),
    );
    if (_shouldTryCrossOriginHeaderlessFallback(segmentUri)) {
      addRequestPlan(
        _ContinuousTsSegmentRequestPlan(
          uri: segmentUri,
          suppressConfiguredHeaders: true,
          context: 'stripped_headers',
        ),
      );
    }
    if (fallbackUri != null) {
      addRequestPlan(
        _ContinuousTsSegmentRequestPlan(
          uri: fallbackUri,
          context: 'inherited_query',
        ),
      );
    }
    if (!establishedLead &&
        allowFreshTransport &&
        _shouldTryCrossOriginHeaderlessFallback(segmentUri)) {
      addRequestPlan(
        _ContinuousTsSegmentRequestPlan(
          uri: segmentUri,
          context: 'fresh_transport_stripped_headers',
          suppressConfiguredHeaders: true,
          useFreshTransport: true,
        ),
      );
    }
    if (establishedLead && allowFreshTransport) {
      addRequestPlan(
        _ContinuousTsSegmentRequestPlan(
          uri: segmentUri,
          context: 'fresh_transport',
          suppressConfiguredHeaders: true,
          useFreshTransport: true,
        ),
      );
    }
    final wallClockTimeout = _shorterDuration(
      _continuousTsSegmentDeadline(
        segmentDuration,
        establishedLead: establishedLead,
      ),
      const Duration(seconds: 8),
    );

    for (var index = 0; index < requestPlans.length; index += 1) {
      if (!_continuousTsRequestIsActive(requestGeneration)) return null;
      final plan = requestPlans[index];
      _onContinuousTsTransportActivity?.call();
      _logContinuousTsSegmentRequestShape(
        plan,
        establishedLead: establishedLead,
        queryFallbackAvailable: fallbackUri != null,
      );
      HttpClient? freshClient;
      HttpClientRequest? upstreamRequest;
      try {
        if (plan.useFreshTransport) {
          onFreshTransportAttempted();
        }
        final requestClient = plan.useFreshTransport
            ? (freshClient = HttpClient()..autoUncompress = false)
            : _client;
        upstreamRequest = await _openUpstreamWithClient(
          requestClient,
          plan.uri,
          forceFreshCacheBypass: plan.useFreshTransport,
          suppressConfiguredHeaders: plan.suppressConfiguredHeaders,
        ).timeout(wallClockTimeout);
        final response =
            await upstreamRequest.close().timeout(wallClockTimeout);
        final effectiveUri = _effectiveResponseUri(
          plan.uri,
          response.redirects,
        );
        _captureSessionCookies(effectiveUri, response.cookies);
        _lastStatusBucket = _statusBucket(response.statusCode);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.drain<void>().timeout(wallClockTimeout);
          if (index + 1 < requestPlans.length) {
            final nextContext = requestPlans[index + 1].context;
            _onEvent(
              'native libvlc hls relay continuous-ts segment request fallback '
              'reason=status '
              "${nextContext == 'inherited_query' ? 'query=inherited' : 'context=$nextContext'} "
              'status=$_lastStatusBucket $summary',
            );
          }
          continue;
        }

        final contentTypeBucket = _contentTypeBucket(
          response.headers.contentType,
        );
        final rawBytes = await _collectContinuousTsSegmentBytes(
          response,
          idleTimeout: _shorterDuration(
            _continuousTsSegmentIdleTimeout,
            wallClockTimeout,
          ),
          wallClockTimeout: wallClockTimeout,
          requestGeneration: requestGeneration,
          onBytes: (_) => _onContinuousTsTransportActivity?.call(),
        );
        void adoptFreshTransport() {
          final replacement = freshClient;
          if (replacement == null) return;
          final previous = _client;
          _client = replacement;
          freshClient = null;
          previous.close(force: true);
          _onEvent(
            'native libvlc hls relay continuous-ts transport rotated '
            'reason=segment_connection_rejected',
          );
        }

        _rememberContinuousTsSegmentRequestPlan(plan);
        if (contentTypeBucket == 'playlist') {
          final body = _decodePlaylist(rawBytes, 'identity');
          adoptFreshTransport();
          return _TvSequentialSegment.playlist(
            _playlistSegmentPlan(effectiveUri, body),
          );
        }
        if (rawBytes.isEmpty) continue;
        final normalizedBytes =
            expectedFragmentedMp4 ? rawBytes : _trimToMpegTsSync(rawBytes);
        final validMedia = expectedFragmentedMp4
            ? _magicBucket(normalizedBytes) == 'mp4_box'
            : normalizedBytes.isNotEmpty && normalizedBytes.first == 0x47;
        if (!validMedia) {
          _lastStatusBucket = 'invalid_media';
          continue;
        }
        adoptFreshTransport();
        return _TvSequentialSegment.media(
          bytes: normalizedBytes,
          contentTypeBucket: contentTypeBucket,
        );
      } catch (error) {
        upstreamRequest?.abort(error);
        _lastStatusBucket = error is TimeoutException ? 'slow' : 'io';
        if (index + 1 < requestPlans.length) {
          final nextContext = requestPlans[index + 1].context;
          _onEvent(
            'native libvlc hls relay continuous-ts segment request fallback '
            'reason=${error.runtimeType} '
            "${nextContext == 'inherited_query' ? 'query=inherited' : 'context=$nextContext'} "
            'status=$_lastStatusBucket $summary',
          );
        }
      } finally {
        freshClient?.close(force: true);
      }
    }
    return null;
  }

  void _rememberContinuousTsSegmentRequestPlan(
    _ContinuousTsSegmentRequestPlan plan,
  ) {
    if (!plan.useFreshTransport) {
      if (_continuousTsSegmentRequestPreference != null) {
        _continuousTsSegmentRequestPreference = null;
        _onEvent(
          'native libvlc hls relay continuous-ts segment request preference '
          'cleared reason=non_fresh_success',
        );
      }
      return;
    }
    final nextPreference = _ContinuousTsSegmentRequestPreference(
      context: plan.context,
      suppressConfiguredHeaders: plan.suppressConfiguredHeaders,
    );
    if (_continuousTsSegmentRequestPreference == nextPreference) return;
    _continuousTsSegmentRequestPreference = nextPreference;
    _onEvent(
      'native libvlc hls relay continuous-ts segment request preference '
      'remembered context=${plan.context}',
    );
  }

  Future<void> _handleContinuousTsRequestLegacy(
    HttpRequest request,
    Uri playlistUri,
  ) async {
    final requestGeneration = ++_continuousTsRequestGeneration;
    _playlistCount += 1;
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    request.response.headers.contentType = ContentType('video', 'mp2t');
    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    var streamedSegments = 0;
    var streamedBytes = 0;
    var bufferedDuration = Duration.zero;
    try {
      var plan = _trimPlanForResume(await _continuousTsPlan(playlistUri));
      if (plan.segmentUris.isEmpty) {
        _upstreamErrorCount += 1;
        _notifyContinuousTsUpstreamError();
        _onEvent(
          'native libvlc hls relay continuous-ts rejected reason=no_segments ${summary}',
        );
        await request.response.close();
        return;
      }
      if (plan.duration > Duration.zero) {
        _onDuration?.call(plan.duration);
      }
      _onEvent(
        'native libvlc hls relay continuous-ts start segments=${_countBucket(plan.segmentUris.length)} '
        'playlistDepth=${plan.playlistDepth} duration=${_durationBucket(plan.duration)} ${summary}',
      );
      final pendingSegments = <int, Future<_ContinuousTsSegmentPayload?>>{};
      var firstStartupSegmentIndex = 0;
      var effectiveTimelineOffset = plan.timelineOffset;

      void scheduleSegment(
        int segmentIndex, {
        bool? establishedLead,
      }) {
        if (segmentIndex < 0 ||
            segmentIndex >= plan.segmentUris.length ||
            pendingSegments.containsKey(segmentIndex) ||
            !_continuousTsRequestIsActive(requestGeneration)) {
          return;
        }
        final hasEstablishedLead = establishedLead ?? streamedSegments > 0;
        pendingSegments[segmentIndex] = _readContinuousTsSegment(
          plan.segmentUris[segmentIndex],
          segmentDuration: plan.segmentDurations[segmentIndex],
          requestGeneration: requestGeneration,
          establishedLead: hasEstablishedLead,
          notifyFatalFailure: false,
          currentBufferedPosition: () =>
              effectiveTimelineOffset + bufferedDuration,
        );
      }

      Future<bool> ensureStartupLead() async {
        final startupLeadElapsed = Stopwatch()..start();
        var startupLeadDeadlineLogged = false;

        bool startupLeadDeadlineExpired() {
          if (startupLeadElapsed.elapsed < _continuousTsStartupLeadMaxElapsed) {
            return false;
          }
          if (!startupLeadDeadlineLogged) {
            startupLeadDeadlineLogged = true;
            _onEvent(
              'native libvlc hls relay continuous-ts startup lead rejected '
              'reason=startup_lead_deadline elapsed=${_durationBucket(startupLeadElapsed.elapsed)} '
              '${summary}',
            );
          }
          return true;
        }

        final startupSegmentSkipBudget = math.min(
          _continuousTsStartupSegmentSkipBudget,
          math.max(0, plan.segmentUris.length - 1),
        );
        var candidateStartIndex = 0;
        var consecutiveStartupFailures = 0;
        while (candidateStartIndex <= startupSegmentSkipBudget) {
          if (startupLeadDeadlineExpired()) return false;
          var startupLeadDuration = Duration.zero;
          final startupSegmentCount = _continuousTsStartupLeadSegmentCount(
            plan.segmentDurations
                .skip(candidateStartIndex)
                .toList(growable: false),
          );
          var failedSegmentIndex = -1;
          for (var offset = 0; offset < startupSegmentCount; offset += 1) {
            final segmentIndex = candidateStartIndex + offset;
            scheduleSegment(segmentIndex, establishedLead: false);
            final remainingStartupLeadTime =
                _continuousTsStartupLeadMaxElapsed - startupLeadElapsed.elapsed;
            if (remainingStartupLeadTime <= Duration.zero) {
              startupLeadDeadlineExpired();
              return false;
            }
            final payload = await pendingSegments[segmentIndex]!.timeout(
              remainingStartupLeadTime,
              onTimeout: () => null,
            );
            if (payload == null ||
                !_continuousTsRequestIsActive(requestGeneration)) {
              failedSegmentIndex = segmentIndex;
              break;
            }
            startupLeadDuration += plan.segmentDurations[segmentIndex];
          }
          if (failedSegmentIndex < 0) {
            firstStartupSegmentIndex = candidateStartIndex;
            final skippedStartupDuration = plan.segmentDurations
                .take(firstStartupSegmentIndex)
                .fold<Duration>(
                  Duration.zero,
                  (total, duration) => total + duration,
                );
            effectiveTimelineOffset =
                plan.timelineOffset + skippedStartupDuration;
            _onTimelineOffset?.call(effectiveTimelineOffset);
            _onEvent(
              'native libvlc hls relay continuous-ts startup lead ready '
              'segments=${_countBucket(startupSegmentCount)} '
              'duration=${_durationBucket(startupLeadDuration)} '
              'target=${_durationBucket(_continuousTsStartupLeadTarget)} ${summary}',
            );
            _onContinuousTsStartupLeadReady?.call();
            return true;
          }
          if (!_continuousTsRequestIsActive(requestGeneration) ||
              startupLeadDeadlineExpired() ||
              failedSegmentIndex >= startupSegmentSkipBudget) {
            return false;
          }
          consecutiveStartupFailures += 1;
          if (consecutiveStartupFailures >=
              _continuousTsStartupConsecutiveFailureLimit) {
            _onEvent(
              'native libvlc hls relay continuous-ts startup lead rejected '
              'reason=startup_segment_failure_limit '
              'failures=$consecutiveStartupFailures ${summary}',
            );
            return false;
          }
          candidateStartIndex = failedSegmentIndex + 1;
          pendingSegments.clear();
          _onEvent(
            'native libvlc hls relay continuous-ts startup lead retry '
            'segment=${_countBucket(failedSegmentIndex + 1)} '
            'reason=startup_segment_skipped '
            'remainingSkipBudget=${startupSegmentSkipBudget - candidateStartIndex} ${summary}',
          );
        }
        return false;
      }

      if (!await ensureStartupLead()) {
        _notifyContinuousTsUpstreamError();
        _invalidateContinuousTsRequest(requestGeneration);
        _onEvent(
          'native libvlc hls relay continuous-ts rejected reason=startup_lead_unavailable ${summary}',
        );
        await request.response.close();
        return;
      }
      for (var segmentIndex = firstStartupSegmentIndex;
          segmentIndex < plan.segmentUris.length;
          segmentIndex += 1) {
        if (!_continuousTsRequestIsActive(requestGeneration)) break;
        var segmentUri = plan.segmentUris[segmentIndex];
        var segmentPayload = await pendingSegments.remove(segmentIndex);
        for (var refreshAttempt = 1;
            segmentPayload == null &&
                refreshAttempt <= _continuousTsPlaylistRefreshMaxAttempts &&
                _continuousTsRequestIsActive(requestGeneration);
            refreshAttempt += 1) {
          _onEvent(
            'native libvlc hls relay continuous-ts playlist refresh '
            'attempt=$refreshAttempt '
            'segment=${_countBucket(segmentIndex + 1)} '
            'reason=sustain_playlist_refresh_after_segment_failure ${summary}',
          );
          try {
            final refreshedPlan = _trimPlanForResume(
              await _continuousTsPlan(
                playlistUri,
                forceFreshCacheBypass: true,
              ),
            );
            if (segmentIndex >= refreshedPlan.segmentUris.length ||
                refreshedPlan.segmentDurations.length !=
                    refreshedPlan.segmentUris.length) {
              _onEvent(
                'native libvlc hls relay continuous-ts playlist refresh '
                'attempt=$refreshAttempt '
                'segment=${_countBucket(segmentIndex + 1)} '
                'reason=sustain_playlist_refresh_missing_segment ${summary}',
              );
              continue;
            }
            plan = refreshedPlan;
            final skippedStartupDuration = plan.segmentDurations
                .take(firstStartupSegmentIndex)
                .fold<Duration>(
                  Duration.zero,
                  (total, duration) => total + duration,
                );
            effectiveTimelineOffset =
                plan.timelineOffset + skippedStartupDuration;
            _onTimelineOffset?.call(effectiveTimelineOffset);
            segmentUri = plan.segmentUris[segmentIndex];
            pendingSegments.removeWhere((index, _) => index >= segmentIndex);
            scheduleSegment(segmentIndex, establishedLead: true);
            segmentPayload = await pendingSegments.remove(segmentIndex);
            if (segmentPayload != null) {
              _onEvent(
                'native libvlc hls relay continuous-ts playlist refresh '
                'attempt=$refreshAttempt '
                'segment=${_countBucket(segmentIndex + 1)} '
                'reason=sustain_playlist_refresh_recovered ${summary}',
              );
            }
          } catch (error) {
            _onEvent(
              'native libvlc hls relay continuous-ts playlist refresh '
              'attempt=$refreshAttempt '
              'segment=${_countBucket(segmentIndex + 1)} '
              'reason=sustain_playlist_refresh_failed '
              'error=${error.runtimeType} ${summary}',
            );
          }
        }
        if (segmentPayload == null) {
          if (!_continuousTsRequestIsActive(requestGeneration)) break;
          _notifyContinuousTsUpstreamError();
          _invalidateContinuousTsRequest(requestGeneration);
          _onEvent(
            'native libvlc hls relay continuous-ts rejected '
            'segment=${_countBucket(segmentIndex + 1)} '
            'reason=sustain_segment_lead_exhausted ${summary}',
          );
          break;
        }
        streamedSegments += 1;
        _mediaCount += 1;
        if (streamedSegments <= 4) {
          _onEvent(
            'native libvlc hls relay continuous-ts segment proof '
            'segment=${_countBucket(streamedSegments)} '
            'sameOrigin=${_sameOrigin(segmentUri, playlistUri)} '
            'contentLength=${_contentLengthBucket(segmentPayload.bytes.length)}',
          );
        }
        _onEvent(
          'native libvlc hls relay media proof '
          'contentType=${segmentPayload.contentTypeBucket} '
          'magic=${segmentPayload.magicBucket} '
          'normalized=${segmentPayload.normalized} '
          'bytes=${_byteBucket(segmentPayload.bytes.length)}',
        );
        request.response.add(segmentPayload.bytes);
        await request.response.flush();
        streamedBytes += segmentPayload.bytes.length;
        _onContinuousTsBytes?.call(streamedBytes);
        bufferedDuration += plan.segmentDurations[segmentIndex];
        _onContinuousTsBufferedPosition?.call(
          effectiveTimelineOffset + bufferedDuration,
        );
        if (streamedSegments == 1 || streamedSegments % 20 == 0) {
          _onContinuousTsProgress?.call(streamedSegments);
          _onEvent(
            'native libvlc hls relay continuous-ts progress streamed=${_countBucket(streamedSegments)} ${summary}',
          );
        }
        scheduleSegment(segmentIndex + _continuousTsSustainPrefetchWindow);
      }
      _onEvent(
        'native libvlc hls relay continuous-ts finished streamed=${_countBucket(streamedSegments)} ${summary}',
      );
      await request.response.close();
    } catch (error) {
      if (_closed) {
        _onEvent(
          'native libvlc hls relay continuous-ts stopped reason=relay_closed streamed=${_countBucket(streamedSegments)} ${summary}',
        );
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }
      _upstreamErrorCount += 1;
      _notifyContinuousTsUpstreamError();
      _onEvent(
        'native libvlc hls relay continuous-ts failed error=${error.runtimeType} ${summary}',
      );
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<_ContinuousTsSegmentPayload?> _readContinuousTsSegment(
    Uri segmentUri, {
    required Duration segmentDuration,
    required int requestGeneration,
    required bool establishedLead,
    required bool notifyFatalFailure,
    required Duration Function() currentBufferedPosition,
  }) async {
    final fallbackUri = _continuousTsSegmentQueryFallbacks[segmentUri];
    _discardExpiredPreflightSegments();
    final preflightCacheEntries = _continuousTsPreflightCache.length;
    final preflightSegment = _takePreflightSegment(segmentUri) ??
        (fallbackUri == null ? null : _takePreflightSegment(fallbackUri));
    _onEvent(
      'native libvlc hls relay continuous-ts preflight cache '
      'result=${preflightSegment == null ? 'miss' : 'hit'} '
      'entries=${_countBucket(preflightCacheEntries)} '
      'queryFallback=${fallbackUri == null ? 'absent' : 'present'}',
    );
    if (preflightSegment != null) {
      if (!_continuousTsRequestIsActive(requestGeneration)) return null;
      final normalizedBytes = _trimToMpegTsSync(preflightSegment.bytes);
      if (normalizedBytes.isNotEmpty && normalizedBytes.first == 0x47) {
        _onContinuousTsTransportActivity?.call();
        _onEvent(
          'native libvlc hls relay continuous-ts segment reused '
          "phase=${establishedLead ? 'sustain' : 'startup'} "
          'source=validated_preflight',
        );
        return _ContinuousTsSegmentPayload(
          bytes: normalizedBytes,
          contentTypeBucket: preflightSegment.contentTypeBucket,
          magicBucket: _magicBucket(preflightSegment.bytes),
          normalized: normalizedBytes.length != preflightSegment.bytes.length,
        );
      }
    }
    final deadline = _continuousTsSegmentDeadline(
      segmentDuration,
      establishedLead: establishedLead,
    );
    final aggregateElapsed = Stopwatch()..start();
    final sustainStatusElapsed = Stopwatch()..start();
    final maxAttempts = establishedLead
        ? _continuousTsSustainSegmentMaxAttempts
        : _continuousTsStartupSegmentMaxAttempts;
    var forceFreshTransport = false;
    var attempt = 0;
    final canonicalHeaderlessFallback =
        _shouldTryCrossOriginHeaderlessFallback(segmentUri);
    final requestPlans = <_ContinuousTsSegmentRequestPlan>[
      _ContinuousTsSegmentRequestPlan(
        uri: segmentUri,
        context: 'canonical',
      ),
      if (canonicalHeaderlessFallback)
        _ContinuousTsSegmentRequestPlan(
          uri: segmentUri,
          suppressConfiguredHeaders: true,
          context: 'stripped_headers',
        ),
      if (fallbackUri != null)
        _ContinuousTsSegmentRequestPlan(
          uri: fallbackUri,
          context: 'inherited_query',
        ),
      if (fallbackUri != null &&
          _shouldTryCrossOriginHeaderlessFallback(fallbackUri))
        _ContinuousTsSegmentRequestPlan(
          uri: fallbackUri,
          suppressConfiguredHeaders: true,
          context: 'inherited_query_stripped_headers',
        ),
    ];
    var requestPlanIndex = 0;

    int? nextRequestPlanIndex({required bool allowStrippedHeaders}) {
      for (var index = requestPlanIndex + 1;
          index < requestPlans.length;
          index += 1) {
        if (!allowStrippedHeaders &&
            requestPlans[index].suppressConfiguredHeaders) {
          continue;
        }
        return index;
      }
      return null;
    }

    Duration remainingLead() {
      if (!establishedLead) return Duration.zero;
      final playbackPosition =
          _currentPlaybackPosition?.call() ?? Duration.zero;
      final bufferedPosition = currentBufferedPosition();
      if (bufferedPosition <= playbackPosition) return Duration.zero;
      return bufferedPosition - playbackPosition;
    }

    bool canRetryUsingBufferedLead() {
      return establishedLead &&
          sustainStatusElapsed.elapsed < _continuousTsSustainRetryMaxElapsed &&
          remainingLead() >= _continuousTsSustainRetryLeadFloor;
    }

    while (true) {
      attempt += 1;
      if (!_continuousTsRequestIsActive(requestGeneration)) return null;
      final attemptElapsed =
          establishedLead ? (Stopwatch()..start()) : aggregateElapsed;
      final remainingBeforeAttempt = deadline - attemptElapsed.elapsed;
      if (remainingBeforeAttempt <= Duration.zero) {
        _upstreamErrorCount += 1;
        _lastStatusBucket = 'slow';
        if (notifyFatalFailure) {
          _notifyContinuousTsUpstreamError();
        }
        _onEvent(
          'native libvlc hls relay continuous-ts segment body rejected '
          'status=$_lastStatusBucket attempts=${attempt - 1} '
          'reason=aggregate_deadline '
          "phase=${establishedLead ? 'sustain' : 'startup'} "
          '${summary}',
        );
        if (notifyFatalFailure) {
          _invalidateContinuousTsRequest(requestGeneration);
        }
        return null;
      }
      HttpClientRequest? segmentRequest;
      HttpClient? freshRetryClient;
      var requestStage = 'open';
      var receivedBytes = 0;
      var declaredBytes = -1;
      try {
        _onContinuousTsTransportActivity?.call();
        if (forceFreshTransport) {
          freshRetryClient = HttpClient()..autoUncompress = false;
        }
        _logContinuousTsSegmentRequestShape(
          requestPlans[requestPlanIndex],
          establishedLead: establishedLead,
          queryFallbackAvailable: fallbackUri != null,
        );
        segmentRequest = await _openUpstreamWithClient(
          freshRetryClient ?? _client,
          requestPlans[requestPlanIndex].uri,
          forceFreshCacheBypass: forceFreshTransport,
          suppressConfiguredHeaders:
              requestPlans[requestPlanIndex].suppressConfiguredHeaders,
        ).timeout(
          remainingBeforeAttempt,
        );
        segmentRequest.persistentConnection =
            establishedLead && !forceFreshTransport;
        requestStage = 'headers';
        final segmentResponse = await segmentRequest.close().timeout(
              _shorterDuration(deadline, deadline - attemptElapsed.elapsed),
            );
        final effectiveSegmentUri = _effectiveResponseUri(
          requestPlans[requestPlanIndex].uri,
          segmentResponse.redirects,
        );
        _captureSessionCookies(effectiveSegmentUri, segmentResponse.cookies);
        requestStage = 'body';
        final statusCode = segmentResponse.statusCode;
        _lastStatusBucket = _statusBucket(statusCode);
        if (statusCode >= 200 && statusCode < 300) {
          if (segmentResponse.contentLength > _continuousTsSegmentMaxBytes) {
            throw const _ContinuousTsSegmentException('segment_too_large');
          }
          var byteCount = 0;
          final declaredContentLength = segmentResponse.contentLength;
          declaredBytes = declaredContentLength;
          final streamTimeout = establishedLead
              ? _continuousTsSegmentIdleTimeout
              : _shorterDuration(
                  _continuousTsSegmentIdleTimeout,
                  deadline - attemptElapsed.elapsed,
                );
          final bodyDeadline = _shorterDuration(
            deadline,
            deadline - attemptElapsed.elapsed,
          );
          final rawBytes = await _collectContinuousTsSegmentBytes(
            segmentResponse,
            idleTimeout: streamTimeout,
            wallClockTimeout: bodyDeadline,
            requestGeneration: requestGeneration,
            onBytes: (count) {
              byteCount = count;
              receivedBytes = count;
            },
          );
          if (!_continuousTsRequestIsActive(requestGeneration)) return null;
          if (rawBytes.isEmpty) {
            throw const _ContinuousTsSegmentException('empty_body');
          }
          if (declaredContentLength >= 0 &&
              byteCount != declaredContentLength) {
            throw const _ContinuousTsSegmentException(
              'content_length_mismatch',
            );
          }
          final normalizedBytes = _trimToMpegTsSync(rawBytes);
          if (normalizedBytes.isEmpty || normalizedBytes.first != 0x47) {
            throw const _ContinuousTsSegmentException('invalid_mpeg_ts');
          }
          return _ContinuousTsSegmentPayload(
            bytes: normalizedBytes,
            contentTypeBucket: _contentTypeBucket(
              segmentResponse.headers.contentType,
            ),
            magicBucket: _magicBucket(rawBytes),
            normalized: normalizedBytes.length != rawBytes.length,
          );
        }
        final retryable = _isTransientContinuousTsStatus(statusCode);
        final nextPlanIndex = nextRequestPlanIndex(
          allowStrippedHeaders: statusCode >= 500 && statusCode < 600,
        );
        if (nextPlanIndex != null) {
          requestPlanIndex = nextPlanIndex;
          forceFreshTransport = true;
          final fallbackContext = requestPlans[requestPlanIndex].context;
          _onEvent(
            'native libvlc hls relay continuous-ts segment request fallback '
            'reason=status '
            '${fallbackContext == 'inherited_query' ? 'query=inherited' : 'context=$fallbackContext'} '
            'status=$_lastStatusBucket ${summary}',
          );
          await segmentResponse.drain<void>().timeout(
                _shorterDuration(
                  _continuousTsSegmentIdleTimeout,
                  deadline - attemptElapsed.elapsed,
                ),
              );
          continue;
        }
        final transientSustainStatus = establishedLead && retryable;
        if (transientSustainStatus) {
          forceFreshTransport = true;
        }
        await segmentResponse.drain<void>().timeout(
              _shorterDuration(
                _continuousTsSegmentIdleTimeout,
                deadline - attemptElapsed.elapsed,
              ),
            );
        final statusMaxAttempts = transientSustainStatus
            ? _continuousTsSustainStatusMaxAttempts
            : maxAttempts;
        final withinSustainStatusRetryBudget = attempt < statusMaxAttempts ||
            (transientSustainStatus && canRetryUsingBufferedLead());
        if (retryable && withinSustainStatusRetryBudget) {
          _transientRetryCount += 1;
          _onEvent(
            'native libvlc hls relay continuous-ts segment retry '
            'attempt=$attempt status=$_lastStatusBucket '
            'action=${forceFreshTransport ? 'retry_sustain_segment_fresh_transport' : 'retry_segment'} '
            '${summary}',
          );
          await Future<void>.delayed(attempt >= maxAttempts
              ? const Duration(seconds: 2)
              : _continuousTsSegmentRetryDelay(attempt));
          continue;
        }
        if (transientSustainStatus && retryable) {
          _onEvent(
            'native libvlc hls relay continuous-ts segment retry stopped '
            'attempts=$attempt lead=${_durationBucket(remainingLead())} '
            'reason=sustain_status_retry_budget_exhausted ${summary}',
          );
        }
        _upstreamErrorCount += 1;
        if (notifyFatalFailure) {
          _notifyContinuousTsUpstreamError();
        }
        _onEvent(
          'native libvlc hls relay continuous-ts segment rejected '
          'status=$_lastStatusBucket attempts=$attempt ${summary}',
        );
        if (notifyFatalFailure) {
          _invalidateContinuousTsRequest(requestGeneration);
        }
        return null;
      } catch (error) {
        segmentRequest?.abort(error);
        if (!_continuousTsRequestIsActive(requestGeneration)) return null;
        final reason = error is _ContinuousTsSegmentException
            ? error.reason
            : error is TimeoutException
                ? establishedLead
                    ? 'body_idle_timeout'
                    : attemptElapsed.elapsed >= deadline
                        ? 'aggregate_deadline'
                        : 'body_idle_timeout'
                : error.runtimeType.toString();
        final deadlineExpired = attemptElapsed.elapsed >= deadline ||
            reason == 'aggregate_deadline';
        final nextPlanIndex = deadlineExpired
            ? null
            : nextRequestPlanIndex(allowStrippedHeaders: false);
        if (nextPlanIndex != null) {
          requestPlanIndex = nextPlanIndex;
          forceFreshTransport = true;
          final fallbackContext = requestPlans[requestPlanIndex].context;
          _onEvent(
            'native libvlc hls relay continuous-ts segment request fallback '
            'reason=$reason '
            '${fallbackContext == 'inherited_query' ? 'query=inherited' : 'context=$fallbackContext'} '
            'stage=$requestStage '
            'received=${_byteBucket(receivedBytes)} '
            'declared=${_contentLengthBucket(declaredBytes)} ${summary}',
          );
          continue;
        }
        final retrySustainDeadline = establishedLead && deadlineExpired;
        final partialBodyStall = establishedLead &&
            receivedBytes > 0 &&
            (reason == 'aggregate_deadline' ||
                reason == 'body_idle_timeout' ||
                reason == 'content_length_mismatch');
        final emptySustainBody = establishedLead && reason == 'empty_body';
        if (partialBodyStall || emptySustainBody) {
          forceFreshTransport = true;
        }
        final retryUsingBufferedLead = canRetryUsingBufferedLead();
        if ((!deadlineExpired || retrySustainDeadline) &&
            (attempt < maxAttempts ||
                (retryUsingBufferedLead && !emptySustainBody))) {
          _transientRetryCount += 1;
          final retryAction = forceFreshTransport
              ? 'retry_sustain_segment_fresh_transport'
              : retrySustainDeadline
                  ? 'retry_sustain_segment'
                  : 'retry_segment';
          _onEvent(
            'native libvlc hls relay continuous-ts segment body retry '
            'attempt=$attempt reason=$reason stage=$requestStage '
            'received=${_byteBucket(receivedBytes)} '
            'declared=${_contentLengthBucket(declaredBytes)} '
            'action=$retryAction '
            '${summary}',
          );
          if (attempt >= maxAttempts && retryUsingBufferedLead) {
            _onEvent(
              'native libvlc hls relay continuous-ts segment held '
              'attempt=$attempt lead=${_durationBucket(remainingLead())} '
              'reason=sustain_segment_retry_using_buffer_lead ${summary}',
            );
          }
          await Future<void>.delayed(attempt >= maxAttempts
              ? const Duration(seconds: 2)
              : _continuousTsSegmentRetryDelay(attempt));
          continue;
        }
        if (emptySustainBody && attempt >= maxAttempts) {
          _onEvent(
            'native libvlc hls relay continuous-ts segment retry stopped '
            'attempts=$attempt lead=${_durationBucket(remainingLead())} '
            'reason=sustain_empty_body_retry_budget_exhausted ${summary}',
          );
        }
        _upstreamErrorCount += 1;
        _lastStatusBucket = 'io';
        if (notifyFatalFailure) {
          _notifyContinuousTsUpstreamError();
        }
        _onEvent(
          'native libvlc hls relay continuous-ts segment body rejected '
          'status=$_lastStatusBucket attempts=$attempt reason=$reason '
          'stage=$requestStage '
          'received=${_byteBucket(receivedBytes)} '
          'declared=${_contentLengthBucket(declaredBytes)} '
          "phase=${establishedLead ? 'sustain' : 'startup'} "
          '${summary}',
        );
        if (notifyFatalFailure) {
          _invalidateContinuousTsRequest(requestGeneration);
        }
        return null;
      } finally {
        freshRetryClient?.close(force: true);
      }
    }
  }

  Future<List<int>> _collectContinuousTsSegmentBytes(
    Stream<List<int>> input, {
    required Duration idleTimeout,
    required Duration wallClockTimeout,
    required int requestGeneration,
    required void Function(int byteCount) onBytes,
  }) async {
    final bytes = BytesBuilder(copy: false);
    final completer = Completer<void>();
    late final StreamSubscription<List<int>> subscription;
    Timer? wallClockTimer;
    var byteCount = 0;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) return;
      if (stackTrace == null) {
        completer.completeError(error);
      } else {
        completer.completeError(error, stackTrace);
      }
    }

    subscription = input.timeout(idleTimeout).listen(
      (chunk) {
        if (completer.isCompleted) return;
        try {
          if (!_continuousTsRequestIsActive(requestGeneration)) {
            throw const _ContinuousTsSegmentException('relay_inactive');
          }
          _onContinuousTsTransportActivity?.call();
          byteCount += chunk.length;
          onBytes(byteCount);
          if (byteCount > _continuousTsSegmentMaxBytes) {
            throw const _ContinuousTsSegmentException('segment_too_large');
          }
          bytes.add(chunk);
        } catch (error, stackTrace) {
          completeError(error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        completeError(error, stackTrace);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: false,
    );
    wallClockTimer = Timer(wallClockTimeout, () {
      completeError(
        TimeoutException(
          'continuous TS segment body exceeded its wall-clock deadline',
          wallClockTimeout,
        ),
      );
    });

    try {
      await completer.future;
      return bytes.takeBytes();
    } finally {
      wallClockTimer.cancel();
      await subscription.cancel();
    }
  }

  void _invalidateContinuousTsRequest(int requestGeneration) {
    if (requestGeneration == _continuousTsRequestGeneration) {
      _continuousTsRequestGeneration += 1;
    }
  }

  bool _continuousTsRequestIsActive(int requestGeneration) {
    return !_closed && requestGeneration == _continuousTsRequestGeneration;
  }

  static int _continuousTsStartupLeadSegmentCount(
    List<Duration> segmentDurations,
  ) {
    if (segmentDurations.isEmpty) return 0;
    var count = 0;
    var duration = Duration.zero;
    final limit = math.min(
      _continuousTsStartupLeadMaxSegments,
      segmentDurations.length,
    );
    while (count < limit) {
      duration += segmentDurations[count];
      count += 1;
      if (count >= 2 && duration >= _continuousTsStartupLeadTarget) {
        break;
      }
    }
    return count;
  }

  static Duration _continuousTsSegmentDeadline(
    Duration segmentDuration, {
    required bool establishedLead,
  }) {
    final multiplier = establishedLead ? 2.0 : 1.5;
    final baseMilliseconds = segmentDuration > Duration.zero
        ? (segmentDuration.inMilliseconds * multiplier).round()
        : const Duration(seconds: 15).inMilliseconds;
    final minimum = establishedLead
        ? const Duration(seconds: 12)
        : const Duration(seconds: 12);
    final maximum = establishedLead
        ? const Duration(seconds: 18)
        : const Duration(seconds: 12);
    return Duration(
      milliseconds: math.max(
        minimum.inMilliseconds,
        math.min(
          maximum.inMilliseconds,
          baseMilliseconds,
        ),
      ),
    );
  }

  static Duration _shorterDuration(Duration left, Duration right) {
    if (right <= Duration.zero) return const Duration(milliseconds: 1);
    return left <= right ? left : right;
  }

  static bool _isTransientContinuousTsStatus(int statusCode) {
    return statusCode == HttpStatus.requestTimeout ||
        statusCode == HttpStatus.tooManyRequests ||
        statusCode >= 500;
  }

  static Duration _continuousTsSegmentRetryDelay(int attempt) {
    return Duration(milliseconds: 180 * attempt);
  }

  _ContinuousTsPlan _trimPlanForResume(_ContinuousTsPlan plan) {
    if (_resumePosition <= Duration.zero ||
        plan.segmentUris.length < 2 ||
        plan.segmentDurations.length != plan.segmentUris.length) {
      _onTimelineOffset?.call(Duration.zero);
      return plan;
    }
    var skippedSegments = 0;
    var skippedDuration = Duration.zero;
    for (final duration in plan.segmentDurations) {
      if (duration <= Duration.zero) break;
      final nextSkipped = skippedDuration + duration;
      if (nextSkipped > _resumePosition - const Duration(seconds: 1)) break;
      skippedSegments += 1;
      skippedDuration = nextSkipped;
    }
    if (skippedSegments <= 0 || skippedSegments >= plan.segmentUris.length) {
      _onTimelineOffset?.call(Duration.zero);
      return plan;
    }
    final playbackStartSegment = math.max(
      0,
      skippedSegments - _continuousTsResumePrerollSegments,
    );
    final playbackStartOffset =
        plan.segmentDurations.take(playbackStartSegment).fold<Duration>(
              Duration.zero,
              (total, duration) => total + duration,
            );
    _onTimelineOffset?.call(playbackStartOffset);
    _onEvent(
      'native libvlc hls relay continuous-ts resume trim '
      'skippedSegments=${_countBucket(playbackStartSegment)} '
      'decoderPreroll=${_countBucket(skippedSegments - playbackStartSegment)} '
      'target=${_durationBucket(_resumePosition)} '
      'skippedDuration=${_durationBucket(playbackStartOffset)}',
    );
    return _ContinuousTsPlan(
      segmentUris: List<Uri>.unmodifiable(
        plan.segmentUris.skip(playbackStartSegment),
      ),
      segmentDurations: List<Duration>.unmodifiable(
        plan.segmentDurations.skip(playbackStartSegment),
      ),
      duration: plan.duration,
      playlistDepth: plan.playlistDepth,
      timelineOffset: playbackStartOffset,
      initializationUri: plan.initializationUri,
      isFragmentedMp4: plan.isFragmentedMp4,
    );
  }

  Future<_ContinuousTsPlan> _continuousTsPlan(
    Uri playlistUri, {
    bool forceFreshCacheBypass = false,
  }) async {
    var currentUri = playlistUri;
    final freshClient =
        forceFreshCacheBypass ? (HttpClient()..autoUncompress = false) : null;
    try {
      for (var depth = 0; depth < 3; depth += 1) {
        _onContinuousTsTransportActivity?.call();
        _onEvent(
          'native libvlc hls relay continuous-ts playlist transport active '
          'depth=$depth stage=request fresh=$forceFreshCacheBypass',
        );
        _logContinuousTsPlaylistRequestShape(currentUri, depth: depth);
        final followedResponse = await _openPlaylistResponseFollowingRedirects(
          freshClient ?? _client,
          currentUri,
          forceFreshCacheBypass: forceFreshCacheBypass,
        );
        final response = followedResponse.response;
        final effectiveCurrentUri = followedResponse.effectiveUri;
        final rootUri = _uriById['root'];
        _onEvent(
          'native libvlc hls relay continuous-ts playlist response shape '
          'depth=$depth redirects=${_countBucket(followedResponse.redirectCount)} '
          'effectiveOrigin=${rootUri != null && _sameOrigin(effectiveCurrentUri, rootUri) ? 'same_origin' : 'cross_origin'} '
          "query=${effectiveCurrentUri.query.isEmpty ? 'absent' : 'present'}",
        );
        _lastStatusBucket = _statusBucket(response.statusCode);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _upstreamErrorCount += 1;
          await response.drain<void>();
          throw const HttpException('playlist rejected');
        }
        final encodingBucket = _encodingBucket(
          response.headers.value(HttpHeaders.contentEncodingHeader),
        );
        final body = _decodePlaylist(
          await _collectBytes(response),
          encodingBucket,
        );
        _onContinuousTsTransportActivity?.call();
        _onEvent(
          'native libvlc hls relay continuous-ts playlist shape depth=$depth ${_playlistShape(body)}',
        );
        final segmentPlan = _playlistSegmentPlan(
          effectiveCurrentUri,
          body,
          queryFallbackBaseUri: currentUri,
        );
        if (currentUri.query.isNotEmpty &&
            effectiveCurrentUri.query.isEmpty &&
            _sameOrigin(currentUri, effectiveCurrentUri)) {
          _onEvent(
            'native libvlc hls relay continuous-ts playlist query context '
            'requested=true effective=false fallback=registered',
          );
        }
        if (segmentPlan.segmentUris.isEmpty) {
          return _ContinuousTsPlan(
            segmentUris: const <Uri>[],
            segmentDurations: const <Duration>[],
            duration: Duration.zero,
            playlistDepth: depth,
            timelineOffset: Duration.zero,
          );
        }
        if (_playlistLooksLikeMaster(body)) {
          final masterVariants = _masterPlaylistVariants(
            effectiveCurrentUri,
            body,
          );
          if (masterVariants.isEmpty) {
            currentUri = segmentPlan.segmentUris.first;
            _onEvent(
              'native libvlc hls relay continuous-ts master selected '
              'reason=playlist_order variants=unknown',
            );
            continue;
          }
          final selection = _selectContinuousTsMasterVariant(
            masterVariants,
            targetHeight: _continuousTsTargetHeight,
            excludedHeights: _continuousTsExcludedHeights,
          );
          currentUri = selection.variant.uri;
          _continuousTsSelectedHeight = selection.variant.height ?? 0;
          if (_continuousTsSelectedHeight > 0) {
            _onContinuousTsRenditionSelected?.call(
              _continuousTsSelectedHeight,
            );
          }
          _onEvent(
            'native libvlc hls relay continuous-ts master selected '
            'reason=${selection.reason} '
            'height=${selection.variant.height ?? 0} '
            'firstHeight=${masterVariants.first.height ?? 0} '
            'bandwidth=${_bandwidthBucket(selection.variant.bandwidth)} '
            'variants=${_countBucket(masterVariants.length)}',
          );
          continue;
        }
        return _ContinuousTsPlan(
          segmentUris: segmentPlan.segmentUris,
          segmentDurations: segmentPlan.segmentDurations,
          duration: segmentPlan.duration,
          playlistDepth: depth,
          timelineOffset: Duration.zero,
          initializationUri: segmentPlan.initializationUri,
          isFragmentedMp4: segmentPlan.isFragmentedMp4,
        );
      }
      return _ContinuousTsPlan(
        segmentUris: const <Uri>[],
        segmentDurations: const <Duration>[],
        duration: Duration.zero,
        playlistDepth: 3,
        timelineOffset: Duration.zero,
      );
    } finally {
      freshClient?.close(force: true);
    }
  }

  static List<_ContinuousTsMasterVariant> _masterPlaylistVariants(
    Uri playlistUri,
    String body,
  ) {
    final lines = body
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final variants = <_ContinuousTsMasterVariant>[];
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      String? uriLine;
      for (var nextIndex = index + 1;
          nextIndex < lines.length;
          nextIndex += 1) {
        final nextLine = lines[nextIndex];
        if (nextLine.startsWith('#')) continue;
        uriLine = nextLine;
        break;
      }
      if (uriLine == null || uriLine.isEmpty) continue;
      final resolution = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      final bandwidth =
          RegExp(r'(?:AVERAGE-)?BANDWIDTH=(\d+)').firstMatch(line);
      variants.add(
        _ContinuousTsMasterVariant(
          uri: _resolvePlaylistReference(playlistUri, uriLine),
          height: int.tryParse(resolution?.group(2) ?? ''),
          bandwidth: int.tryParse(bandwidth?.group(1) ?? ''),
        ),
      );
    }
    return variants;
  }

  static _ContinuousTsMasterSelection _selectContinuousTsMasterVariant(
    List<_ContinuousTsMasterVariant> masterVariants, {
    required int targetHeight,
    Set<int> excludedHeights = const <int>{},
  }) {
    final selectableVariants = masterVariants
        .where((variant) => !excludedHeights.contains(variant.height))
        .toList(growable: false);
    if (selectableVariants.isEmpty) {
      throw StateError('No selectable continuous-TS rendition remains.');
    }
    final atOrBelowTarget = selectableVariants
        .where(
          (variant) =>
              variant.height != null &&
              variant.height! > 0 &&
              variant.height! <= targetHeight,
        )
        .toList()
      ..sort((left, right) {
        final heightCompare = right.height!.compareTo(left.height!);
        if (heightCompare != 0) return heightCompare;
        return (right.bandwidth ?? 0).compareTo(left.bandwidth ?? 0);
      });
    if (atOrBelowTarget.isNotEmpty) {
      return _ContinuousTsMasterSelection(
        variant: atOrBelowTarget.first,
        reason: 'target_height',
      );
    }
    if (excludedHeights.isNotEmpty) {
      throw StateError(
        'No continuous-TS rendition remains at or below the recovery ceiling.',
      );
    }

    final aboveTarget = selectableVariants
        .where(
          (variant) => variant.height != null && variant.height! > targetHeight,
        )
        .toList()
      ..sort((left, right) {
        final heightCompare = left.height!.compareTo(right.height!);
        if (heightCompare != 0) return heightCompare;
        return (left.bandwidth ?? 0).compareTo(right.bandwidth ?? 0);
      });
    if (aboveTarget.isNotEmpty) {
      return _ContinuousTsMasterSelection(
        variant: aboveTarget.first,
        reason: 'target_height',
      );
    }

    final knownBandwidth = selectableVariants
        .where((variant) => (variant.bandwidth ?? 0) > 0)
        .toList()
      ..sort(
        (left, right) => left.bandwidth!.compareTo(right.bandwidth!),
      );
    if (knownBandwidth.isNotEmpty) {
      return _ContinuousTsMasterSelection(
        variant: knownBandwidth[knownBandwidth.length ~/ 2],
        reason: 'bandwidth_median',
      );
    }

    return _ContinuousTsMasterSelection(
      variant: selectableVariants.first,
      reason: 'playlist_order',
    );
  }

  static String _bandwidthBucket(int? bandwidth) {
    if (bandwidth == null || bandwidth <= 0) return 'unknown';
    if (bandwidth < 1000000) return 'under_1mbps';
    if (bandwidth < 3000000) return '1_to_3mbps';
    if (bandwidth < 6000000) return '3_to_6mbps';
    if (bandwidth < 10000000) return '6_to_10mbps';
    return '10mbps_plus';
  }

  Future<HttpClientRequest> _openUpstream(Uri upstream) async {
    return _openUpstreamWithClient(_client, upstream);
  }

  Future<HttpClientRequest> _openUpstreamWithClient(
    HttpClient client,
    Uri upstream, {
    bool forceFreshCacheBypass = false,
    bool suppressConfiguredHeaders = false,
  }) async {
    final request = await client.openUrl('GET', upstream);
    if (!suppressConfiguredHeaders &&
        (!_limitHeadersToUpstreamOrigin ||
            _sameOrigin(upstream, _uriById['root']!))) {
      for (final header in _headers.entries) {
        final name = header.key.trim();
        final value = header.value.trim();
        if (name.isEmpty || value.isEmpty) continue;
        if (name.toLowerCase() == HttpHeaders.acceptEncodingHeader) continue;
        request.headers.set(name, value);
      }
    } else if (!suppressConfiguredHeaders) {
      for (final header in _headers.entries) {
        final name = header.key.trim();
        final value = header.value.trim();
        final normalizedName = name.toLowerCase();
        if (name.isEmpty || value.isEmpty) continue;
        if (normalizedName == HttpHeaders.acceptEncodingHeader) continue;
        if (_continuousTsCrossOriginSafeHeaders.contains(normalizedName)) {
          request.headers.set(name, value);
        }
      }
    }
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    _applySessionCookies(upstream, request);
    if (forceFreshCacheBypass) {
      request.persistentConnection = false;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set('Pragma', 'no-cache');
    }
    return request;
  }

  Future<_FollowedPlaylistResponse> _openPlaylistResponseFollowingRedirects(
    HttpClient client,
    Uri upstream, {
    bool forceFreshCacheBypass = false,
  }) async {
    var currentUri = upstream;
    const maxRedirects = 5;
    for (var redirectCount = 0;
        redirectCount <= maxRedirects;
        redirectCount += 1) {
      final request = await _openUpstreamWithClient(
        client,
        currentUri,
        forceFreshCacheBypass: forceFreshCacheBypass,
      );
      request.followRedirects = false;
      final response = await request.close();
      _captureSessionCookies(currentUri, response.cookies);
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (!_isFollowableRedirect(response.statusCode) ||
          location == null ||
          location.trim().isEmpty) {
        return _FollowedPlaylistResponse(
          response: response,
          effectiveUri: currentUri,
          redirectCount: redirectCount,
        );
      }
      if (redirectCount >= maxRedirects) {
        await response.drain<void>();
        throw const HttpException('playlist redirect limit exceeded');
      }
      final redirectedUri = currentUri.resolve(location.trim());
      await response.drain<void>();
      currentUri = redirectedUri;
    }
    throw const HttpException('playlist redirect limit exceeded');
  }

  static bool _isFollowableRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  bool _shouldTryCrossOriginHeaderlessFallback(Uri upstream) {
    final rootUri = _uriById['root'];
    if (!_limitHeadersToUpstreamOrigin ||
        rootUri == null ||
        _sameOrigin(upstream, rootUri)) {
      return false;
    }
    return _headers.entries.any((header) {
      final name = header.key.trim().toLowerCase();
      return header.value.trim().isNotEmpty &&
          _continuousTsCrossOriginSafeHeaders.contains(name);
    });
  }

  void _logContinuousTsSegmentRequestShape(
    _ContinuousTsSegmentRequestPlan plan, {
    required bool establishedLead,
    required bool queryFallbackAvailable,
  }) {
    final rootUri = _uriById['root'];
    final rootOrigin = rootUri != null && _sameOrigin(plan.uri, rootUri)
        ? 'same_origin'
        : 'cross_origin';
    final configuredHeaders = _configuredHeaderCount();
    final safeHeaders = _safeConfiguredHeaderCount();
    final cookieCount = _matchingSessionCookieCount(plan.uri);
    final shape = '${establishedLead ? 'sustain' : 'startup'}|${plan.context}|'
        '$rootOrigin|${plan.uri.query.isEmpty}|$queryFallbackAvailable|'
        '$configuredHeaders|$safeHeaders|$cookieCount';
    if (!_continuousTsRequestShapesLogged.add(shape)) return;
    _onEvent(
      'native libvlc hls relay continuous-ts segment request shape '
      "phase=${establishedLead ? 'sustain' : 'startup'} "
      'context=${plan.context} '
      'rootOrigin=$rootOrigin '
      "query=${plan.uri.query.isEmpty ? 'absent' : 'present'} "
      'queryFallback=${queryFallbackAvailable ? 'available' : 'unavailable'} '
      'configuredHeaders=$configuredHeaders '
      'safeHeaders=$safeHeaders cookies=$cookieCount',
    );
  }

  void _logContinuousTsPlaylistRequestShape(Uri uri, {required int depth}) {
    final rootUri = _uriById['root'];
    _onEvent(
      'native libvlc hls relay continuous-ts playlist request shape '
      'depth=$depth '
      'rootOrigin=${rootUri != null && _sameOrigin(uri, rootUri) ? 'same_origin' : 'cross_origin'} '
      "query=${uri.query.isEmpty ? 'absent' : 'present'} "
      'configuredHeaders=${_configuredHeaderCount()} '
      'safeHeaders=${_safeConfiguredHeaderCount()} '
      'cookies=${_matchingSessionCookieCount(uri)}',
    );
  }

  int _configuredHeaderCount() {
    return _headers.entries.where((header) {
      final name = header.key.trim().toLowerCase();
      return name.isNotEmpty &&
          header.value.trim().isNotEmpty &&
          name != HttpHeaders.acceptEncodingHeader;
    }).length;
  }

  int _safeConfiguredHeaderCount() {
    return _headers.entries.where((header) {
      final name = header.key.trim().toLowerCase();
      return name.isNotEmpty &&
          header.value.trim().isNotEmpty &&
          name != HttpHeaders.acceptEncodingHeader &&
          _continuousTsCrossOriginSafeHeaders.contains(name);
    }).length;
  }

  int _matchingSessionCookieCount(Uri uri) {
    final now = DateTime.now().toUtc();
    return _sessionCookies
        .where(
          (cookie) => !cookie.isExpiredAt(now) && cookie.matches(uri),
        )
        .length;
  }

  void _captureSessionCookies(Uri responseUri, List<Cookie> cookies) {
    final now = DateTime.now().toUtc();
    _sessionCookies.removeWhere((cookie) => cookie.isExpiredAt(now));
    for (final cookie in cookies) {
      final name = cookie.name.trim();
      if (name.isEmpty) continue;
      final domain = _normalizedCookieDomain(
        cookie.domain?.trim().isNotEmpty == true
            ? cookie.domain!
            : responseUri.host,
      );
      if (!_cookieDomainMatches(responseUri.host, domain)) continue;
      final path = _normalizedCookiePath(
        cookie.path,
        responseUri.path,
      );
      _sessionCookies.removeWhere(
        (existing) =>
            existing.name == name &&
            existing.domain == domain &&
            existing.path == path,
      );
      if (cookie.value.isEmpty ||
          cookie.maxAge == 0 ||
          (cookie.expires?.toUtc().isBefore(now) ?? false)) {
        continue;
      }
      _sessionCookies.add(
        _RelaySessionCookie(
          name: name,
          value: cookie.value,
          domain: domain,
          path: path,
          secure: cookie.secure,
          expires: cookie.expires?.toUtc(),
          hostOnly: cookie.domain?.trim().isNotEmpty != true,
        ),
      );
    }
  }

  void _applySessionCookies(Uri upstream, HttpClientRequest request) {
    final now = DateTime.now().toUtc();
    _sessionCookies.removeWhere((cookie) => cookie.isExpiredAt(now));
    for (final cookie in _sessionCookies) {
      if (!cookie.matches(upstream)) continue;
      request.cookies.add(Cookie(cookie.name, cookie.value));
    }
  }

  static String _normalizedCookieDomain(String domain) {
    final normalized = domain.trim().toLowerCase();
    return normalized.startsWith('.') ? normalized.substring(1) : normalized;
  }

  static bool _cookieDomainMatches(String host, String domain) {
    final normalizedHost = host.toLowerCase();
    return normalizedHost == domain || normalizedHost.endsWith('.$domain');
  }

  static String _normalizedCookiePath(String? cookiePath, String responsePath) {
    final explicit = cookiePath?.trim();
    if (explicit != null && explicit.startsWith('/')) return explicit;
    if (!responsePath.startsWith('/') || responsePath == '/') return '/';
    final lastSlash = responsePath.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : responsePath.substring(0, lastSlash);
  }

  String _rewritePlaylist(Uri baseUri, String body) {
    final lines =
        body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    return lines.map((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return line;
      if (trimmed.startsWith('#')) {
        return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
          final raw = match.group(1);
          if (raw == null || raw.trim().isEmpty || _isDataUri(raw)) {
            return match.group(0)!;
          }
          return 'URI="${_localPathFor(_resolvePlaylistReference(baseUri, raw))}"';
        });
      }
      return _localPathFor(_resolvePlaylistReference(baseUri, trimmed));
    }).join('\n');
  }

  String _localPathFor(Uri upstream) {
    final id = 'r${_nextId++}';
    _uriById[id] = upstream;
    final extension = _localExtensionFor(upstream.path);
    if (extension == 'm3u8') _playlistIds.add(id);
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _server.port,
      pathSegments: <String>['juicr-libvlc-hls', _token, '$id.$extension'],
    ).toString();
  }

  static bool _isDataUri(String value) {
    return value.trimLeft().toLowerCase().startsWith('data:');
  }

  static bool _pathLooksLikePlaylist(String path) {
    return path.toLowerCase().contains('.m3u8');
  }

  static bool _playlistLooksLikeMaster(String body) {
    return body.contains('#EXT-X-STREAM-INF');
  }

  static bool _sameOrigin(Uri left, Uri right) {
    return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
        left.host.toLowerCase() == right.host.toLowerCase() &&
        left.port == right.port;
  }

  static Uri _effectiveResponseUri(
    Uri requestedUri,
    List<RedirectInfo> redirects,
  ) {
    var effectiveUri = requestedUri;
    for (final redirect in redirects) {
      effectiveUri = effectiveUri.resolveUri(redirect.location);
    }
    return effectiveUri;
  }

  static Uri _resolvePlaylistReference(Uri baseUri, String reference) {
    final resolved = baseUri.resolve(reference.trim());
    if (baseUri.query.isEmpty ||
        resolved.query.isNotEmpty ||
        !_sameOrigin(baseUri, resolved)) {
      return resolved;
    }
    return resolved.replace(query: baseUri.query);
  }

  _ContinuousTsSegmentPlan _playlistSegmentPlan(
    Uri baseUri,
    String body, {
    Uri? queryFallbackBaseUri,
  }) {
    final output = <Uri>[];
    final durations = <Duration>[];
    final lines =
        body.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    var totalDurationMs = 0;
    double? pendingSegmentSeconds;
    Uri? initializationUri;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#EXT-X-MAP:')) {
        final match = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
        final reference = match?.group(1)?.trim();
        if (reference != null && reference.isNotEmpty) {
          initializationUri = _resolveContinuousTsSegmentReference(
            baseUri,
            reference,
            queryFallbackBaseUri: queryFallbackBaseUri,
          );
        }
        continue;
      }
      if (trimmed.startsWith('#EXTINF:')) {
        pendingSegmentSeconds = _parseExtInfSeconds(trimmed);
        continue;
      }
      if (trimmed.startsWith('#')) continue;
      if (_isDataUri(trimmed)) continue;
      output.add(
        _resolveContinuousTsSegmentReference(
          baseUri,
          trimmed,
          queryFallbackBaseUri: queryFallbackBaseUri,
        ),
      );
      if (pendingSegmentSeconds != null && pendingSegmentSeconds > 0) {
        final segmentDurationMs = (pendingSegmentSeconds * 1000).round();
        totalDurationMs += segmentDurationMs;
        durations.add(Duration(milliseconds: segmentDurationMs));
      } else {
        durations.add(Duration.zero);
      }
      pendingSegmentSeconds = null;
    }
    return _ContinuousTsSegmentPlan(
      segmentUris: List<Uri>.unmodifiable(output),
      segmentDurations: List<Duration>.unmodifiable(durations),
      duration: Duration(milliseconds: totalDurationMs),
      initializationUri: initializationUri,
      isFragmentedMp4: initializationUri != null,
    );
  }

  Uri _resolveContinuousTsSegmentReference(
    Uri baseUri,
    String reference, {
    Uri? queryFallbackBaseUri,
  }) {
    final canonical = baseUri.resolve(reference.trim());
    final querySource = baseUri.query.isNotEmpty
        ? baseUri
        : queryFallbackBaseUri != null &&
                queryFallbackBaseUri.query.isNotEmpty &&
                _sameOrigin(queryFallbackBaseUri, canonical)
            ? queryFallbackBaseUri
            : null;
    if (querySource == null ||
        canonical.query.isNotEmpty ||
        !_sameOrigin(querySource, canonical)) {
      return canonical;
    }
    final inheritedQuery = canonical.replace(query: querySource.query);
    if (inheritedQuery != canonical) {
      _continuousTsSegmentQueryFallbacks[canonical] = inheritedQuery;
    }
    return canonical;
  }

  static double? _parseExtInfSeconds(String line) {
    final value = line.substring('#EXTINF:'.length).split(',').first.trim();
    if (value.isEmpty) return null;
    return double.tryParse(value);
  }

  static String _localExtensionFor(String path) {
    final normalized = path.toLowerCase();
    if (normalized.contains('.m3u8')) return 'm3u8';
    for (final extension in <String>[
      'ts',
      'm4s',
      'mp4',
      'm4v',
      'aac',
      'mp3',
      'vtt',
    ]) {
      if (normalized.endsWith('.$extension')) return extension;
    }
    return 'ts';
  }

  static String _extensionBucket(String path) {
    final extension = _localExtensionFor(path);
    if (extension == 'm3u8') return 'playlist';
    return extension;
  }

  Future<int> _pipeMediaResponse(
    Stream<List<int>> input,
    HttpResponse output, {
    required String contentTypeBucket,
    required bool normalizeTs,
    void Function(int streamedBytes)? onBytes,
  }) async {
    var sawFirstChunk = false;
    var streamedBytes = 0;
    var lastReportedBytes = 0;
    await for (final chunk in input) {
      if (!sawFirstChunk) {
        sawFirstChunk = true;
        final trimmedChunk = normalizeTs ? _trimToMpegTsSync(chunk) : chunk;
        _onEvent(
          'native libvlc hls relay media proof contentType=$contentTypeBucket '
          'magic=${_magicBucket(chunk)} normalized=${trimmedChunk.length != chunk.length} '
          'bytes=${_byteBucket(trimmedChunk.length)}',
        );
        if (trimmedChunk.isEmpty) continue;
        output.add(trimmedChunk);
        streamedBytes += trimmedChunk.length;
        if (streamedBytes - lastReportedBytes >= 64 * 1024) {
          lastReportedBytes = streamedBytes;
          onBytes?.call(streamedBytes);
        }
        continue;
      }
      output.add(chunk);
      streamedBytes += chunk.length;
      if (streamedBytes - lastReportedBytes >= 64 * 1024) {
        lastReportedBytes = streamedBytes;
        onBytes?.call(streamedBytes);
      }
    }
    if (!sawFirstChunk) {
      _onEvent(
        'native libvlc hls relay media proof contentType=$contentTypeBucket magic=empty bytes=0',
      );
    }
    if (streamedBytes != lastReportedBytes) {
      onBytes?.call(streamedBytes);
    }
    return streamedBytes;
  }

  static String _decodePlaylist(List<int> bytes, String encodingBucket) {
    if (encodingBucket == 'gzip') {
      return utf8.decode(gzip.decode(bytes), allowMalformed: true);
    }
    if (encodingBucket == 'deflate') {
      return utf8.decode(zlib.decode(bytes), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _redactRelayEvent(String message, String token) {
    var redacted = message
        .replaceAll(RegExp(r'https?://[^\s"]+'), '[hidden-url]')
        .replaceAll(RegExp(r'127\.0\.0\.1[^\s"]*'), '[localhost-hidden]')
        .replaceAll(RegExp(r'localhost[^\s"]*'), '[localhost-hidden]');
    if (token.isNotEmpty) {
      redacted = redacted.replaceAll(token, '[redacted-token]');
    }
    return redacted;
  }

  static String _playlistShape(String body) {
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    var variantCount = 0;
    var mediaCount = 0;
    var keyCount = 0;
    var mapCount = 0;
    var byteRangeCount = 0;
    var discontinuityCount = 0;
    var uriLineCount = 0;
    var endList = false;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-STREAM-INF')) variantCount += 1;
      if (line.startsWith('#EXT-X-MEDIA:')) mediaCount += 1;
      if (line.startsWith('#EXT-X-KEY')) keyCount += 1;
      if (line.startsWith('#EXT-X-MAP')) mapCount += 1;
      if (line.startsWith('#EXT-X-BYTERANGE')) byteRangeCount += 1;
      if (line == '#EXT-X-DISCONTINUITY') discontinuityCount += 1;
      if (line == '#EXT-X-ENDLIST') endList = true;
      if (!line.startsWith('#')) uriLineCount += 1;
    }
    return 'lines=${lines.length} variants=$variantCount mediaTags=$mediaCount '
        'keys=$keyCount maps=$mapCount byteRanges=$byteRangeCount '
        'discontinuities=$discontinuityCount '
        'uriLines=$uriLineCount endList=$endList';
  }

  static String _statusBucket(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return '2xx';
    if (statusCode >= 300 && statusCode < 400) return '3xx';
    if (statusCode == 401 || statusCode == 403) return 'auth';
    if (statusCode == 404) return 'not_found';
    if (statusCode >= 400 && statusCode < 500) return '4xx';
    if (statusCode >= 500 && statusCode < 600) return '5xx';
    return 'other';
  }

  static String _contentTypeBucket(ContentType? contentType) {
    final value = contentType?.mimeType.toLowerCase();
    if (value == null || value.isEmpty) return 'missing';
    if (value.contains('video')) return 'video';
    if (value.contains('mpegurl')) return 'playlist';
    if (value.contains('mp2t') || value.contains('mpeg')) return 'mpeg';
    if (value.contains('octet-stream')) return 'binary';
    if (value.contains('text') || value.contains('html')) return 'text';
    return 'other';
  }

  static ContentType? _relayMediaContentType(
    ContentType? upstreamContentType,
    String extensionBucket,
  ) {
    if (extensionBucket == 'ts') {
      return ContentType('video', 'mp2t');
    }
    if (extensionBucket == 'm4s' ||
        extensionBucket == 'mp4' ||
        extensionBucket == 'm4v') {
      return ContentType('video', 'mp4');
    }
    if (extensionBucket == 'aac') return ContentType('audio', 'aac');
    if (extensionBucket == 'mp3') return ContentType('audio', 'mpeg');
    if (extensionBucket == 'vtt') return ContentType('text', 'vtt');
    return upstreamContentType;
  }

  static String _magicBucket(List<int> bytes) {
    if (bytes.isEmpty) return 'empty';
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return 'gzip';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33) {
      return 'id3';
    }
    if (bytes[0] == 0x47) return 'mpeg_ts';
    final tsOffset = _mpegTsSyncOffset(bytes);
    if (tsOffset != null) return 'mpeg_ts_offset_${_offsetBucket(tsOffset)}';
    if (bytes.length >= 12) {
      final box = String.fromCharCodes(bytes.skip(4).take(4)).toLowerCase();
      if (box == 'ftyp' || box == 'styp' || box == 'moof') return 'mp4_box';
    }
    final prefix = utf8
        .decode(
          bytes.take(math.min(bytes.length, 32)).toList(growable: false),
          allowMalformed: true,
        )
        .trimLeft()
        .toLowerCase();
    if (prefix.startsWith('<!doctype') || prefix.startsWith('<html')) {
      return 'html';
    }
    if (prefix.startsWith('#extm3u')) return 'playlist';
    if (prefix.startsWith('{') || prefix.startsWith('[')) return 'json';
    return 'unknown';
  }

  static int? _mpegTsSyncOffset(List<int> bytes) {
    final searchLimit = math.min(bytes.length, 188);
    for (var offset = 1; offset < searchLimit; offset += 1) {
      if (bytes[offset] != 0x47) continue;
      final next = offset + 188;
      if (next < bytes.length && bytes[next] == 0x47) return offset;
      if (next >= bytes.length) return offset;
    }
    return null;
  }

  static List<int> _trimToMpegTsSync(List<int> bytes) {
    if (bytes.isEmpty || bytes[0] == 0x47) return bytes;
    final offset = _mpegTsSyncOffset(bytes);
    if (offset == null || offset <= 0 || offset >= bytes.length) return bytes;
    return bytes.sublist(offset);
  }

  static String _offsetBucket(int offset) {
    if (offset < 16) return 'under_16';
    if (offset < 64) return '16_to_63';
    return '64_to_187';
  }

  static String _byteBucket(int length) {
    if (length <= 0) return '0';
    if (length < 1024) return 'under_1kb';
    if (length < 16384) return '1_to_15kb';
    if (length < 65536) return '16_to_63kb';
    if (length < 262144) return '64_to_255kb';
    if (length < 1048576) return '256kb_to_1mb';
    if (length < 4194304) return '1_to_4mb';
    return '4mb_plus';
  }

  static String _contentLengthBucket(int length) {
    if (length < 0) return 'unknown';
    return _byteBucket(length);
  }

  static String _countBucket(int count) {
    if (count <= 0) return '0';
    if (count == 1) return '1';
    if (count < 5) return '2_to_4';
    if (count < 25) return '5_to_24';
    if (count < 100) return '25_to_99';
    if (count < 500) return '100_to_499';
    return '500_plus';
  }

  static String _durationBucket(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes <= 0) return 'unknown';
    if (minutes < 30) return 'under_30m';
    if (minutes < 60) return '30_to_59m';
    if (minutes < 120) return '60_to_119m';
    if (minutes < 180) return '120_to_179m';
    return '180m_plus';
  }

  static String _encodingBucket(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty || normalized == 'identity') {
      return 'identity';
    }
    if (normalized.contains('gzip')) return 'gzip';
    if (normalized.contains('deflate')) return 'deflate';
    if (normalized.contains('br')) return 'br';
    return 'other';
  }

  static Future<List<int>> _collectBytes(Stream<List<int>> stream) async {
    final output = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      output.add(chunk);
    }
    return output.takeBytes();
  }

  static Future<List<int>> _collectBoundedPreflightBytes(
    Stream<List<int>> stream,
  ) async {
    final output = BytesBuilder(copy: false);
    var receivedBytes = 0;
    await for (final chunk in stream) {
      receivedBytes += chunk.length;
      if (receivedBytes > _continuousTsSegmentMaxBytes) {
        throw const _HlsPreflightSegmentTooLarge();
      }
      output.add(chunk);
    }
    return output.takeBytes();
  }

  static Future<void> _closeWith(HttpResponse response, int statusCode) async {
    response.statusCode = statusCode;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await response.close();
  }

  static String _randomToken() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(18, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _FollowedPlaylistResponse {
  const _FollowedPlaylistResponse({
    required this.response,
    required this.effectiveUri,
    required this.redirectCount,
  });

  final HttpClientResponse response;
  final Uri effectiveUri;
  final int redirectCount;
}

class _RelaySessionCookie {
  const _RelaySessionCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.secure,
    required this.expires,
    required this.hostOnly,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final DateTime? expires;
  final bool hostOnly;

  bool isExpiredAt(DateTime now) => expires?.isBefore(now) ?? false;

  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final domainMatches = hostOnly
        ? host == domain
        : LibVlcHlsRelay._cookieDomainMatches(host, domain);
    if (!domainMatches) return false;
    if (secure && uri.scheme.toLowerCase() != 'https') return false;
    final requestPath = uri.path.isEmpty ? '/' : uri.path;
    return requestPath == path ||
        requestPath.startsWith(path.endsWith('/') ? path : '$path/');
  }
}

class _ContinuousTsPlan {
  const _ContinuousTsPlan({
    required this.segmentUris,
    required this.segmentDurations,
    required this.duration,
    required this.playlistDepth,
    required this.timelineOffset,
    this.initializationUri,
    this.isFragmentedMp4 = false,
  });

  final List<Uri> segmentUris;
  final List<Duration> segmentDurations;
  final Duration duration;
  final int playlistDepth;
  final Duration timelineOffset;
  final Uri? initializationUri;
  final bool isFragmentedMp4;
}

class _ContinuousTsSegmentPlan {
  const _ContinuousTsSegmentPlan({
    required this.segmentUris,
    required this.segmentDurations,
    required this.duration,
    this.initializationUri,
    this.isFragmentedMp4 = false,
  });

  final List<Uri> segmentUris;
  final List<Duration> segmentDurations;
  final Duration duration;
  final Uri? initializationUri;
  final bool isFragmentedMp4;
}

class _ContinuousTsSegmentRequestPlan {
  const _ContinuousTsSegmentRequestPlan({
    required this.uri,
    required this.context,
    this.suppressConfiguredHeaders = false,
    this.useFreshTransport = false,
  });

  final Uri uri;
  final String context;
  final bool suppressConfiguredHeaders;
  final bool useFreshTransport;
}

class _ContinuousTsSegmentRequestPreference {
  const _ContinuousTsSegmentRequestPreference({
    required this.context,
    required this.suppressConfiguredHeaders,
  });

  final String context;
  final bool suppressConfiguredHeaders;

  @override
  bool operator ==(Object other) {
    return other is _ContinuousTsSegmentRequestPreference &&
        other.context == context &&
        other.suppressConfiguredHeaders == suppressConfiguredHeaders;
  }

  @override
  int get hashCode => Object.hash(context, suppressConfiguredHeaders);
}

class _HlsPreflightChildResponse {
  const _HlsPreflightChildResponse({
    required this.readable,
    required this.requestUri,
    required this.effectiveUri,
    this.body,
    this.mediaBytes,
    this.contentTypeBucket = 'unknown',
  });

  final bool readable;
  final Uri requestUri;
  final Uri effectiveUri;
  final String? body;
  final List<int>? mediaBytes;
  final String contentTypeBucket;
}

class _HlsPreflightSegmentCacheEntry {
  const _HlsPreflightSegmentCacheEntry({
    required this.bytes,
    required this.contentTypeBucket,
    required this.expiresAt,
  });

  final Uint8List bytes;
  final String contentTypeBucket;
  final DateTime expiresAt;
}

class _HlsPreflightSegmentTooLarge implements Exception {
  const _HlsPreflightSegmentTooLarge();
}

class _TvSequentialSegment {
  const _TvSequentialSegment._({
    required this.bytes,
    required this.contentTypeBucket,
    required this.nestedPlan,
    required this.isInitialization,
  });

  const _TvSequentialSegment.media({
    required List<int> bytes,
    required String contentTypeBucket,
  }) : this._(
          bytes: bytes,
          contentTypeBucket: contentTypeBucket,
          nestedPlan: null,
          isInitialization: false,
        );

  const _TvSequentialSegment.initialization({
    required List<int> bytes,
    required String contentTypeBucket,
  }) : this._(
          bytes: bytes,
          contentTypeBucket: contentTypeBucket,
          nestedPlan: null,
          isInitialization: true,
        );

  const _TvSequentialSegment.playlist(_ContinuousTsSegmentPlan nestedPlan)
      : this._(
          bytes: const <int>[],
          contentTypeBucket: 'playlist',
          nestedPlan: nestedPlan,
          isInitialization: false,
        );

  final List<int> bytes;
  final String contentTypeBucket;
  final _ContinuousTsSegmentPlan? nestedPlan;
  final bool isInitialization;
}

class _ContinuousTsSegmentPayload {
  const _ContinuousTsSegmentPayload({
    required this.bytes,
    required this.contentTypeBucket,
    required this.magicBucket,
    required this.normalized,
  });

  final List<int> bytes;
  final String contentTypeBucket;
  final String magicBucket;
  final bool normalized;
}

class _ContinuousTsMasterVariant {
  const _ContinuousTsMasterVariant({
    required this.uri,
    required this.height,
    required this.bandwidth,
  });

  final Uri uri;
  final int? height;
  final int? bandwidth;
}

class _ContinuousTsMasterSelection {
  const _ContinuousTsMasterSelection({
    required this.variant,
    required this.reason,
  });

  final _ContinuousTsMasterVariant variant;
  final String reason;
}

class _ContinuousTsSegmentException implements Exception {
  const _ContinuousTsSegmentException(this.reason);

  final String reason;

  @override
  String toString() => '_ContinuousTsSegmentException($reason)';
}
