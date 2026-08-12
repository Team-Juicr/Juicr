import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:juicr/src/app_state.dart';
import 'package:juicr/src/catalog_item.dart';
import 'package:juicr/src/playback_identity_envelope.dart';
import 'package:juicr/src/playback_request_transport.dart';
import 'package:juicr/src/stream_api.dart';

void main() {
  late bool defaultProvidersEnabled;

  setUp(() {
    defaultProvidersEnabled = AppState.defaultProvidersEnabled.value;
    AppState.defaultProvidersEnabled.value = true;
  });

  tearDown(() {
    AppState.defaultProvidersEnabled.value = defaultProvidersEnabled;
  });

  test('initial movie resolve emits the hydrated public identity envelope',
      () async {
    late Uri observed;
    final api =
        StreamApi(client: _captureClient((request) => observed = request.url));
    const item = CatalogItem(
      type: MediaType.movie,
      id: 'tmdb:424783',
      tmdbId: 424783,
      imdbId: 'tt4701182',
      name: '  Bumblebee   ',
      year: '2018',
    );

    await api.resolveMovie(item);

    expect(observed.path, '/mobile/playback/session');
    expect(observed.queryParameters, {
      'id': '424783',
      'mediaType': 'movie',
      'title': 'Bumblebee',
      'year': '2018',
      'imdbId': 'tt4701182',
      'tmdbId': '424783',
    });
  });

  test(
      'episode coordinates and series type remain authoritative under stale hydration',
      () async {
    late Uri observed;
    final api =
        StreamApi(client: _captureClient((request) => observed = request.url));
    const staleItem = CatalogItem(
      type: MediaType.movie,
      id: '48866',
      tmdbId: 48866,
      imdbId: 'tt2661044',
      name: 'The 100',
      year: '2014',
    );

    await api.resolveEpisode(staleItem, season: 2, episode: 9);

    expect(observed.path, '/mobile/playback/session');
    expect(observed.queryParameters, {
      'id': '48866',
      'season': '2',
      'episode': '9',
      'mediaType': 'series',
    });
  });

  test(
      'fresh recovery reuses complete identity and adds bounded recovery fields',
      () async {
    late Uri observed;
    dynamic api = StreamApi(
      client: _captureClient((request) => observed = request.url),
    );
    const item = CatalogItem(
      type: MediaType.series,
      id: '48866',
      tmdbId: 48866,
      imdbId: 'tt2661044',
      name: 'The 100',
      year: '2014',
    );

    try {
      await api.resolveEpisode(
        item,
        season: 2,
        episode: 9,
        recoveryAttempt: 1,
      );
    } on NoSuchMethodError {
      fail('StreamApi recovery resolve does not own a recovery attempt yet');
    }

    expect(observed.queryParameters, {
      'id': '48866',
      'season': '2',
      'episode': '9',
      'mediaType': 'series',
      'title': 'The 100',
      'year': '2014',
      'imdbId': 'tt2661044',
      'tmdbId': '48866',
      'resolveMode': 'recovery',
      'recoveryAttempt': '1',
    });
  });

  test('conflicting IMDb identities are omitted instead of crossing titles',
      () async {
    late Uri observed;
    final api =
        StreamApi(client: _captureClient((request) => observed = request.url));
    const item = CatalogItem(
      type: MediaType.movie,
      id: 'tt1111111',
      imdbId: 'tt2222222',
      name: 'Conflict',
      year: '2020',
    );

    await api.resolveMovie(item);

    expect(observed.queryParameters['id'], 'tt1111111');
    expect(observed.queryParameters, isNot(contains('imdbId')));
    expect(observed.queryParameters, isNot(contains('tmdbId')));
  });

  test('minimal catalog identity remains valid with required fields only',
      () async {
    late Uri observed;
    final api =
        StreamApi(client: _captureClient((request) => observed = request.url));
    const item = CatalogItem(
      type: MediaType.movie,
      id: 'local-safe-id',
      name: '',
      year: 'unknown',
      imdbId: 'not-imdb',
    );

    await api.resolveMovie(item);

    expect(observed.queryParameters, {
      'id': 'local-safe-id',
      'mediaType': 'movie',
    });
  });

  test('provider refresh keeps public identity and excludes private context',
      () async {
    late Uri observed;
    final api =
        StreamApi(client: _captureClient((request) => observed = request.url));
    const item = CatalogItem(
      type: MediaType.series,
      id: '48866',
      tmdbId: 48866,
      imdbId: 'tt2661044',
      name: 'The 100',
      year: '2014',
    );

    await api.resolveEpisodeNativeSources(
      item,
      season: 2,
      episode: 9,
      providerId: 'builtin',
    );

    expect(observed.path, '/resolve/tv');
    expect(observed.queryParameters['title'], 'The 100');
    expect(observed.queryParameters['year'], '2014');
    expect(observed.queryParameters['imdbId'], 'tt2661044');
    expect(observed.queryParameters['tmdbId'], '48866');
    for (final privateKey in {
      'source',
      'engine',
      'device',
      'account',
      'headers',
      'token',
    }) {
      expect(observed.queryParameters, isNot(contains(privateKey)));
    }
  });

  test('shared identity envelope excludes provider and player context', () {
    expect(androidPlaybackIdentityPublicKeys, isNot(contains('provider')));
    expect(
      androidPlaybackIdentityPublicKeys,
      isNot(containsAll({'source', 'engine', 'device', 'account'})),
    );
  });

  test('numeric canonical identity omits unproven or conflicting external ids',
      () {
    const missingTmdbProof = CatalogItem(
      type: MediaType.movie,
      id: '424783',
      imdbId: 'tt4701182',
      name: 'Bumblebee',
      year: '2018',
    );
    const conflictingTmdb = CatalogItem(
      type: MediaType.movie,
      id: '424783',
      tmdbId: 999999,
      imdbId: 'tt4701182',
      name: 'Bumblebee',
      year: '2018',
    );

    expect(
      buildAndroidPlaybackIdentityEnvelope(missingTmdbProof, series: false),
      {
        'id': '424783',
        'mediaType': 'movie',
        'title': 'Bumblebee',
        'year': '2018',
      },
    );
    expect(
      buildAndroidPlaybackIdentityEnvelope(conflictingTmdb, series: false),
      {
        'id': '424783',
        'mediaType': 'movie',
      },
    );
  });

  test('IMDb canonical identity emits only an exact IMDb mapping', () {
    const exact = CatalogItem(
      type: MediaType.movie,
      id: 'tt4701182',
      imdbId: 'tt4701182',
      tmdbId: 424783,
      name: 'Bumblebee',
      year: '2018',
    );

    expect(
      buildAndroidPlaybackIdentityEnvelope(exact, series: false),
      {
        'id': 'tt4701182',
        'mediaType': 'movie',
        'title': 'Bumblebee',
        'year': '2018',
        'imdbId': 'tt4701182',
      },
    );
  });

  test('route type mismatch emits required minimal identity only', () {
    const staleMovieHydration = CatalogItem(
      type: MediaType.movie,
      id: '48866',
      tmdbId: 48866,
      imdbId: 'tt2661044',
      name: 'The 100',
      year: '2014',
    );

    expect(
      buildAndroidPlaybackIdentityEnvelope(
        staleMovieHydration,
        series: true,
        season: 2,
        episode: 9,
      ),
      {
        'id': '48866',
        'season': '2',
        'episode': '9',
        'mediaType': 'series',
      },
    );
  });

  test('conflicting hydrated route id suppresses all optional identity', () {
    const staleHydration = CatalogItem(
      type: MediaType.movie,
      id: '424783',
      tmdbId: 999999,
      imdbId: 'tt9999999',
      name: 'Wrong title',
      year: '2024',
    );

    expect(
      buildAndroidPlaybackIdentityEnvelope(staleHydration, series: false),
      {'id': '424783', 'mediaType': 'movie'},
    );
  });

  test('playback timeout closes the owned request transport', () async {
    final transport = _DeferredTrackingClient();
    final api = StreamApi(
      client: _captureClient((_) {}),
      playbackClientFactory: () => transport,
      remoteBootstrapTimeout: const Duration(milliseconds: 20),
    );
    const item = CatalogItem(
      type: MediaType.movie,
      id: '424784',
      tmdbId: 424784,
      name: 'Independent disposal fixture',
    );

    final stopwatch = Stopwatch()..start();
    await expectLater(
      api.resolveMovie(item),
      throwsA(isA<StreamApiTemporaryBlockException>()),
    );
    stopwatch.stop();
    await transport.closed.future.timeout(const Duration(seconds: 1));
    expect(transport.closeCount, 1);
    expect(transport.responseCompleted, isTrue);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
  });

  test('StreamApi disposal cancels and settles an active playback request',
      () async {
    final transport = _DeferredTrackingClient();
    final api = StreamApi(
      client: _captureClient((_) {}),
      playbackClientFactory: () => transport,
      remoteBootstrapTimeout: const Duration(seconds: 5),
    );
    const item = CatalogItem(
      type: MediaType.movie,
      id: '424783',
      tmdbId: 424783,
      name: 'Bumblebee',
    );

    final request = api.resolveMovie(item);
    await transport.started.future.timeout(const Duration(seconds: 1));
    api.close();

    await transport.closed.future.timeout(const Duration(seconds: 1));
    await expectLater(
      request,
      throwsA(isA<PlaybackRequestCancelledException>()),
    );
    expect(transport.closeCount, 1);
  });

  test('bounded recovery cancels its child and waits for settlement', () async {
    var settled = false;
    final stopwatch = Stopwatch()..start();

    await expectLater(
      runCancelablePlaybackAttempt<String>(
        timeout: const Duration(milliseconds: 20),
        operation: (cancellation) {
          final result = Completer<String>();
          cancellation.addListener(() {
            Timer(const Duration(milliseconds: 25), () {
              settled = true;
              result.completeError(const PlaybackRequestCancelledException());
            });
          });
          return result.future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    stopwatch.stop();

    expect(settled, isTrue);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(40));
  });

  test('already cancelled parent never starts recovery operation', () async {
    final parent = PlaybackRequestCancellation()..cancel();
    var started = false;

    await expectLater(
      runCancelablePlaybackAttempt<void>(
        timeout: const Duration(seconds: 1),
        parentCancellation: parent,
        operation: (_) async => started = true,
      ),
      throwsA(isA<PlaybackRequestCancelledException>()),
    );

    expect(started, isFalse);
  });
}

MockClient _captureClient(void Function(http.Request request) capture) {
  return MockClient((request) async {
    capture(request);
    return http.Response(
      jsonEncode({
        'sources': [
          {
            'provider': 'builtin',
            'name': 'candidate',
            'url': 'https://example.invalid/video.m3u8',
            'type': 'hls',
          },
        ],
        'embeds': <Object>[],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

class _DeferredTrackingClient extends http.BaseClient {
  final Completer<void> started = Completer<void>();
  final Completer<void> closed = Completer<void>();
  final Completer<http.StreamedResponse> _response =
      Completer<http.StreamedResponse>();
  int closeCount = 0;

  bool get responseCompleted => _response.isCompleted;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!started.isCompleted) started.complete();
    return _response.future;
  }

  @override
  void close() {
    closeCount += 1;
    if (!closed.isCompleted) closed.complete();
    if (!_response.isCompleted) {
      Timer(const Duration(milliseconds: 25), () {
        if (!_response.isCompleted) {
          _response.completeError(http.ClientException('closed'));
        }
      });
    }
    super.close();
  }
}
