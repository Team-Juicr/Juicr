import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/libvlc_hls_relay.dart';

void main() {
  test('reloads a rolling playlist and emits each segment once', () async {
    var manifestReads = 0;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      switch (request.uri.path) {
        case '/live.m3u8':
          manifestReads += 1;
          request.response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          request.response.write(
            manifestReads == 1
                ? '#EXTM3U\n'
                    '#EXT-X-TARGETDURATION:1\n'
                    '#EXT-X-MEDIA-SEQUENCE:1\n'
                    '#EXTINF:1,\nsegment-1.ts\n'
                    '#EXTINF:1,\nsegment-2.ts\n'
                : '#EXTM3U\n'
                    '#EXT-X-TARGETDURATION:1\n'
                    '#EXT-X-MEDIA-SEQUENCE:2\n'
                    '#EXTINF:1,\nsegment-2.ts\n'
                    '#EXTINF:1,\nsegment-3.ts\n',
          );
          await request.response.close();
        case '/segment-1.ts':
        case '/segment-2.ts':
        case '/segment-3.ts':
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(
            _tsPacket(
              request.uri.pathSegments.single.replaceAll('.ts', ''),
            ),
          );
          await request.response.close();
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    });
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.address}:${upstream.port}/live.m3u8',
      ),
      headers: const {},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: (_) {},
    );

    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.localUri)).close();
      final bytes = <int>[];
      final thirdSegment = Completer<void>();
      final subscription = response.listen((chunk) {
        bytes.addAll(chunk);
        if (!thirdSegment.isCompleted &&
            utf8.decode(bytes, allowMalformed: true).contains('segment-3')) {
          thirdSegment.complete();
        }
      });
      final responseDone = subscription.asFuture<void>();

      await thirdSegment.future.timeout(const Duration(seconds: 4));
      await relay.stop();
      await responseDone;

      expect(bytes, <int>[
        ..._tsPacket('segment-1'),
        ..._tsPacket('segment-2'),
        ..._tsPacket('segment-3'),
      ]);
      expect(manifestReads, greaterThanOrEqualTo(2));
    } finally {
      client.close(force: true);
      await relay.stop();
      await upstreamSubscription.cancel();
      await upstream.close(force: true);
    }
  });

  test('emits the active EXT-X-MAP before fMP4 media and after map changes',
      () async {
    var manifestReads = 0;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      if (request.uri.path == '/live.m3u8') {
        manifestReads += 1;
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          manifestReads == 1
              ? '#EXTM3U\n'
                  '#EXT-X-TARGETDURATION:1\n'
                  '#EXT-X-MAP:URI="init-a.mp4"\n'
                  '#EXTINF:1,\npart-1.m4s\n'
              : '#EXTM3U\n'
                  '#EXT-X-TARGETDURATION:1\n'
                  '#EXT-X-MAP:URI="init-b.mp4"\n'
                  '#EXTINF:1,\npart-1.m4s\n'
                  '#EXTINF:1,\npart-2.m4s\n',
        );
        await request.response.close();
        return;
      }
      final payloads = <String, String>{
        '/init-a.mp4': 'map-a|',
        '/init-b.mp4': 'map-b|',
        '/part-1.m4s': 'media-1|',
        '/part-2.m4s': 'media-2|',
      };
      final payload = payloads[request.uri.path];
      if (payload == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.add(utf8.encode(payload));
      }
      await request.response.close();
    });
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.address}:${upstream.port}/live.m3u8',
      ),
      headers: const {},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: (_) {},
    );

    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.localUri)).close();
      final bytes = <int>[];
      final secondMedia = Completer<void>();
      final subscription = response.listen((chunk) {
        bytes.addAll(chunk);
        if (!secondMedia.isCompleted &&
            utf8.decode(bytes).contains('media-2|')) {
          secondMedia.complete();
        }
      });
      final responseDone = subscription.asFuture<void>();

      await secondMedia.future.timeout(const Duration(seconds: 4));
      await relay.stop();
      await responseDone;

      expect(utf8.decode(bytes), 'map-a|media-1|map-b|media-2|');
    } finally {
      client.close(force: true);
      await relay.stop();
      await upstreamSubscription.cancel();
      await upstream.close(force: true);
    }
  });

  test('falls back to the playlist session query for relative media',
      () async {
    final observedQueries = <String>[];
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      if (request.uri.path == '/session/live.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-ENDLIST\n'
          '#EXTINF:1,\nsegment.ts\n',
        );
        await request.response.close();
        return;
      }
      if (request.uri.path == '/session/segment.ts') {
        observedQueries.add(request.uri.query);
        if (request.uri.queryParameters['session'] == 'abc') {
          request.response.headers.contentType = ContentType('video', 'mp2t');
          request.response.add(_tsPacket('query-fallback'));
          await request.response.close();
          return;
        }
      }
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.address}:${upstream.port}'
        '/session/live.m3u8?session=abc',
      ),
      headers: const {},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: (_) {},
    );

    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.localUri)).close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (output, chunk) => output..addAll(chunk),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.first, 0x47);
      expect(observedQueries, <String>['', '', 'session=abc']);
    } finally {
      client.close(force: true);
      await relay.stop();
      await upstreamSubscription.cancel();
      await upstream.close(force: true);
    }
  });

  test('cross-origin media receives only safe playback context headers',
      () async {
    late HttpServer mediaServer;
    mediaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final mediaSubscription = mediaServer.listen((request) async {
      final hasSafeContext =
          request.headers.value(HttpHeaders.refererHeader) ==
                  'https://playback.example/' &&
              request.headers.value('origin') == 'https://playback.example';
      final leakedAuthorization =
          request.headers.value(HttpHeaders.authorizationHeader) != null;
      if (hasSafeContext && !leakedAuthorization) {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(_tsPacket('safe-cross-origin'));
      } else {
        request.response.statusCode = HttpStatus.unauthorized;
      }
      await request.response.close();
    });
    final playlistServer =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final playlistSubscription = playlistServer.listen((request) async {
      request.response.headers.contentType = ContentType(
        'application',
        'vnd.apple.mpegurl',
      );
      request.response.write(
        '#EXTM3U\n'
        '#EXT-X-ENDLIST\n'
        '#EXTINF:1,\n'
        'http://${mediaServer.address.address}:${mediaServer.port}/segment.ts\n',
      );
      await request.response.close();
    });
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${playlistServer.address.address}:${playlistServer.port}'
        '/live.m3u8',
      ),
      headers: const {
        HttpHeaders.refererHeader: 'https://playback.example/',
        'Origin': 'https://playback.example',
        HttpHeaders.authorizationHeader: 'private-token',
      },
      limitHeadersToUpstreamOrigin: true,
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: (_) {},
    );

    final client = HttpClient();
    try {
      final response = await (await client.getUrl(relay.localUri)).close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (output, chunk) => output..addAll(chunk),
      );

      expect(bytes, isNotEmpty);
      expect(bytes.first, 0x47);
    } finally {
      client.close(force: true);
      await relay.stop();
      await playlistSubscription.cancel();
      await mediaSubscription.cancel();
      await playlistServer.close(force: true);
      await mediaServer.close(force: true);
    }
  });

  test('stop aborts in-flight upstream work and prevents late output',
      () async {
    final segmentRequested = Completer<void>();
    final segmentRequestClosed = Completer<void>();
    HttpResponse? heldSegmentResponse;
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamSubscription = upstream.listen((request) async {
      if (request.uri.path == '/live.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          '#EXTM3U\n'
          '#EXT-X-TARGETDURATION:1\n'
          '#EXTINF:1,\nheld.ts\n',
        );
        await request.response.close();
        return;
      }
      heldSegmentResponse = request.response;
      request.response.headers.contentType = ContentType('video', 'mp2t');
      request.response.add(utf8.encode('before|'));
      await request.response.flush();
      request.response.done.whenComplete(() {
        if (!segmentRequestClosed.isCompleted) segmentRequestClosed.complete();
      });
      segmentRequested.complete();
    });
    final relay = await LibVlcHlsRelay.start(
      upstreamUri: Uri.parse(
        'http://${upstream.address.address}:${upstream.port}/live.m3u8',
      ),
      headers: const {},
      resumePosition: Duration.zero,
      continuousTsMode: true,
      onEvent: (_) {},
    );

    final client = HttpClient();
    try {
      final responseFuture = () async {
        final request = await client.getUrl(relay.localUri);
        return request.close();
      }();
      final bytes = <int>[];

      await segmentRequested.future.timeout(const Duration(seconds: 2));
      await relay.stop().timeout(const Duration(seconds: 2));
      try {
        heldSegmentResponse?.add(utf8.encode('after|'));
        await heldSegmentResponse?.flush();
      } catch (_) {}
      try {
        await heldSegmentResponse?.close();
      } catch (_) {}
      await segmentRequestClosed.future.timeout(const Duration(seconds: 2));
      final response = await responseFuture.timeout(const Duration(seconds: 2));
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(utf8.decode(bytes), isNot(contains('after|')));
    } finally {
      client.close(force: true);
      try {
        await heldSegmentResponse
            ?.close()
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      try {
        await upstream
            .close(force: true)
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      try {
        await relay.stop().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
      try {
        await upstreamSubscription
            .cancel()
            .timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  });

  test('reports continuous bytes before the active segment closes', () async {
    final reports = <int>[];
    var streamedBytes = 0;
    streamedBytes = reportLibVlcRelayStreamedBytes(
      streamedBytes,
      300 * 1024,
      reports.add,
    );
    streamedBytes = reportLibVlcRelayStreamedBytes(
      streamedBytes,
      300 * 1024,
      reports.add,
    );

    expect(streamedBytes, 600 * 1024);
    expect(reports, <int>[300 * 1024, 600 * 1024]);
    expect(reports.last, greaterThanOrEqualTo(512 * 1024));
  });
}

List<int> _tsPacket(String label) {
  final packet = List<int>.filled(188, 0);
  packet[0] = 0x47;
  final labelBytes = utf8.encode(label);
  packet.setRange(4, 4 + labelBytes.length, labelBytes);
  return packet;
}
