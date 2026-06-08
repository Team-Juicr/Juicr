import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class LibVlcHlsRelay {
  LibVlcHlsRelay._({
    required this.localUri,
    required HttpServer server,
    required HttpClient client,
    required Map<String, Uri> uriById,
    required Set<String> playlistIds,
    required Map<String, String> headers,
    required Duration resumePosition,
    required String token,
    required bool continuousTsMode,
    required void Function(Duration duration)? onDuration,
    required void Function(int streamedSegments)? onContinuousTsProgress,
    required void Function(int streamedBytes)? onContinuousTsBytes,
    required void Function(String message) onEvent,
  }) : _server = server,
       _client = client,
       _uriById = uriById,
       _playlistIds = playlistIds,
       _headers = headers,
       _resumePosition = resumePosition,
       _token = token,
       _continuousTsMode = continuousTsMode,
       _onDuration = onDuration,
       _onContinuousTsProgress = onContinuousTsProgress,
       _onContinuousTsBytes = onContinuousTsBytes,
       _onEvent = ((message) => onEvent(_redactRelayEvent(message, token))) {
    _subscription = _server.listen(_handleRequest);
  }

  static Future<LibVlcHlsRelay> start({
    required Uri upstreamUri,
    required Map<String, String> headers,
    required Duration resumePosition,
    bool continuousTsMode = false,
    void Function(Duration duration)? onDuration,
    void Function(int streamedSegments)? onContinuousTsProgress,
    void Function(int streamedBytes)? onContinuousTsBytes,
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
      resumePosition: resumePosition,
      token: token,
      continuousTsMode: continuousTsMode,
      onDuration: onDuration,
      onContinuousTsProgress: onContinuousTsProgress,
      onContinuousTsBytes: onContinuousTsBytes,
      onEvent: onEvent,
    );
  }

  final Uri localUri;
  final HttpServer _server;
  final HttpClient _client;
  final Map<String, Uri> _uriById;
  final Set<String> _playlistIds;
  final Map<String, String> _headers;
  final Duration _resumePosition;
  final String _token;
  final bool _continuousTsMode;
  final void Function(Duration duration)? _onDuration;
  final void Function(int streamedSegments)? _onContinuousTsProgress;
  final void Function(int streamedBytes)? _onContinuousTsBytes;
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
  var _lastStatusBucket = 'none';

  String get summary =>
      'requests=$_requestCount playlists=$_playlistCount media=$_mediaCount '
      'heads=$_headCount ranges=$_rangeCount ignoredRanges=$_ignoredRangeCount '
      'notFound=$_notFoundCount upstreamErrors=$_upstreamErrorCount '
      'lastStatus=$_lastStatusBucket';

  Future<void> stop() async {
    if (_closed) return;
    _closed = true;
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
      _onEvent('native libvlc hls relay request failed stage=open $summary');
      await _closeWith(request.response, HttpStatus.badGateway);
      return;
    }

    try {
      final upstreamResponse = await upstreamRequest.close();
      final contentType = upstreamResponse.headers.contentType;
      final encodingBucket = _encodingBucket(
        upstreamResponse.headers.value(HttpHeaders.contentEncodingHeader),
      );
      final looksLikePlaylist =
          knownPlaylistRequest ||
          _pathLooksLikePlaylist(upstream.path) ||
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
          'extension=${looksLikePlaylist ? 'm3u8' : _extensionBucket(upstream.path)} $summary',
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
          'status=$_lastStatusBucket $summary',
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
        var playlistBaseUri = upstream;
        var body = _decodePlaylist(bytes, encodingBucket);
        _onEvent(
          'native libvlc hls relay playlist shape ${_playlistShape(body)}',
        );
        if (!_continuousTsMode && id == 'root') {
          final flattened = await _flattenRootMasterPlaylist(upstream, body);
          if (flattened != null) {
            playlistBaseUri = flattened.baseUri;
            body = flattened.body;
          }
        }
        final rewritten = _rewritePlaylist(playlistBaseUri, body);
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
        'native libvlc hls relay request failed stage=response error=${error.runtimeType} $summary',
      );
      try {
        await _closeWith(request.response, HttpStatus.badGateway);
      } catch (_) {}
      }
  }

  Future<_RelayPlaylistBody?> _flattenRootMasterPlaylist(
    Uri baseUri,
    String body,
  ) async {
    if (!_playlistLooksLikeMaster(body)) return null;
    final variantUri = _firstVariantUri(baseUri, body);
    if (variantUri == null) return null;
    HttpClientResponse? response;
    try {
      final request = await _openUpstream(variantUri);
      response = await request.close();
      _lastStatusBucket = _statusBucket(response.statusCode);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        _onEvent(
          'native libvlc hls relay root flatten rejected status=$_lastStatusBucket $summary',
        );
        return null;
      }
      final encodingBucket = _encodingBucket(
        response.headers.value(HttpHeaders.contentEncodingHeader),
      );
      final flattenedBody = _decodePlaylist(
        await _collectBytes(response),
        encodingBucket,
      );
      _onEvent(
        'native libvlc hls relay root flattened ${_playlistShape(flattenedBody)}',
      );
      return _RelayPlaylistBody(baseUri: variantUri, body: flattenedBody);
    } catch (error) {
      _upstreamErrorCount += 1;
      _onEvent(
        'native libvlc hls relay root flatten failed error=${error.runtimeType} $summary',
      );
      try {
        await response?.drain<void>();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _handleContinuousTsRequest(
    HttpRequest request,
    Uri playlistUri,
  ) async {
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
    var rejectedSegments = 0;
    try {
      final plan = _trimPlanForResume(await _continuousTsPlan(playlistUri));
      if (plan.segmentUris.isEmpty) {
        _upstreamErrorCount += 1;
        _onEvent(
          'native libvlc hls relay continuous-ts rejected reason=no_segments $summary',
        );
        await request.response.close();
        return;
      }
      if (plan.duration > Duration.zero) {
        _onDuration?.call(plan.duration);
      }
      _onEvent(
        'native libvlc hls relay continuous-ts start segments=${_countBucket(plan.segmentUris.length)} '
        'playlistDepth=${plan.playlistDepth} duration=${_durationBucket(plan.duration)} $summary',
      );
      final segmentQueue = List<Uri>.of(plan.segmentUris);
      while (segmentQueue.isNotEmpty) {
        if (_closed) break;
        final segmentUri = segmentQueue.removeAt(0);
        streamedSegments += 1;
        final segmentRequest = await _openUpstream(segmentUri);
        final segmentResponse = await segmentRequest.close();
        _lastStatusBucket = _statusBucket(segmentResponse.statusCode);
        if (segmentResponse.statusCode < 200 ||
            segmentResponse.statusCode >= 300) {
          _upstreamErrorCount += 1;
          rejectedSegments += 1;
          _onEvent(
            'native libvlc hls relay continuous-ts segment rejected status=$_lastStatusBucket '
            'streamed=${_countBucket(streamedSegments)} '
            'rejected=${_countBucket(rejectedSegments)} $summary',
          );
          await segmentResponse.drain<void>();
          if (rejectedSegments >= 12) break;
          continue;
        }
        rejectedSegments = 0;
        final segmentContentType = segmentResponse.headers.contentType;
        if (_contentTypeBucket(segmentContentType) == 'playlist') {
          final encodingBucket = _encodingBucket(
            segmentResponse.headers.value(HttpHeaders.contentEncodingHeader),
          );
          final body = _decodePlaylist(
            await _collectBytes(segmentResponse),
            encodingBucket,
          );
          final nestedPlan = _playlistSegmentPlan(segmentUri, body);
          _onEvent(
            'native libvlc hls relay continuous-ts segment playlist expanded '
            'children=${_countBucket(nestedPlan.segmentUris.length)} '
            '${_playlistShape(body)}',
          );
          if (nestedPlan.segmentUris.isEmpty) {
            _upstreamErrorCount += 1;
            rejectedSegments += 1;
            if (rejectedSegments >= 12) break;
            continue;
          }
          segmentQueue.insertAll(0, nestedPlan.segmentUris);
          continue;
        }
        _mediaCount += 1;
        streamedBytes += await _pipeMediaResponse(
          segmentResponse,
          request.response,
          contentTypeBucket: _contentTypeBucket(
            segmentResponse.headers.contentType,
          ),
          normalizeTs: true,
        );
        _onContinuousTsBytes?.call(streamedBytes);
        if (streamedSegments == 1 || streamedSegments % 20 == 0) {
          _onContinuousTsProgress?.call(streamedSegments);
          _onEvent(
            'native libvlc hls relay continuous-ts progress streamed=${_countBucket(streamedSegments)} '
            'bytes=${_byteBucket(streamedBytes)} $summary',
          );
        }
      }
      _onEvent(
        'native libvlc hls relay continuous-ts finished streamed=${_countBucket(streamedSegments)} $summary',
      );
      await request.response.close();
    } catch (error) {
      if (_closed) {
        _onEvent(
          'native libvlc hls relay continuous-ts stopped reason=relay_closed streamed=${_countBucket(streamedSegments)} $summary',
        );
        try {
          await request.response.close();
        } catch (_) {}
        return;
      }
      _upstreamErrorCount += 1;
      _onEvent(
        'native libvlc hls relay continuous-ts failed error=${error.runtimeType} $summary',
      );
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  _ContinuousTsPlan _trimPlanForResume(_ContinuousTsPlan plan) {
    if (_resumePosition <= Duration.zero ||
        plan.segmentUris.length < 2 ||
        plan.segmentDurations.length != plan.segmentUris.length) {
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
      return plan;
    }
    _onEvent(
      'native libvlc hls relay continuous-ts resume trim '
      'skippedSegments=${_countBucket(skippedSegments)} '
      'target=${_durationBucket(_resumePosition)} '
      'skippedDuration=${_durationBucket(skippedDuration)}',
    );
    return _ContinuousTsPlan(
      segmentUris: List<Uri>.unmodifiable(
        plan.segmentUris.skip(skippedSegments),
      ),
      segmentDurations: List<Duration>.unmodifiable(
        plan.segmentDurations.skip(skippedSegments),
      ),
      duration: plan.duration,
      playlistDepth: plan.playlistDepth,
    );
  }

  Future<_ContinuousTsPlan> _continuousTsPlan(Uri playlistUri) async {
    var currentUri = playlistUri;
    for (var depth = 0; depth < 3; depth += 1) {
      final request = await _openUpstream(currentUri);
      final response = await request.close();
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
      _onEvent(
        'native libvlc hls relay continuous-ts playlist shape depth=$depth ${_playlistShape(body)}',
      );
      final segmentPlan = _playlistSegmentPlan(currentUri, body);
      if (segmentPlan.segmentUris.isEmpty) {
        return _ContinuousTsPlan(
          segmentUris: const <Uri>[],
          segmentDurations: const <Duration>[],
          duration: Duration.zero,
          playlistDepth: depth,
        );
      }
      if (_playlistLooksLikeMaster(body)) {
        currentUri = segmentPlan.segmentUris.first;
        continue;
      }
      final nestedPlaylist = await _firstNestedPlaylistUri(segmentPlan);
      if (nestedPlaylist != null) {
        currentUri = nestedPlaylist;
        continue;
      }
      final liveTail = _tailWindowForRollingPlaylist(segmentPlan);
      return _ContinuousTsPlan(
        segmentUris: liveTail.segmentUris,
        segmentDurations: liveTail.segmentDurations,
        duration: segmentPlan.duration,
        playlistDepth: depth,
      );
    }
    return const _ContinuousTsPlan(
      segmentUris: <Uri>[],
      segmentDurations: <Duration>[],
      duration: Duration(),
      playlistDepth: 3,
    );
  }

  Future<Uri?> _firstNestedPlaylistUri(
    _ContinuousTsSegmentPlan segmentPlan,
  ) async {
    if (segmentPlan.segmentUris.isEmpty) return null;
    final candidate = segmentPlan.segmentUris.first;
    HttpClientResponse? response;
    try {
      final request = await _openUpstream(candidate);
      response = await request.close();
      _lastStatusBucket = _statusBucket(response.statusCode);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        return null;
      }
      final contentType = response.headers.contentType;
      final bytes = await _collectBytes(response);
      final looksLikePlaylist =
          (contentType?.mimeType.toLowerCase().contains('mpegurl') ?? false) ||
          _magicBucket(bytes) == 'playlist';
      if (!looksLikePlaylist) return null;
      _onEvent(
        'native libvlc hls relay continuous-ts nested playlist detected '
        'contentType=${_contentTypeBucket(contentType)} '
        'magic=${_magicBucket(bytes)}',
      );
      return candidate;
    } catch (_) {
      try {
        await response?.drain<void>();
      } catch (_) {}
      return null;
    }
  }

  _ContinuousTsSegmentPlan _tailWindowForRollingPlaylist(
    _ContinuousTsSegmentPlan plan,
  ) {
    if (plan.segmentUris.length <= 80) return plan;
    return _ContinuousTsSegmentPlan(
      segmentUris: List<Uri>.unmodifiable(
        plan.segmentUris.skip(plan.segmentUris.length - 80),
      ),
      segmentDurations: List<Duration>.unmodifiable(
        plan.segmentDurations.length == plan.segmentUris.length
            ? plan.segmentDurations.skip(plan.segmentDurations.length - 80)
            : const <Duration>[],
      ),
      duration: plan.duration,
    );
  }

  Future<HttpClientRequest> _openUpstream(Uri upstream) async {
    final request = await _client.openUrl('GET', upstream);
    for (final header in _headers.entries) {
      final name = header.key.trim();
      final value = header.value.trim();
      if (name.isEmpty || value.isEmpty) continue;
      if (name.toLowerCase() == HttpHeaders.acceptEncodingHeader) continue;
      request.headers.set(name, value);
    }
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    return request;
  }

  String _rewritePlaylist(Uri baseUri, String body) {
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    return lines
        .map((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return line;
          if (trimmed.startsWith('#')) {
            final safeLine = _streamInfoWithBandwidth(line);
            return safeLine.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
              final raw = match.group(1);
              if (raw == null || raw.trim().isEmpty || _isDataUri(raw)) {
                return match.group(0)!;
              }
              return 'URI="${_localPathFor(baseUri.resolve(raw))}"';
            });
          }
          return _localPathFor(baseUri.resolve(trimmed));
        })
        .join('\n');
  }

  static String _streamInfoWithBandwidth(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#EXT-X-STREAM-INF') ||
        RegExp(r'(^|,)BANDWIDTH=\d+', caseSensitive: false).hasMatch(line)) {
      return line;
    }
    final height = int.tryParse(
      RegExp(
            r'RESOLUTION=\d+x(\d+)',
            caseSensitive: false,
          ).firstMatch(line)?.group(1) ??
          '',
    );
    final bandwidth = switch (height ?? 0) {
      >= 2160 => 16000000,
      >= 1440 => 9000000,
      >= 1080 => 5500000,
      >= 720 => 2800000,
      >= 480 => 1400000,
      _ => 800000,
    };
    return '$line,BANDWIDTH=$bandwidth';
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

  static Uri? _firstVariantUri(Uri baseUri, String body) {
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    var expectsVariantUri = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#EXT-X-STREAM-INF')) {
        expectsVariantUri = true;
        continue;
      }
      if (trimmed.startsWith('#')) continue;
      if (expectsVariantUri) return baseUri.resolve(trimmed);
    }
    return null;
  }

  static _ContinuousTsSegmentPlan _playlistSegmentPlan(
    Uri baseUri,
    String body,
  ) {
    final output = <Uri>[];
    final durations = <Duration>[];
    final lines = body
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    var totalDurationMs = 0;
    double? pendingSegmentSeconds;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#EXTINF:')) {
        pendingSegmentSeconds = _parseExtInfSeconds(trimmed);
        continue;
      }
      if (trimmed.startsWith('#')) continue;
      if (_isDataUri(trimmed)) continue;
      output.add(baseUri.resolve(trimmed));
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
    );
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
  }) async {
    var sawFirstChunk = false;
    var streamedBytes = 0;
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
        continue;
      }
      output.add(chunk);
      streamedBytes += chunk.length;
    }
    if (!sawFirstChunk) {
      _onEvent(
        'native libvlc hls relay media proof contentType=$contentTypeBucket magic=empty bytes=0',
      );
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
    var uriLineCount = 0;
    var endList = false;
    for (final line in lines) {
      if (line.startsWith('#EXT-X-STREAM-INF')) variantCount += 1;
      if (line.startsWith('#EXT-X-MEDIA:')) mediaCount += 1;
      if (line.startsWith('#EXT-X-KEY')) keyCount += 1;
      if (line.startsWith('#EXT-X-MAP')) mapCount += 1;
      if (line.startsWith('#EXT-X-BYTERANGE')) byteRangeCount += 1;
      if (line == '#EXT-X-ENDLIST') endList = true;
      if (!line.startsWith('#')) uriLineCount += 1;
    }
    return 'lines=${lines.length} variants=$variantCount mediaTags=$mediaCount '
        'keys=$keyCount maps=$mapCount byteRanges=$byteRangeCount '
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
    return '64kb_plus';
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

class _ContinuousTsPlan {
  const _ContinuousTsPlan({
    required this.segmentUris,
    required this.segmentDurations,
    required this.duration,
    required this.playlistDepth,
  });

  final List<Uri> segmentUris;
  final List<Duration> segmentDurations;
  final Duration duration;
  final int playlistDepth;
}

class _ContinuousTsSegmentPlan {
  const _ContinuousTsSegmentPlan({
    required this.segmentUris,
    required this.segmentDurations,
    required this.duration,
  });

  final List<Uri> segmentUris;
  final List<Duration> segmentDurations;
  final Duration duration;
}

class _RelayPlaylistBody {
  const _RelayPlaylistBody({required this.baseUri, required this.body});

  final Uri baseUri;
  final String body;
}
