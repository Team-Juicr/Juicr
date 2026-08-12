import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/libvlc_hls_relay.dart';

void main() {
  test('relative media resolves from the final redirected playlist URI',
      () async {
    final events = <String>[];
    late HttpServer upstream;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/start.m3u8') {
        request.response.redirect(
          Uri.parse(
            'http://${upstream.address.host}:${upstream.port}'
            '/session/index.m3u8',
          ),
        );
        return;
      }
      if (request.uri.path == '/session/index.m3u8') {
        await _writePlaylist(request.response);
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.host}:${upstream.port}/start.m3u8',
      ),
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchFirstMedia(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
  });

  test('cross-origin playlist redirect reapplies only safe playback headers',
      () async {
    final events = <String>[];
    late HttpServer redirectServer;
    late HttpServer playlistServer;
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/session/index.m3u8') {
        final hasSafeContext =
            request.headers.value(HttpHeaders.refererHeader) ==
                    'https://playback.example/' &&
                request.headers.value('origin') == 'https://playback.example';
        final leakedAuthorization =
            request.headers.value(HttpHeaders.authorizationHeader) != null;
        if (hasSafeContext && !leakedAuthorization) {
          await _writePlaylist(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    redirectServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirectServer.listen((request) async {
      if (request.uri.path == '/start.m3u8') {
        request.response.redirect(
          Uri.parse(
            'http://${playlistServer.address.host}:${playlistServer.port}'
            '/session/index.m3u8',
          ),
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${redirectServer.address.host}:${redirectServer.port}'
        '/start.m3u8',
      ),
      headers: const <String, String>{
        HttpHeaders.refererHeader: 'https://playback.example/',
        'Origin': 'https://playback.example',
        HttpHeaders.authorizationHeader: 'private-token',
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await redirectServer.close(force: true);
      await playlistServer.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
  });

  test('playlist redirect session cookie reaches the redirected playlist',
      () async {
    final events = <String>[];
    late HttpServer redirectServer;
    late HttpServer playlistServer;
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/session/index.m3u8') {
        final hasSessionCookie = request.cookies.any(
          (cookie) =>
              cookie.name == 'playback_session' && cookie.value == 'abc',
        );
        if (hasSessionCookie) {
          await _writePlaylist(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    redirectServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    redirectServer.listen((request) async {
      if (request.uri.path == '/start.m3u8') {
        request.response.cookies.add(
          Cookie('playback_session', 'abc')..path = '/session',
        );
        request.response.redirect(
          Uri.parse(
            'http://${playlistServer.address.host}:${playlistServer.port}'
            '/session/index.m3u8',
          ),
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${redirectServer.address.host}:${redirectServer.port}'
        '/start.m3u8',
      ),
      headers: const <String, String>{},
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await redirectServer.close(force: true);
      await playlistServer.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
  });

  test('relative media uses canonical URI before playlist query fallback',
      () async {
    final events = <String>[];
    final observedQueries = <String>[];
    late HttpServer upstream;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/session/index.m3u8') {
        await _writePlaylist(request.response);
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        observedQueries.add(request.uri.query);
      }
      if (request.uri.path == '/session/segment.ts' &&
          request.uri.query.isEmpty) {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.host}:${upstream.port}'
        '/session/index.m3u8?session=abc',
      ),
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(observedQueries, <String>['']);
  });

  test('relative media can fall back to same-origin playlist session query',
      () async {
    final events = <String>[];
    final observedQueries = <String>[];
    late HttpServer upstream;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/session/index.m3u8') {
        await _writePlaylist(request.response);
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        observedQueries.add(request.uri.query);
      }
      if (request.uri.path == '/session/segment.ts' &&
          request.uri.queryParameters['session'] == 'abc') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.host}:${upstream.port}'
        '/session/index.m3u8?session=abc',
      ),
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(observedQueries, <String>['', 'session=abc']);
  });

  test('redirected playlist retains its same-origin request query fallback',
      () async {
    final events = <String>[];
    final observedQueries = <String>[];
    late HttpServer upstream;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/start.m3u8') {
        request.response.redirect(
          Uri.parse(
            'http://${upstream.address.host}:${upstream.port}'
            '/session/index.m3u8',
          ),
        );
        return;
      }
      if (request.uri.path == '/session/index.m3u8') {
        await _writePlaylist(request.response);
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        observedQueries.add(request.uri.query);
      }
      if (request.uri.path == '/session/segment.ts' &&
          request.uri.queryParameters['session'] == 'abc') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.host}:${upstream.port}'
        '/start.m3u8?session=abc',
      ),
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(observedQueries, <String>['', 'session=abc']);
  });

  test('playlist session cookies are forwarded to media requests', () async {
    final events = <String>[];
    late HttpServer upstream;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      if (request.uri.path == '/session/index.m3u8') {
        request.response.cookies.add(
          Cookie('playback_session', 'abc')
            ..path = '/session'
            ..httpOnly = true,
        );
        await _writePlaylist(request.response);
        return;
      }
      final hasSessionCookie = request.cookies.any(
        (cookie) => cookie.name == 'playback_session' && cookie.value == 'abc',
      );
      if (request.uri.path == '/session/segment.ts' && hasSessionCookie) {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.host}:${upstream.port}'
        '/session/index.m3u8',
      ),
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchFirstMedia(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
  });

  test('cross-origin media retries without safe headers when rejected',
      () async {
    final events = <String>[];
    final observedReferers = <String?>[];
    late HttpServer playlistServer;
    late HttpServer mediaServer;
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      if (request.uri.path != '/segment.ts') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final referer = request.headers.value(HttpHeaders.refererHeader);
      observedReferers.add(referer);
      if (referer == null) {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:6\n'
          '#EXTINF:6.0,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${playlistServer.address.host}:${playlistServer.port}'
        '/index.m3u8',
      ),
      headers: const <String, String>{
        HttpHeaders.refererHeader: 'https://playback.example/',
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await playlistServer.close(force: true);
      await mediaServer.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(
      observedReferers,
      <String?>['https://playback.example/', null],
    );
    expect(
      events,
      contains(
        contains(
          'segment request fallback reason=status context=stripped_headers',
        ),
      ),
    );
  });

  test('cross-origin media keeps safe playback headers when required',
      () async {
    final events = <String>[];
    final observedReferers = <String?>[];
    late HttpServer playlistServer;
    late HttpServer mediaServer;
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      if (request.uri.path != '/segment.ts') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final referer = request.headers.value(HttpHeaders.refererHeader);
      observedReferers.add(referer);
      if (referer == 'https://playback.example/') {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
    });
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:6\n'
          '#EXTINF:6.0,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${playlistServer.address.host}:${playlistServer.port}'
        '/index.m3u8',
      ),
      headers: const <String, String>{
        HttpHeaders.refererHeader: 'https://playback.example/',
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await playlistServer.close(force: true);
      await mediaServer.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(observedReferers, <String?>['https://playback.example/']);
  });

  test('startup retries a fresh transport without cross-origin headers',
      () async {
    final events = <String>[];
    final observedReferers = <String?>[];
    int? rejectedPort;
    late HttpServer playlistServer;
    late HttpServer mediaServer;
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      if (request.uri.path != '/segment.ts') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final remotePort = request.connectionInfo?.remotePort;
      final referer = request.headers.value(HttpHeaders.refererHeader);
      observedReferers.add(referer);
      rejectedPort ??= remotePort;
      if (remotePort != rejectedPort && referer == null) {
        await _writeTransportStream(request.response);
        return;
      }
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:6\n'
          '#EXTINF:6.0,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${playlistServer.address.host}:${playlistServer.port}'
        '/index.m3u8',
      ),
      headers: const <String, String>{
        HttpHeaders.refererHeader: 'https://playback.example/',
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await playlistServer.close(force: true);
      await mediaServer.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty);
    expect(mediaBytes.first, 0x47);
    expect(observedReferers, contains(null));
    expect(
      events.join('\n'),
      contains('context=fresh_transport_stripped_headers'),
    );
  });

  test('segment request diagnostics expose only redacted request shape',
      () async {
    final events = <String>[];
    late HttpServer playlistServer;
    late HttpServer mediaServer;
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistServer.listen((request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:6\n'
          '#EXTINF:6.0,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}'
          '/segment.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    const secretHeaderValue = 'private-header-value';
    const secretQueryValue = 'private-query-value';
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${playlistServer.address.host}:${playlistServer.port}'
        '/index.m3u8?session=$secretQueryValue',
      ),
      headers: const <String, String>{
        HttpHeaders.refererHeader: 'https://playback.example/',
        HttpHeaders.authorizationHeader: secretHeaderValue,
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await playlistServer.close(force: true);
      await mediaServer.close(force: true);
    });

    await _fetchContinuousTs(relay.localUri, events);

    expect(
      events,
      contains(
        contains(
          'playlist request shape depth=0 rootOrigin=same_origin '
          'query=present configuredHeaders=2 safeHeaders=1 cookies=0',
        ),
      ),
    );
    expect(
      events,
      contains(
        contains(
          'playlist response shape depth=0 redirects=0 '
          'effectiveOrigin=same_origin query=present',
        ),
      ),
    );
    expect(
      events,
      contains(
        contains(
          'segment request shape phase=startup context=canonical '
          'rootOrigin=cross_origin query=absent queryFallback=unavailable '
          'configuredHeaders=2 safeHeaders=1 cookies=0',
        ),
      ),
    );
    expect(events.join('\n'), isNot(contains(secretHeaderValue)));
    expect(events.join('\n'), isNot(contains(secretQueryValue)));
    expect(events.join('\n'), isNot(contains('/segment.ts')));
  });

  test(
    'continuous TS startup skips a slow-drip incomplete segment',
    () async {
      final events = <String>[];
      final slowResponseDone = Completer<void>();
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:1\n'
            '#EXTINF:1,\n'
            'slow.ts\n'
            '#EXTINF:1,\n'
            'segment1.ts\n'
            '#EXTINF:1,\n'
            'segment2.ts\n'
            '#EXTINF:1,\n'
            'segment3.ts\n'
            '#EXT-X-ENDLIST\n',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/slow.ts') {
          request.response.headers.contentType = ContentType('video', 'mp2t');
          try {
            while (!slowResponseDone.isCompleted) {
              request.response.add(_transportStreamBytes(packetCount: 500));
              await request.response.flush();
              await Future.any<void>(<Future<void>>[
                Future<void>.delayed(const Duration(seconds: 4)),
                slowResponseDone.future,
              ]);
            }
          } catch (_) {
          } finally {
            try {
              await request.response.close();
            } catch (_) {}
          }
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        slowResponseDone.complete();
        await relay.stop();
        await upstream.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(relay.localUri)).close();
      final mediaBytes = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.ok);
      expect(mediaBytes, isNotEmpty);
      expect(mediaBytes.first, 0x47);
      expect(
        events,
        contains(
          contains('reason=startup_segment_skipped'),
        ),
      );
      expect(
        events,
        contains(
          contains('startup lead ready'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 25)),
  );

  test(
    'continuous TS startup leaves a bad segment neighborhood before the player watchdog',
    () async {
      final events = <String>[];
      final slowResponseDone = Completer<void>();
      var failedSegmentRequests = 0;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:30\n'
            '#EXTINF:30,\n'
            'failed.ts\n'
            '#EXTINF:30,\n'
            'slow.ts\n'
            '#EXTINF:30,\n'
            'segment1.ts\n'
            '#EXTINF:30,\n'
            'segment2.ts\n'
            '#EXT-X-ENDLIST\n',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path == '/failed.ts') {
          failedSegmentRequests += 1;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.uri.path == '/slow.ts') {
          request.response.headers.contentType = ContentType('video', 'mp2t');
          try {
            while (!slowResponseDone.isCompleted) {
              request.response.add(_transportStreamBytes(packetCount: 500));
              await request.response.flush();
              await Future.any<void>(<Future<void>>[
                Future<void>.delayed(const Duration(seconds: 4)),
                slowResponseDone.future,
              ]);
            }
          } catch (_) {
          } finally {
            try {
              await request.response.close();
            } catch (_) {}
          }
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        slowResponseDone.complete();
        await relay.stop();
        await upstream.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(relay.localUri)).close();
      final mediaBytes = await response.expand((chunk) => chunk).toList();

      expect(response.statusCode, HttpStatus.ok);
      expect(mediaBytes, isNotEmpty);
      expect(mediaBytes.first, 0x47);
      expect(failedSegmentRequests, 1);
      expect(
        events,
        contains(
          contains('startup lead ready'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'continuous TS startup survives three failed segments before healthy media',
    () async {
      final events = <String>[];
      var failedSegmentRequests = 0;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:30\n'
            '#EXTINF:30,\n'
            'failed0.ts\n'
            '#EXTINF:30,\n'
            'failed1.ts\n'
            '#EXTINF:30,\n'
            'failed2.ts\n'
            '#EXTINF:30,\n'
            'segment0.ts\n'
            '#EXTINF:30,\n'
            'segment1.ts\n'
            '#EXT-X-ENDLIST\n',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/failed')) {
          failedSegmentRequests += 1;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes, isNotEmpty);
      expect(mediaBytes.first, 0x47);
      expect(failedSegmentRequests, 3);
      expect(
        events,
        contains(
          contains('startup lead ready'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'continuous TS rejects a permanent startup gap before exposing partial media',
    () async {
      final events = <String>[];
      var failedSegmentRequests = 0;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n'
            '#EXTINF:10,\n'
            'segment0.ts\n',
          );
          for (var index = 0; index < 11; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('failed$index.ts');
          }
          playlist
            ..writeln('#EXTINF:10,')
            ..writeln('segment1.ts')
            ..writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/failed')) {
          failedSegmentRequests += 1;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes, isEmpty);
      expect(failedSegmentRequests, 6);
      expect(
        events.join('\n'),
        contains('reason=startup_segment_skipped'),
      );
      expect(
        events.join('\n'),
        isNot(contains('segment request shape phase=sustain')),
      );
      expect(
        events.join('\n'),
        contains('reason=startup_segment_failure_limit'),
      );
      expect(
        events,
        isNot(
          contains(
            contains('continuous-ts finished streamed=2_to_4'),
          ),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'continuous TS sustain rotates capped keep-alive transports',
    () async {
      final events = <String>[];
      final requestsByPort = <int, int>{};
      var freshTransportRequests = 0;
      late HttpServer mediaServer;
      mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mediaServer.listen((request) async {
        final port = request.connectionInfo?.remotePort ?? -1;
        final requestCount = (requestsByPort[port] ?? 0) + 1;
        requestsByPort[port] = requestCount;
        if (requestCount > 12) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (requestsByPort.length > 1) freshTransportRequests += 1;
        await _writeTransportStream(request.response);
      });

      late HttpServer playlistServer;
      playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      playlistServer.listen((request) async {
        if (request.uri.path != '/index.m3u8') {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        final playlist = StringBuffer(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:10\n',
        );
        for (var index = 0; index < 13; index += 1) {
          playlist
            ..writeln('#EXTINF:10,')
            ..writeln(
              'http://${mediaServer.address.host}:${mediaServer.port}/segment$index.ts',
            );
        }
        playlist.writeln('#EXT-X-ENDLIST');
        request.response.write(playlist);
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${playlistServer.address.host}:${playlistServer.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await playlistServer.close(force: true);
        await mediaServer.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes.length, 13 * _transportStreamBytes().length);
      expect(freshTransportRequests, greaterThan(0));
      expect(requestsByPort.length, greaterThanOrEqualTo(2));
      expect(
        events.join('\n'),
        contains('context=fresh_transport'),
      );
      expect(
        events.join('\n'),
        contains('transport rotated'),
      );
      expect(
        events.join('\n'),
        isNot(contains('segment_failure_limit')),
      );
    },
    timeout: const Timeout(Duration(seconds: 18)),
  );

  test(
    'continuous TS remembers a successful fresh transport for later segments',
    () async {
      final events = <String>[];
      var cacheBypassRequests = 0;
      late HttpServer mediaServer;
      mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mediaServer.listen((request) async {
        final cacheBypass =
            request.headers.value(HttpHeaders.cacheControlHeader) == 'no-cache';
        if (!cacheBypass) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        cacheBypassRequests += 1;
        await _writeTransportStream(request.response);
      });

      late HttpServer playlistServer;
      playlistServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      playlistServer.listen((request) async {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:30\n'
          '#EXTINF:30,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}/segment0.ts\n'
          '#EXTINF:30,\n'
          'http://${mediaServer.address.host}:${mediaServer.port}/segment1.ts\n'
          '#EXT-X-ENDLIST\n',
        );
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${playlistServer.address.host}:${playlistServer.port}/index.m3u8',
        ),
        headers: const <String, String>{
          'Referer': 'https://media.invalid/',
        },
        limitHeadersToUpstreamOrigin: true,
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await playlistServer.close(force: true);
        await mediaServer.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);
      final canonicalRequests = events.where(
        (event) =>
            event.contains(
              'segment request shape phase=',
            ) &&
            event.contains(
              'context=canonical',
            ),
      );

      expect(mediaBytes.length, 2 * _transportStreamBytes().length);
      expect(cacheBypassRequests, 2);
      expect(
        canonicalRequests,
        hasLength(1),
        reason: events.join('\n'),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS sustain pauses at a bounded lead until playback advances',
    () async {
      final events = <String>[];
      var requestedSegments = 0;
      var playbackPosition = Duration.zero;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 20; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('segment$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          requestedSegments += 1;
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        currentPlaybackPosition: () => playbackPosition,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(relay.localUri)).close();
      final mediaFuture = response.expand((chunk) => chunk).toList();

      await _waitForCondition(
        () => requestedSegments >= 9,
        timeout: const Duration(seconds: 3),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requestedSegments, lessThan(20));
      expect(
        events.join('\n'),
        contains('continuous-ts lead held'),
      );

      final heldRequestCount = requestedSegments;
      playbackPosition = const Duration(seconds: 59);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(requestedSegments, heldRequestCount);
      expect(
        events.join('\n'),
        isNot(contains('continuous-ts lead released')),
      );

      playbackPosition = const Duration(seconds: 60);
      await _waitForCondition(
        () => requestedSegments > heldRequestCount,
        timeout: const Duration(seconds: 2),
      );
      expect(
        events.join('\n'),
        contains('continuous-ts lead released lead=120s resume=120s'),
      );

      playbackPosition = const Duration(seconds: 200);
      final mediaBytes = await mediaFuture.timeout(const Duration(seconds: 3));

      expect(mediaBytes.length, 20 * _transportStreamBytes().length);
      expect(requestedSegments, 20);
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS startup proof waits for two minutes of contiguous media',
    () async {
      final events = <String>[];
      var requestedSegments = 0;
      var startupLeadReadyAtSegment = 0;
      var firstMediaByteAtSegment = 0;
      var firstRelayByteAtSegment = 0;
      final releaseRemainingSegments = Completer<void>();
      addTearDown(() {
        if (!releaseRemainingSegments.isCompleted) {
          releaseRemainingSegments.complete();
        }
      });
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 14; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('segment$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          requestedSegments += 1;
          if (requestedSegments > 1) {
            await releaseRemainingSegments.future;
          }
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onContinuousTsBytes: (bytes) {
          if (bytes > 0 && firstRelayByteAtSegment == 0) {
            firstRelayByteAtSegment = requestedSegments;
          }
        },
        onContinuousTsStartupLeadReady: () {
          startupLeadReadyAtSegment = requestedSegments;
        },
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final responseFuture = (await client.getUrl(relay.localUri)).close();

      await _waitForCondition(
        () => requestedSegments >= 2,
        timeout: const Duration(seconds: 3),
      );
      expect(
        firstRelayByteAtSegment,
        0,
        reason: 'the relay must retain startup media until the complete '
            'lead is ready',
      );
      releaseRemainingSegments.complete();
      final response = await responseFuture;
      expect(response.statusCode, HttpStatus.ok);
      final mediaBytes = <int>[];
      final mediaDone = Completer<void>();
      response.listen((chunk) {
        if (firstMediaByteAtSegment == 0 && chunk.isNotEmpty) {
          firstMediaByteAtSegment = requestedSegments;
        }
        mediaBytes.addAll(chunk);
      }, onDone: mediaDone.complete);
      await mediaDone.future;

      expect(mediaBytes.length, 14 * _transportStreamBytes().length);
      expect(firstRelayByteAtSegment, greaterThanOrEqualTo(12));
      expect(startupLeadReadyAtSegment, greaterThanOrEqualTo(12));
      expect(
        firstMediaByteAtSegment,
        greaterThanOrEqualTo(12),
        reason: 'libVLC must not receive partial startup media before the '
            '120-second lead is ready',
      );
      expect(
        events.join('\n'),
        contains('duration=120s'),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS sustain absorbs a multi-attempt transient segment gap',
    () async {
      final events = <String>[];
      var middleSegmentRequests = 0;
      var upstreamErrorSignals = 0;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 16; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('segment$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path == '/segment13.ts') {
          middleSegmentRequests += 1;
          if (middleSegmentRequests <= 5) {
            request.response.statusCode = HttpStatus.serviceUnavailable;
            await request.response.close();
            return;
          }
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onContinuousTsUpstreamError: (_, __) {
          upstreamErrorSignals += 1;
        },
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes.length, 16 * _transportStreamBytes().length);
      expect(middleSegmentRequests, 6);
      expect(upstreamErrorSignals, 0);
      expect(
        events.join('\n'),
        contains('reason=sustain_segment_retry_bounded'),
      );
      expect(
        events.join('\n'),
        isNot(contains('reason=sustain_segment_gap_requires_recovery')),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS sustain rejects a missing segment before emitting a timestamp gap',
    () async {
      final events = <String>[];
      var middleSegmentRequests = 0;
      var upstreamErrorSignals = 0;
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 16; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('segment$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path == '/segment13.ts') {
          middleSegmentRequests += 1;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        if (request.uri.path.startsWith('/segment')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onContinuousTsUpstreamError: (_, __) {
          upstreamErrorSignals += 1;
        },
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes.length, 13 * _transportStreamBytes().length);
      expect(middleSegmentRequests, 10);
      expect(upstreamErrorSignals, 1);
      expect(
        events.join('\n'),
        contains('reason=sustain_segment_retry_bounded'),
      );
      expect(events.join('\n'), contains('round=4'));
      expect(
        events.join('\n'),
        contains('reason=sustain_segment_gap_requires_recovery'),
      );
      expect(
        events.join('\n'),
        isNot(contains('reason=sustain_segment_skipped')),
      );
      expect(
        events.join('\n'),
        isNot(contains('reason=sustain_segment_failure_limit')),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS near-end resume accepts the complete remaining VOD window',
    () async {
      final events = <String>[];
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 10; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('segment$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('.ts')) {
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(_transportStreamBytes());
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: const Duration(seconds: 80),
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes, isNotEmpty);
      expect(events, contains(contains('startup lead ready')));
      expect(
        events.join('\n'),
        isNot(contains('reason=startup_lead_unavailable')),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test(
    'continuous TS startup bounds repeated slow 5xx segment rejection',
    () async {
      final events = <String>[];
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/index.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          final playlist = StringBuffer(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n',
          );
          for (var index = 0; index < 20; index += 1) {
            playlist
              ..writeln('#EXTINF:10,')
              ..writeln('failed$index.ts');
          }
          playlist.writeln('#EXT-X-ENDLIST');
          request.response.write(playlist);
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('.ts')) {
          await Future<void>.delayed(const Duration(seconds: 2));
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/index.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final stopwatch = Stopwatch()..start();
      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);
      stopwatch.stop();

      expect(mediaBytes, isEmpty);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 16)));
      expect(
        events,
        contains(
          contains('reason=startup_segment_failure_limit'),
        ),
      );
      expect(
        events,
        contains(
          contains('reason=startup_lead_unavailable'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 28)),
  );

  test(
    'adaptive downshift never selects a rendition above its recovery ceiling',
    () async {
      final events = <String>[];
      late HttpServer upstream;
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        if (request.uri.path == '/master.m3u8') {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x358\n'
            '358/index.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2200000,RESOLUTION=1280x714\n'
            '714/index.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=4500000,RESOLUTION=1920x1072\n'
            '1072/index.m3u8\n',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('/index.m3u8')) {
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
            charset: 'utf-8',
          );
          request.response.write(
            '#EXTM3U\n'
            '#EXT-X-TARGETDURATION:10\n'
            '#EXTINF:10,\n'
            'segment1.ts\n'
            '#EXTINF:10,\n'
            'segment2.ts\n'
            '#EXTINF:10,\n'
            'segment3.ts\n'
            '#EXT-X-ENDLIST\n',
          );
          await request.response.close();
          return;
        }
        if (request.uri.path.endsWith('.ts')) {
          await _writeTransportStream(request.response);
          return;
        }
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });

      final relay = await LibVlcHlsRelay.start(
        upstreamUri: Uri.parse(
          'http://${upstream.address.host}:${upstream.port}/master.m3u8',
        ),
        headers: const <String, String>{},
        resumePosition: Duration.zero,
        continuousTsMode: true,
        continuousTsTargetHeight: 357,
        continuousTsExcludedHeights: const <int>{358, 714},
        onEvent: events.add,
      );
      addTearDown(() async {
        await relay.stop();
        await upstream.close(force: true);
      });

      final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

      expect(mediaBytes, isEmpty);
      expect(
        events,
        isNot(
          contains(
            contains('master selected reason=target_height height=1072'),
          ),
        ),
      );
      expect(
        events,
        contains(
          contains('continuous-ts failed error=StateError'),
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 12)),
  );

  test('HLS preflight rejects a readable playlist with a dead media segment',
      () async {
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:6\n'
        '#EXTINF:6,\n'
        'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
        '#EXT-X-ENDLIST\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody,
      headers: const <String, String>{'Referer': 'https://media.invalid/'},
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isFalse);
  });

  test('HLS preflight accepts a readable playlist and media segment', () async {
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.contentType = ContentType('video', 'mp2t');
      request.response.add(_transportStreamBytes(packetCount: 1));
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:6\n'
        '#EXTINF:6,\n'
        'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
        '#EXT-X-ENDLIST\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody,
      headers: const <String, String>{'Referer': 'https://media.invalid/'},
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isTrue);
  });

  test('HLS preflight tries a relative segment without playlist query first',
      () async {
    final observedQueries = <String>[];
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      observedQueries.add(request.uri.query);
      if (request.uri.query.isNotEmpty) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('video', 'mp2t')
        ..add(_transportStreamBytes(packetCount: 1));
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse(
      'http://${mediaServer.address.host}:${mediaServer.port}'
      '/index.m3u8?session=abc',
    );
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:6\n'
        '#EXTINF:6,\n'
        'segment.ts\n'
        '#EXT-X-ENDLIST\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isTrue);
    expect(observedQueries, isNotEmpty);
    expect(observedQueries.first, isEmpty);
  });

  test('HLS preflight falls back when canonical segment body is not MPEG-TS',
      () async {
    final observedQueries = <String>[];
    final events = <String>[];
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      observedQueries.add(request.uri.query);
      request.response.statusCode = HttpStatus.ok;
      if (request.uri.queryParameters['session'] == 'abc') {
        request.response
          ..headers.contentType = ContentType('video', 'mp2t')
          ..add(_transportStreamBytes(packetCount: 1));
      } else {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<html>temporary gate</html>');
      }
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse(
      'http://${mediaServer.address.host}:${mediaServer.port}'
      '/index.m3u8?session=abc',
    );
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:6\n'
        '#EXTINF:6,\n'
        'segment.ts\n'
        '#EXT-X-ENDLIST\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 2),
      onEvent: events.add,
    );

    expect(readable, isTrue);
    expect(observedQueries, containsAllInOrder(<String>['', 'session=abc']));
    expect(
      events,
      contains(
        contains(
          'segment result context=canonical headers=configured '
          'status=ok body=unreadable',
        ),
      ),
    );
    expect(
      events,
      contains(
        contains(
          'segment result context=inherited_query headers=configured '
          'status=ok body=readable',
        ),
      ),
    );
  });

  test('HLS preflight rejects a segment that starts but does not complete',
      () async {
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      if (request.headers.value(HttpHeaders.rangeHeader) != null) {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..add(const <int>[0x47, 0x00]);
        await request.response.close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('video', 'mp2t')
        ..add(_transportStreamBytes(packetCount: 1));
      await request.response.flush();
      await Future<void>.delayed(const Duration(seconds: 1));
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:6\n'
        '#EXTINF:6,\n'
        'http://${mediaServer.address.host}:${mediaServer.port}/segment.ts\n'
        '#EXT-X-ENDLIST\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody,
      headers: const <String, String>{},
      timeout: const Duration(milliseconds: 200),
    );

    expect(readable, isNull);
  });

  test('HLS preflight probes the same master rendition as continuous TS relay',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/low.m3u8':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType =
                ContentType('application', 'vnd.apple.mpegurl')
            ..write(
              '#EXTM3U\n'
              '#EXT-X-TARGETDURATION:6\n'
              '#EXTINF:6,\n'
              'low.ts\n'
              '#EXT-X-ENDLIST\n',
            );
        case '/target.m3u8':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType =
                ContentType('application', 'vnd.apple.mpegurl')
            ..write(
              '#EXTM3U\n'
              '#EXT-X-TARGETDURATION:6\n'
              '#EXTINF:6,\n'
              'target.ts\n'
              '#EXT-X-ENDLIST\n',
            );
        case '/low.ts':
          request.response
            ..statusCode = HttpStatus.partialContent
            ..headers.contentType = ContentType('video', 'mp2t')
            ..add(_transportStreamBytes(packetCount: 1));
        case '/target.ts':
          request.response.statusCode = HttpStatus.serviceUnavailable;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() => upstream.close(force: true));

    final root = Uri.parse(
      'http://${upstream.address.host}:${upstream.port}/master.m3u8',
    );
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=640x266\n'
        'low.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=960x534\n'
        'target.m3u8\n';

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: root,
      manifestBody: manifestBody,
      headers: const <String, String>{},
      continuousTsTargetHeight: 720,
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isFalse);
  });

  test('HLS preflight probes the decoder-preroll segment near resume',
      () async {
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.statusCode = request.uri.path == '/segment-1.ts'
          ? HttpStatus.serviceUnavailable
          : HttpStatus.partialContent;
      if (request.response.statusCode == HttpStatus.partialContent) {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(_transportStreamBytes(packetCount: 1));
      }
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-TARGETDURATION:10');
    for (var index = 0; index < 5; index += 1) {
      manifestBody
        ..writeln('#EXTINF:10,')
        ..writeln(
          'http://${mediaServer.address.host}:${mediaServer.port}'
          '/segment-$index.ts',
        );
    }
    manifestBody.writeln('#EXT-X-ENDLIST');

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody.toString(),
      headers: const <String, String>{'Referer': 'https://media.invalid/'},
      resumePosition: const Duration(seconds: 35),
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isFalse);
  });

  test('HLS preflight rejects a break late in the full startup lead', () async {
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      request.response.statusCode = request.uri.path == '/segment-4.ts'
          ? HttpStatus.serviceUnavailable
          : HttpStatus.ok;
      if (request.response.statusCode == HttpStatus.ok) {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(_transportStreamBytes(packetCount: 1));
      }
      await request.response.close();
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-TARGETDURATION:10');
    for (var index = 0; index < 6; index += 1) {
      manifestBody
        ..writeln('#EXTINF:10,')
        ..writeln(
          'http://${mediaServer.address.host}:${mediaServer.port}'
          '/segment-$index.ts',
        );
    }
    manifestBody.writeln('#EXT-X-ENDLIST');

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody.toString(),
      headers: const <String, String>{'Referer': 'https://media.invalid/'},
      resumePosition: const Duration(seconds: 35),
      timeout: const Duration(seconds: 2),
    );

    expect(readable, isFalse);
  });

  test('HLS preflight builds the full startup lead with bounded concurrency',
      () async {
    var inFlight = 0;
    var peakInFlight = 0;
    final mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    mediaServer.listen((request) async {
      inFlight += 1;
      if (inFlight > peakInFlight) peakInFlight = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType('video', 'mp2t')
        ..add(_transportStreamBytes(packetCount: 1));
      await request.response.close();
      inFlight -= 1;
    });
    addTearDown(() => mediaServer.close(force: true));

    final manifestUri = Uri.parse('https://media.invalid/movie/index.m3u8');
    final manifestBody = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-TARGETDURATION:10');
    for (var index = 0; index < 6; index += 1) {
      manifestBody
        ..writeln('#EXTINF:10,')
        ..writeln(
          'http://${mediaServer.address.host}:${mediaServer.port}'
          '/segment-$index.ts',
        );
    }
    manifestBody.writeln('#EXT-X-ENDLIST');

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: manifestUri,
      manifestBody: manifestBody.toString(),
      headers: const <String, String>{'Referer': 'https://media.invalid/'},
      timeout: const Duration(milliseconds: 1800),
    );

    expect(readable, isTrue);
    expect(peakInFlight, greaterThan(1));
    expect(peakInFlight, lessThanOrEqualTo(3));
  });

  test('continuous TS reuses the validated preflight startup window', () async {
    final events = <String>[];
    final segmentRequests = <String, int>{};
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final root = Uri.parse(
      'http://${upstream.address.host}:${upstream.port}/index.m3u8',
    );
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:20\n'
        '#EXTINF:20,\n'
        'segment-0.ts\n'
        '#EXTINF:20,\n'
        'segment-1.ts\n'
        '#EXTINF:20,\n'
        'segment-2.ts\n'
        '#EXT-X-ENDLIST\n';
    upstream.listen((request) async {
      if (request.uri.path == '/index.m3u8') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType =
              ContentType('application', 'vnd.apple.mpegurl')
          ..write(manifestBody);
        await request.response.close();
        return;
      }
      final count = (segmentRequests[request.uri.path] ?? 0) + 1;
      segmentRequests[request.uri.path] = count;
      if (count > 1) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
        return;
      }
      await _writeTransportStream(request.response);
    });

    final readable = await LibVlcHlsRelay.hasReadableMediaSegment(
      manifestUri: root,
      manifestBody: manifestBody,
      headers: const <String, String>{},
      timeout: const Duration(seconds: 2),
    );
    expect(readable, isTrue);

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: root,
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final mediaBytes = await _fetchContinuousTs(relay.localUri, events);

    expect(mediaBytes, isNotEmpty, reason: events.join('\n'));
    expect(mediaBytes.first, 0x47);
    expect(segmentRequests.values, everyElement(1));
  });

  test('continuous relay prepends EXT-X-MAP for fragmented MP4 HLS', () async {
    final events = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final root = Uri.parse(
      'http://${upstream.address.host}:${upstream.port}/index.m3u8',
    );
    final initialization = _mp4Box('ftyp', <int>[0, 0, 0, 0]);
    final firstFragment = <int>[
      ..._mp4Box('moof', <int>[0, 0, 0, 1]),
      ..._mp4Box('mdat', <int>[1, 2, 3, 4]),
    ];
    final secondFragment = <int>[
      ..._mp4Box('moof', <int>[0, 0, 0, 2]),
      ..._mp4Box('mdat', <int>[5, 6, 7, 8]),
    ];
    final manifestBody = '#EXTM3U\n'
        '#EXT-X-VERSION:7\n'
        '#EXT-X-TARGETDURATION:4\n'
        '#EXT-X-MAP:URI="init.mp4"\n'
        '#EXTINF:4,\n'
        'segment-0.m4s\n'
        '#EXTINF:4,\n'
        'segment-1.m4s\n'
        '#EXT-X-ENDLIST\n';

    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/index.m3u8':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType =
                ContentType('application', 'vnd.apple.mpegurl')
            ..write(manifestBody);
          break;
        case '/init.mp4':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('video', 'mp4')
            ..add(initialization);
          break;
        case '/segment-0.m4s':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('video', 'mp4')
            ..add(firstFragment);
          break;
        case '/segment-1.m4s':
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType('video', 'mp4')
            ..add(secondFragment);
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final relay = await LibVlcHlsRelay.start(
      upstreamUri: root,
      headers: const <String, String>{},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: events.add,
    );
    addTearDown(() async {
      await relay.stop();
      await upstream.close(force: true);
    });

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(relay.localUri)).close();
    final mediaBytes = await response.expand((chunk) => chunk).toList();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.contentType?.mimeType, 'video/mp4');
    expect(
      mediaBytes,
      <int>[...initialization, ...firstFragment, ...secondFragment],
      reason: events.join('\n'),
    );
  });
}

List<int> _mp4Box(String type, List<int> payload) {
  final size = payload.length + 8;
  return <int>[
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
    ...type.codeUnits,
    ...payload,
  ];
}

Future<List<int>> _fetchFirstMedia(
  Uri relayUri,
  List<String> events,
) async {
  final client = HttpClient();
  try {
    final playlistResponse = await (await client.getUrl(relayUri)).close();
    expect(playlistResponse.statusCode, HttpStatus.ok);
    final playlist = await utf8.decoder.bind(playlistResponse).join();
    final mediaLine = playlist
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));
    final mediaResponse =
        await (await client.getUrl(Uri.parse(mediaLine))).close();
    expect(mediaResponse.statusCode, HttpStatus.ok);
    try {
      return await mediaResponse.expand((chunk) => chunk).toList();
    } on HttpException catch (error) {
      fail('$error\n${events.join('\n')}');
    }
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _fetchContinuousTs(
  Uri relayUri,
  List<String> events,
) async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(relayUri)).close();
    expect(response.statusCode, HttpStatus.ok);
    try {
      return await response.expand((chunk) => chunk).toList();
    } on HttpException catch (error) {
      fail('$error\n${events.join('\n')}');
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> _waitForCondition(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('Condition was not met before $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _writePlaylist(HttpResponse response) async {
  response.headers.contentType = ContentType(
    'application',
    'vnd.apple.mpegurl',
    charset: 'utf-8',
  );
  response.write(
    '#EXTM3U\n'
    '#EXT-X-TARGETDURATION:6\n'
    '#EXTINF:6,\n'
    'segment.ts\n'
    '#EXT-X-ENDLIST\n',
  );
  await response.close();
}

Future<void> _writeTransportStream(HttpResponse response) async {
  response.headers.contentType = ContentType('video', 'mp2t');
  response.add(_transportStreamBytes());
  await response.close();
}

List<int> _transportStreamBytes({int packetCount = 2}) {
  final bytes = List<int>.filled(188 * packetCount, 0);
  for (var offset = 0; offset < bytes.length; offset += 188) {
    bytes[offset] = 0x47;
  }
  return bytes;
}
