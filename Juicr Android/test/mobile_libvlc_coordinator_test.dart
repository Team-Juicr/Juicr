import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_libvlc_coordinator.dart';
import 'package:juicr/src/mobile_libvlc_models.dart';
import 'package:juicr/src/mobile_playback_route_startup.dart';

void main() {
  group('MobileLibVlcCoordinator startup', () {
    test(
        'native startup stall yields reserved budget to a distinct local candidate',
        () async {
      final primary = _transportCandidate(
        'primary-1080',
        '1080P',
        path: 'primary/1080.m3u8',
      );
      final recovery = _transportCandidate(
        'recovery-1080',
        '1080P',
        path: 'recovery/1080.m3u8',
        mirror: 'mirror-b',
      );
      final attempted = <String>[];
      final primaryDriver = _FakeDriver(afterPlay: const []);
      final recoveryDriver = _provedDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver =
              candidate.id == primary.id ? primaryDriver : recoveryDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 8192,
            completedMediaSegments: 3,
            estimatedBufferedPosition: Duration(minutes: 32),
            timelineOffset: Duration(minutes: 30),
          ),
        ),
        freshResolver: () async => const <MobileLibVlcSourceCandidate>[],
        startupTimeout: const Duration(milliseconds: 200),
        startupBudget: const Duration(milliseconds: 140),
        freshRecoveryReserve: const Duration(milliseconds: 60),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[primary, recovery],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(attempted, <String>['primary-1080', 'recovery-1080']);
      expect(primaryDriver.disposeCount, 1);
      expect(result.candidate.id, recovery.id);
      expect(result.anchor, greaterThanOrEqualTo(const Duration(minutes: 30)));
      await coordinator.close();
    });

    test(
        'native startup stall rejects refreshed aliases but keeps a distinct session eligible',
        () async {
      final primary = _transportCandidate(
        'primary-1080',
        '1080P',
        path: 'renditions/1080.m3u8',
      );
      final alias = _transportCandidate(
        'primary-auto',
        'Auto',
        path: 'master.m3u8',
      );
      final distinct = _transportCandidate(
        'distinct-auto',
        'Auto',
        path: 'master.m3u8',
        mirror: 'mirror-b',
      );
      expect(alias.transportSessionIdentity, primary.transportSessionIdentity);
      final attempted = <String>[];
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver = candidate.id == distinct.id
              ? _provedDriver()
              : _FakeDriver(afterPlay: const []);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 8192,
            completedMediaSegments: 3,
            estimatedBufferedPosition: Duration(minutes: 32),
            timelineOffset: Duration(minutes: 30),
          ),
        ),
        freshResolver: () async => <MobileLibVlcSourceCandidate>[
          alias,
          distinct,
        ],
        startupTimeout: const Duration(milliseconds: 200),
        startupBudget: const Duration(milliseconds: 140),
        freshRecoveryReserve: const Duration(milliseconds: 60),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[primary],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(attempted, <String>['primary-1080', 'distinct-auto']);
      expect(result.candidate.id, distinct.id);
      await coordinator.close();
    });

    test(
        'native startup stall runs fresh recovery once inside the route budget',
        () async {
      final primary = _transportCandidate(
        'primary-1080',
        '1080P',
        path: 'primary/1080.m3u8',
      );
      final distinct = _transportCandidate(
        'fresh-1080',
        '1080P',
        path: 'fresh/1080.m3u8',
        mirror: 'mirror-b',
      );
      final attempted = <String>[];
      var freshResolveCount = 0;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver = candidate.id == distinct.id
              ? _provedDriver()
              : _FakeDriver(afterPlay: const []);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 8192,
            completedMediaSegments: 3,
            estimatedBufferedPosition: Duration(minutes: 32),
            timelineOffset: Duration(minutes: 30),
          ),
        ),
        freshResolver: () async {
          freshResolveCount += 1;
          return <MobileLibVlcSourceCandidate>[distinct];
        },
        startupTimeout: const Duration(milliseconds: 200),
        startupBudget: const Duration(milliseconds: 140),
        freshRecoveryReserve: const Duration(milliseconds: 60),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[primary],
        anchor: const Duration(seconds: 1527),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(freshResolveCount, 1);
      expect(attempted, <String>['primary-1080', 'fresh-1080']);
      expect(result.candidate.id, distinct.id);
      expect(
          result.anchor, greaterThanOrEqualTo(const Duration(seconds: 1527)));
      await coordinator.close();
    });

    test('route-owned deadline is not restarted when coordinator open begins',
        () async {
      final transportGate = Completer<MobileLibVlcTransport?>();
      final routeDeadline =
          DateTime.now().add(const Duration(milliseconds: 75));
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          fail('native must not open after the route deadline');
        },
        transportFactory: (candidate, anchor) => transportGate.future,
        freshResolver: () async => const <MobileLibVlcSourceCandidate>[],
        startupBudget: const Duration(seconds: 1),
        freshRecoveryReserve: const Duration(milliseconds: 30),
      );
      await Future<void>.delayed(const Duration(milliseconds: 35));
      final stopwatch = Stopwatch()..start();

      await expectLater(
        coordinator.open(
          candidates: <MobileLibVlcSourceCandidate>[
            _transportCandidate('route-owned', 'Auto', path: 'master.m3u8'),
          ],
          anchor: const Duration(seconds: 1527),
          reason: MobileLibVlcOpenReason.resume,
          routeStartupDeadline: routeDeadline,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                MobileLibVlcFailureKind.startupTimeout,
              )
              .having(
                (failure) => failure.anchor,
                'anchor',
                const Duration(seconds: 1527),
              ),
        ),
      );

      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 150)));
      await coordinator.close();
    });

    test(
        'auth-unreadable rendition session is rejected once before fresh recovery',
        () async {
      final attempted = <String>[];
      var freshResolveCount = 0;
      final failedTransports = <_FakeTransport>[];
      final freshDriver = _provedDriver(39);
      final expired = <MobileLibVlcSourceCandidate>[
        _transportCandidate('expired-1080', '1080P',
            path: 'renditions/1080.m3u8'),
        _transportCandidate('expired-720', '720P', path: 'renditions/720.m3u8'),
        _transportCandidate('expired-auto', 'Auto', path: 'master.m3u8'),
      ];
      final fresh = _transportCandidate(
        'fresh-query-session',
        '1080P',
        path: 'renditions/1080.m3u8',
        query: 'session=fresh',
      );
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver = candidate.id == fresh.id
              ? freshDriver
              : _FakeDriver(afterPlay: const []);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async {
          if (candidate.id == fresh.id) {
            return _FakeTransport(
              snapshot: const MobileLibVlcTransportSnapshot(
                totalMediaBytes: 8192,
                completedMediaSegments: 3,
                estimatedBufferedPosition: Duration(minutes: 41),
                timelineOffset: Duration(minutes: 39),
              ),
            );
          }
          final transport = _FakeTransport(
            snapshot: const MobileLibVlcTransportSnapshot(
              totalMediaBytes: 0,
              completedMediaSegments: 0,
              estimatedBufferedPosition: Duration.zero,
              terminalFailure: MobileLibVlcFailureKind.transportFailure,
              terminalFailureClass:
                  MobileLibVlcTransportFailureClass.authSessionUnreadable,
            ),
          );
          failedTransports.add(transport);
          return transport;
        },
        freshResolver: () async {
          freshResolveCount += 1;
          return <MobileLibVlcSourceCandidate>[fresh];
        },
        startupTimeout: const Duration(milliseconds: 100),
        startupBudget: const Duration(seconds: 1),
        freshRecoveryReserve: const Duration(milliseconds: 400),
      );

      final result = await coordinator.open(
        candidates: expired,
        anchor: const Duration(seconds: 2341),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(attempted, <String>['expired-1080', 'fresh-query-session']);
      expect(freshResolveCount, 1);
      expect(failedTransports, hasLength(1));
      expect(failedTransports.single.stopCount, 1);
      expect(result.candidate.id, 'fresh-query-session');
      expect(
          result.anchor, greaterThanOrEqualTo(const Duration(seconds: 2341)));
      await coordinator.close();
    });

    test('non-auth transient failure does not quarantine sibling rendition',
        () async {
      final attempted = <String>[];
      final first = _transportCandidate('slow-1080', '1080P',
          path: 'renditions/1080.m3u8');
      final second =
          _transportCandidate('slow-720', '720P', path: 'renditions/720.m3u8');
      final proved = _provedDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver = candidate.id == second.id
              ? proved
              : _FakeDriver(afterPlay: const []);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: candidate.id == first.id
              ? const MobileLibVlcTransportSnapshot(
                  totalMediaBytes: 0,
                  completedMediaSegments: 0,
                  estimatedBufferedPosition: Duration.zero,
                  terminalFailure: MobileLibVlcFailureKind.transportFailure,
                  terminalFailureClass:
                      MobileLibVlcTransportFailureClass.transient,
                )
              : const MobileLibVlcTransportSnapshot(
                  totalMediaBytes: 4096,
                  completedMediaSegments: 2,
                  estimatedBufferedPosition: Duration(minutes: 32),
                  timelineOffset: Duration(minutes: 30),
                ),
        ),
        freshResolver: () async => const <MobileLibVlcSourceCandidate>[],
        startupTimeout: const Duration(milliseconds: 100),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[first, second],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(attempted, <String>['slow-1080', 'slow-720']);
      expect(result.candidate.id, 'slow-720');
      await coordinator.close();
    });

    test('auth rejection leaves a distinct mirror session eligible', () async {
      final attempted = <String>[];
      final rejected = _transportCandidate(
        'mirror-a-1080',
        '1080P',
        path: 'renditions/1080.m3u8',
      );
      final distinct = _transportCandidate(
        'mirror-b-1080',
        '1080P',
        path: 'renditions/1080.m3u8',
        mirror: 'mirror-b',
      );
      final proved = _provedDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          final driver = candidate.id == distinct.id
              ? proved
              : _FakeDriver(afterPlay: const []);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: candidate.id == rejected.id
              ? const MobileLibVlcTransportSnapshot(
                  totalMediaBytes: 0,
                  completedMediaSegments: 0,
                  estimatedBufferedPosition: Duration.zero,
                  terminalFailure: MobileLibVlcFailureKind.transportFailure,
                  terminalFailureClass:
                      MobileLibVlcTransportFailureClass.authSessionUnreadable,
                )
              : const MobileLibVlcTransportSnapshot(
                  totalMediaBytes: 4096,
                  completedMediaSegments: 2,
                  estimatedBufferedPosition: Duration(minutes: 32),
                  timelineOffset: Duration(minutes: 30),
                ),
        ),
        freshResolver: () async => const <MobileLibVlcSourceCandidate>[],
        startupTimeout: const Duration(milliseconds: 100),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[rejected, distinct],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(attempted, <String>['mirror-a-1080', 'mirror-b-1080']);
      expect(result.candidate.id, 'mirror-b-1080');
      await coordinator.close();
    });

    test(
        'launch rejection skips refreshed Auto alias but permits distinct session',
        () async {
      final rejected1080 = _transportCandidate(
        'expired-1080',
        '1080P',
        path: 'renditions/1080.m3u8',
      );
      final sameSessionAuto = _transportCandidate(
        'expired-auto-refresh',
        'Auto',
        path: 'master.m3u8',
      );
      final distinct = _transportCandidate(
        'fresh-query-session',
        'Auto',
        path: 'master.m3u8',
        query: 'session=fresh',
      );
      expect(
        sameSessionAuto.transportSessionIdentity,
        rejected1080.transportSessionIdentity,
      );
      final launchRejectedSessions = <String>{
        rejected1080.transportSessionIdentity,
      };
      final attempted = <String>[];
      var freshResolveCount = 0;
      final proved = _provedDriver(39);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempted.add(candidate.id);
          proved.markCreated();
          return proved;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(
          snapshot: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 8192,
            completedMediaSegments: 3,
            estimatedBufferedPosition: Duration(minutes: 41),
            timelineOffset: Duration(minutes: 39),
          ),
        ),
        freshResolver: () async {
          freshResolveCount += 1;
          return <MobileLibVlcSourceCandidate>[sameSessionAuto, distinct];
        },
        startupTimeout: const Duration(milliseconds: 100),
        startupBudget: const Duration(seconds: 1),
      );

      final result = await coordinator.open(
        candidates: <MobileLibVlcSourceCandidate>[sameSessionAuto],
        anchor: const Duration(seconds: 2341),
        reason: MobileLibVlcOpenReason.resume,
        rejectedTransportSessions: launchRejectedSessions,
      );

      expect(freshResolveCount, 1);
      expect(attempted, <String>['fresh-query-session']);
      expect(result.candidate.id, 'fresh-query-session');
      expect(
          result.anchor, greaterThanOrEqualTo(const Duration(seconds: 2341)));
      expect(
        launchRejectedSessions,
        contains(rejected1080.transportSessionIdentity),
      );
      await coordinator.close();
    });

    test('absolute startup budget rejects and cleans up late transport work',
        () async {
      final lateTransport = _FakeTransport();
      final transportGate = Completer<MobileLibVlcTransport?>();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          fail('driver must not be created after the startup budget expires');
        },
        transportFactory: (candidate, anchor) => transportGate.future,
        freshResolver: () async => const <MobileLibVlcSourceCandidate>[],
        startupTimeout: const Duration(seconds: 1),
        startupBudget: const Duration(milliseconds: 40),
        freshRecoveryReserve: const Duration(milliseconds: 20),
      );
      final stopwatch = Stopwatch()..start();

      await expectLater(
        coordinator.open(
          candidates: <MobileLibVlcSourceCandidate>[
            _transportCandidate('late', 'Auto', path: 'master.m3u8'),
          ],
          anchor: const Duration(seconds: 2341),
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                MobileLibVlcFailureKind.startupTimeout,
              )
              .having(
                (failure) => failure.anchor,
                'anchor',
                const Duration(seconds: 2341),
              ),
        ),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 250)));

      transportGate.complete(lateTransport);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(lateTransport.stopCount, 1);
      expect(coordinator.currentTransport, isNull);
      await coordinator.close();
    });

    test('publishes the bounded TV-style startup sequence', () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1400),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final transport = _FakeTransport();
      final coordinator = _coordinator(driver, transport);
      final states = <MobileLibVlcState>[];
      final subscription = coordinator.states.listen(states.add);

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );

      expect(
        states,
        containsAllInOrder(const [
          MobileLibVlcState.resolving,
          MobileLibVlcState.prebuffering,
          MobileLibVlcState.opening,
          MobileLibVlcState.proving,
          MobileLibVlcState.playing,
        ]),
      );
      expect(result.driver.position, const Duration(milliseconds: 1400));
      expect(driver.initializeCount, 1);
      expect(driver.playCount, 1);
      await subscription.cancel();
      await coordinator.close();
    });

    test('playing without an advancing video clock is not proof', () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 5),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 5),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final coordinator = _coordinator(
        driver,
        _FakeTransport(),
        startupTimeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        coordinator.open(
          candidates: [_candidate()],
          anchor: const Duration(seconds: 5),
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.startupTimeout,
          ),
        ),
      );
      expect(coordinator.state, MobileLibVlcState.failed);
      await coordinator.close();
    });

    test('terminal HLS transport failure aborts startup proof immediately',
        () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: false,
            isBuffering: true,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final transport = _FakeTransport();
      final coordinator = _coordinator(
        driver,
        transport,
        startupTimeout: const Duration(seconds: 2),
      );
      final stopwatch = Stopwatch()..start();

      final opening = coordinator.open(
        candidates: [_candidate()],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      await driver.created;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      transport.emit(
        const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 0,
          completedMediaSegments: 0,
          estimatedBufferedPosition: Duration.zero,
          terminalFailure: MobileLibVlcFailureKind.transportFailure,
        ),
      );

      await expectLater(
        opening,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.transportFailure,
          ),
        ),
      );
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(transport.stopCount, 1);
      await coordinator.close();
    });

    test('transport media proof can pair with sustained visual clock advance',
        () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 800),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1600),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
          ),
        ],
      );
      final transport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 2,
          estimatedBufferedPosition: Duration(seconds: 12),
        ),
      );
      final coordinator = _coordinator(driver, transport);

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );

      expect(result.driver.position, const Duration(milliseconds: 1600));
      await coordinator.close();
    });

    test(
        'HLS transport proof can pair with sustained clock advance before geometry',
        () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 800),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1600),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final transport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 2,
          estimatedBufferedPosition: Duration(seconds: 12),
        ),
      );
      final coordinator = _coordinator(driver, transport);

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );

      expect(result.driver.position, const Duration(milliseconds: 1600));
      expect(result.driver.hasVideoGeometry, isFalse);
      await coordinator.close();
    });

    test(
        'HLS startup proof translates the local relay clock to the movie timeline',
        () async {
      const anchor = Duration(minutes: 1, seconds: 43);
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 800),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1600),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final transport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 6,
          estimatedBufferedPosition: Duration(minutes: 1, seconds: 50),
          timelineOffset: Duration(minutes: 1, seconds: 20),
        ),
      );
      final coordinator = _coordinator(
        driver,
        transport,
        startupTimeout: const Duration(milliseconds: 40),
      );

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: anchor,
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(result.anchor, greaterThanOrEqualTo(anchor));
      expect(transport.stopCount, 0);
      await coordinator.close();
    });

    test('late HLS transport proof rechecks an already advancing driver clock',
        () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 800),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1600),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final transport = _FakeTransport();
      final coordinator = _coordinator(
        driver,
        transport,
        startupTimeout: const Duration(milliseconds: 100),
      );

      final opening = coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );
      await driver.created;
      await Future<void>.delayed(const Duration(milliseconds: 15));
      transport.emit(
        const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 2,
          estimatedBufferedPosition: Duration(seconds: 12),
        ),
      );

      final result = await opening;
      expect(result.driver.position, const Duration(milliseconds: 1600));
      expect(result.driver.hasVideoGeometry, isFalse);
      await coordinator.close();
    });

    test(
        'direct VOD advancing audio clock without geometry is not startup proof',
        () async {
      const anchor = Duration(minutes: 33, seconds: 57);
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: anchor,
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 33, seconds: 57, milliseconds: 700),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 33, seconds: 58, milliseconds: 400),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => null,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 40),
      );

      await expectLater(
        coordinator.open(
          candidates: [
            MobileLibVlcSourceCandidate(
              id: 'direct-vod',
              mirrorGroup: '1080p',
              qualityLabel: '1080P',
              uri: Uri.parse('https://example.invalid/movie.mp4'),
            ),
          ],
          anchor: anchor,
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.startupTimeout,
          ),
        ),
      );

      await coordinator.close();
    });

    test('repairs audio only after direct MP4 startup is proved', () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 1),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 2),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 3),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => null,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );

      await coordinator.open(
        candidates: [
          MobileLibVlcSourceCandidate(
            id: 'direct-mp4-audio',
            mirrorGroup: '1080p',
            qualityLabel: '1080P',
            uri: Uri.parse('https://example.invalid/movie.mp4'),
          ),
        ],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );

      expect(driver.playCount, 1);
      expect(driver.ensureAudioCount, 1);
      expect(driver.audioEnsuredAfterPlay, isTrue);
      await coordinator.close();
    });

    test('direct MP4 rejects sustained clock proof without video geometry',
        () async {
      const anchor = Duration(minutes: 24, seconds: 52);
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: anchor,
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 24, seconds: 55),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 24, seconds: 58),
            duration: Duration(hours: 1, minutes: 53),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
        ],
      );
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => null,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );

      await expectLater(
        coordinator.open(
          candidates: [
            MobileLibVlcSourceCandidate(
              id: 'direct-mp4',
              mirrorGroup: '1080p',
              qualityLabel: '1080P',
              uri: Uri.parse('https://example.invalid/movie.mp4'),
            ),
          ],
          anchor: anchor,
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.startupTimeout,
          ),
        ),
      );

      await coordinator.close();
    });

    test('transport-required VOD never opens the original URI directly',
        () async {
      const anchor = Duration(minutes: 31);
      var driverFactoryCalled = false;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          driverFactoryCalled = true;
          return _provedDriver();
        },
        transportFactory: (candidate, anchor) async => null,
        freshResolver: () async => const [],
      );

      await expectLater(
        coordinator.open(
          candidates: [
            MobileLibVlcSourceCandidate(
              id: 'relay-required-vod',
              mirrorGroup: '1080p',
              qualityLabel: '1080P',
              uri: Uri.parse('https://example.invalid/master.m3u8'),
              requiresTransport: true,
            ),
          ],
          anchor: anchor,
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                MobileLibVlcFailureKind.transportFailure,
              )
              .having(
                (failure) => failure.anchor,
                'anchor',
                anchor,
              ),
        ),
      );
      expect(driverFactoryCalled, isFalse);

      await coordinator.close();
    });

    test('one resume jump followed by a frozen clock is not startup proof',
        () async {
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 30),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 30),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final coordinator = _coordinator(
        driver,
        _FakeTransport(),
        startupTimeout: const Duration(milliseconds: 30),
      );

      await expectLater(
        coordinator.open(
          candidates: [_candidate()],
          anchor: Duration.zero,
          reason: MobileLibVlcOpenReason.initial,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );
      await coordinator.close();
    });

    test('resume is reasserted after play when libVLC ignores the early seek',
        () async {
      const anchor = Duration(minutes: 17);
      final driver = _FakeDriver(
        ignoreSeekUntilPlay: true,
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
        afterPlayingSeek: const [
          MobileLibVlcDriverSnapshot(
            position: anchor,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 17, milliseconds: 700),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 17, seconds: 1, milliseconds: 400),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final coordinator = _coordinator(driver, _FakeTransport());

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: anchor,
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(driver.seekPositions, [anchor, anchor]);
      expect(result.driver.position, greaterThanOrEqualTo(anchor));
      await coordinator.close();
    });

    test(
        'resume proof accepts advancing decoder preroll below an optimistic seek clock',
        () async {
      const anchor = Duration(seconds: 143);
      final driver = _FakeDriver(
        afterPlayingSeek: const [
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 120),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 125),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 130),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 140),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final transport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 8 * 1024 * 1024,
          completedMediaSegments: 8,
          estimatedBufferedPosition: Duration(seconds: 150),
        ),
      );
      final coordinator = _coordinator(
        driver,
        transport,
        startupTimeout: const Duration(milliseconds: 40),
      );

      final result = await coordinator.open(
        candidates: [_candidate()],
        anchor: anchor,
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(result.driver.position, const Duration(seconds: 140));
      expect(result.anchor, anchor);
      expect(transport.stopCount, 0);
      await coordinator.close();
    });

    test('startup timeout bounds owner cleanup before terminal settlement',
        () async {
      final initializeGate = Completer<void>();
      final disposeGate = Completer<void>();
      final driver = _FakeDriver(
        initializeGate: initializeGate,
        disposeGate: disposeGate,
      );
      final coordinator = _coordinator(
        driver,
        _FakeTransport(),
        startupTimeout: const Duration(milliseconds: 20),
      );
      final stopwatch = Stopwatch()..start();

      await expectLater(
        coordinator.open(
          candidates: [_candidate('cleanup-timeout')],
          anchor: const Duration(seconds: 1489),
          reason: MobileLibVlcOpenReason.resume,
          routeStartupRemainingBudget: () =>
              const Duration(milliseconds: 20) - stopwatch.elapsed,
        ).timeout(const Duration(milliseconds: 750)),
        throwsA(
          isA<MobileLibVlcTerminalFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                MobileLibVlcFailureKind.startupTimeout,
              )
              .having(
                (failure) => failure.anchor,
                'anchor',
                const Duration(seconds: 1489),
              ),
        ),
      );
      expect(driver.disposeCount, 1);
      initializeGate.complete();
      disposeGate.complete();
    });

    test('timed out initial open disposes a driver that completes late',
        () async {
      final driverGate = Completer<MobileLibVlcDriver>();
      final lateDriver = _FakeDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) => driverGate.future,
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 20),
        startupBudget: const Duration(milliseconds: 20),
        freshRecoveryReserve: Duration.zero,
      );

      await expectLater(
        coordinator.open(
          candidates: [_candidate('late-initial-driver')],
          anchor: const Duration(seconds: 1489),
          reason: MobileLibVlcOpenReason.resume,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );
      driverGate.complete(lateDriver);
      await Future<void>.delayed(Duration.zero);

      expect(lateDriver.disposeCount, 1);
    });
  });

  group('MobileLibVlcCoordinator cancellation', () {
    test('driver factory failure stops the owned transport exactly once',
        () async {
      final transport = _FakeTransport();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          throw StateError('driver factory failed');
        },
        transportFactory: (candidate, anchor) async => transport,
        freshResolver: () async => const [],
      );

      await expectLater(
        coordinator.open(
          candidates: [_candidate()],
          anchor: Duration.zero,
          reason: MobileLibVlcOpenReason.initial,
        ),
        throwsA(anything),
      );

      expect(transport.stopCount, 1);
      await coordinator.close();
      expect(transport.stopCount, 1);
    });

    test('close during a delayed driver factory disposes late owners once',
        () async {
      final driverFactoryEntered = Completer<void>();
      final driverFactoryGate = Completer<void>();
      final driver = _FakeDriver();
      final transport = _FakeTransport();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          driverFactoryEntered.complete();
          await driverFactoryGate.future;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => transport,
        freshResolver: () async => const [],
      );

      final opening = coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );
      final cancelled = expectLater(
        opening,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      await driverFactoryEntered.future;

      await coordinator.close();
      expect(transport.stopCount, 1);
      driverFactoryGate.complete();

      await cancelled;
      expect(driver.disposeCount, 1);
      expect(transport.stopCount, 1);
      await coordinator.close();
      expect(driver.disposeCount, 1);
      expect(transport.stopCount, 1);
    });

    test('close cancels pending open and disposes each owner once', () async {
      final initializeGate = Completer<void>();
      final driver = _FakeDriver(initializeGate: initializeGate);
      final transport = _FakeTransport();
      final coordinator = _coordinator(driver, transport);

      final opening = coordinator.open(
        candidates: [_candidate()],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      final cancelled = expectLater(
        opening,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      await driver.created;

      await coordinator.close();
      initializeGate.complete();

      await cancelled;
      expect(coordinator.state, MobileLibVlcState.closed);
      expect(driver.disposeCount, 1);
      expect(transport.stopCount, 1);

      await coordinator.close();
      expect(driver.disposeCount, 1);
      expect(transport.stopCount, 1);
    });

    test('stale snapshots cannot publish after close', () async {
      final initializeGate = Completer<void>();
      final driver = _FakeDriver(initializeGate: initializeGate);
      final coordinator = _coordinator(driver, _FakeTransport());
      final states = <MobileLibVlcState>[];
      final subscription = coordinator.states.listen(states.add);

      final opening = coordinator.open(
        candidates: [_candidate()],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.initial,
      );
      final cancelled = expectLater(
        opening,
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );
      await driver.created;
      await coordinator.close();
      initializeGate.complete();
      driver.emit(
        const MobileLibVlcDriverSnapshot(
          position: Duration(seconds: 1),
          duration: Duration(minutes: 90),
          isPlaying: true,
          isBuffering: false,
          hasError: false,
          videoWidth: 1920,
          videoHeight: 1080,
        ),
      );

      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(states.last, MobileLibVlcState.closed);
      expect(
          states.where((state) => state == MobileLibVlcState.playing), isEmpty);
      await subscription.cancel();
    });
  });

  group('classifyMobileLibVlcHealth', () {
    const advancingDriver = MobileLibVlcDriverSnapshot(
      position: Duration(seconds: 11),
      duration: Duration(minutes: 90),
      isPlaying: true,
      isBuffering: false,
      hasError: false,
      videoWidth: 1920,
      videoHeight: 1080,
      isInitialized: true,
      hasUsableVideoFrame: true,
    );
    const frozenDriver = MobileLibVlcDriverSnapshot(
      position: Duration(seconds: 10),
      duration: Duration(minutes: 90),
      isPlaying: true,
      isBuffering: false,
      hasError: false,
      videoWidth: 1920,
      videoHeight: 1080,
      isInitialized: true,
      hasUsableVideoFrame: true,
    );
    const previousDriver = MobileLibVlcDriverSnapshot(
      position: Duration(seconds: 10),
      duration: Duration(minutes: 90),
      isPlaying: true,
      isBuffering: false,
      hasError: false,
      videoWidth: 1920,
      videoHeight: 1080,
      isInitialized: true,
      hasUsableVideoFrame: true,
    );

    test('advancing video remains healthy even with low lead', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 11),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          driver: advancingDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 11),
          ),
          anchor: const Duration(seconds: 11),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.healthy);
    });

    test('moving video consumes buffered lead before terminal recovery', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 30),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 11),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 30),
            terminalFailure: MobileLibVlcFailureKind.transportFailure,
          ),
          anchor: const Duration(seconds: 11),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.healthy);
    });

    test('advancing continuous TS clock stays healthy with relay media proof',
        () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 10),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 20),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 22),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          transport: MobileLibVlcTransportSnapshot(
            totalMediaBytes: 4096,
            completedMediaSegments: 8,
            estimatedBufferedPosition: const Duration(minutes: 2),
            lastTransportActivityAt: DateTime.fromMillisecondsSinceEpoch(11500),
          ),
          anchor: const Duration(seconds: 22),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.healthy);
    });

    test('advancing audio-only clock remains buffering inside visual grace',
        () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 10),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 20),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(4000),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 14),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 0,
            videoHeight: 0,
            isInitialized: true,
          ),
          transport: MobileLibVlcTransportSnapshot(
            totalMediaBytes: 2048,
            completedMediaSegments: 4,
            estimatedBufferedPosition: const Duration(seconds: 45),
            lastTransportActivityAt: DateTime.fromMillisecondsSinceEpoch(3500),
          ),
          anchor: const Duration(seconds: 14),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.buffering);
    });

    test('terminal transport failure recovers after the video clock stops', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 30),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          driver: frozenDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 30),
            terminalFailure: MobileLibVlcFailureKind.transportFailure,
          ),
          anchor: const Duration(seconds: 10),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.failed);
    });

    test('terminal transport failure beats a premature local relay EOF', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 30),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          driver: const MobileLibVlcDriverSnapshot(
            position: Duration(seconds: 124),
            duration: Duration(minutes: 23, seconds: 47),
            isPlaying: false,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            isEnded: true,
            hasUsableVideoFrame: true,
          ),
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 24,
            estimatedBufferedPosition: Duration(seconds: 124),
            terminalFailure: MobileLibVlcFailureKind.transportFailure,
          ),
          anchor: const Duration(seconds: 124),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.failed);
    });

    test('frozen clock with advancing transport is bounded buffering', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 20),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(5000),
          driver: frozenDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 200,
            completedMediaSegments: 2,
            estimatedBufferedPosition: Duration(seconds: 30),
          ),
          anchor: const Duration(seconds: 10),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.buffering);
    });

    test('frozen clock with fresh transport activity remains buffering', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 20),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
          driver: frozenDriver,
          transport: MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: const Duration(seconds: 20),
            lastTransportActivityAt: DateTime.fromMillisecondsSinceEpoch(11000),
          ),
          anchor: const Duration(seconds: 10),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.buffering);
    });

    test('stale transport activity cannot mask a hard stall', () {
      final status = classifyMobileLibVlcHealth(
        previous: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(0),
          driver: previousDriver,
          transport: const MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: Duration(seconds: 20),
          ),
          anchor: const Duration(seconds: 10),
        ),
        current: MobileLibVlcHealthSample(
          observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
          driver: frozenDriver,
          transport: MobileLibVlcTransportSnapshot(
            totalMediaBytes: 100,
            completedMediaSegments: 1,
            estimatedBufferedPosition: const Duration(seconds: 20),
            lastTransportActivityAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
          anchor: const Duration(seconds: 10),
        ),
      );

      expect(status, MobileLibVlcHealthStatus.stalled);
    });

    test('frozen clock with stale transport is a hard stall', () {
      final previous = MobileLibVlcHealthSample(
        observedAt: DateTime.fromMillisecondsSinceEpoch(0),
        driver: previousDriver,
        transport: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 100,
          completedMediaSegments: 1,
          estimatedBufferedPosition: Duration(seconds: 20),
        ),
        anchor: const Duration(seconds: 10),
      );
      final current = MobileLibVlcHealthSample(
        observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
        driver: frozenDriver,
        transport: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 100,
          completedMediaSegments: 1,
          estimatedBufferedPosition: Duration(seconds: 20),
        ),
        anchor: const Duration(seconds: 10),
      );

      expect(
        classifyMobileLibVlcHealth(previous: previous, current: current),
        MobileLibVlcHealthStatus.stalled,
      );
    });

    test('reported buffering with stale transport becomes a hard stall', () {
      final previous = MobileLibVlcHealthSample(
        observedAt: DateTime.fromMillisecondsSinceEpoch(0),
        driver: previousDriver,
        transport: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 100,
          completedMediaSegments: 1,
          estimatedBufferedPosition: Duration(seconds: 20),
        ),
        anchor: const Duration(seconds: 10),
      );
      final current = MobileLibVlcHealthSample(
        observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
        driver: const MobileLibVlcDriverSnapshot(
          position: Duration(seconds: 10),
          duration: Duration(minutes: 90),
          isPlaying: true,
          isBuffering: true,
          hasError: false,
          videoWidth: 1920,
          videoHeight: 1080,
          isInitialized: true,
          hasUsableVideoFrame: true,
        ),
        transport: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 100,
          completedMediaSegments: 1,
          estimatedBufferedPosition: Duration(seconds: 20),
        ),
        anchor: const Duration(seconds: 10),
      );

      expect(
        classifyMobileLibVlcHealth(previous: previous, current: current),
        MobileLibVlcHealthStatus.stalled,
      );
    });

    test('natural completion never becomes a stall', () {
      final ended = MobileLibVlcHealthSample(
        observedAt: DateTime.fromMillisecondsSinceEpoch(12000),
        driver: const MobileLibVlcDriverSnapshot(
          position: Duration(minutes: 90),
          duration: Duration(minutes: 90),
          isPlaying: false,
          isBuffering: false,
          hasError: false,
          videoWidth: 1920,
          videoHeight: 1080,
          isInitialized: true,
          isEnded: true,
          hasUsableVideoFrame: true,
        ),
        transport: const MobileLibVlcTransportSnapshot.idle(),
        anchor: const Duration(minutes: 90),
      );

      expect(
        classifyMobileLibVlcHealth(
          previous: MobileLibVlcHealthSample(
            observedAt: DateTime.fromMillisecondsSinceEpoch(0),
            driver: previousDriver,
            transport: const MobileLibVlcTransportSnapshot.idle(),
            anchor: const Duration(seconds: 10),
          ),
          current: ended,
        ),
        MobileLibVlcHealthStatus.ended,
      );
    });
  });

  group('MobileLibVlcCoordinator recovery', () {
    test('promoted recovery survives previous owner disposal failure', () async {
      final initial = _candidate('initial');
      final recovered = _candidate('recovered');
      final oldDriver = _provedDriver(30, null, null, StateError('old'));
      final recoveredDriver = _provedDriver(31);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial'
              ? oldDriver
              : recoveredDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async => recovered,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [initial],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final result = await coordinator.recover(
        failure: MobileLibVlcFailureKind.frozenVideo,
        observedPosition: const Duration(minutes: 31),
      );

      expect(result.candidate.id, 'recovered');
      expect(coordinator.currentDriver, same(recoveredDriver));
      expect(recoveredDriver.disposeCount, 0);
      await coordinator.close();
    });

    test('uses one bounded libVLC-only recovery ladder in exact order',
        () async {
      final attempts = <String>[];
      var refreshCalls = 0;
      var resolveCalls = 0;
      final initial = _candidate('initial');
      final sibling = _candidate('sibling');
      final refreshed = _candidate('refreshed');
      final fresh = _candidate('fresh');
      final drivers = <String, List<_FakeDriver>>{
        'initial': [_provedDriver()],
        'refreshed': [_frozenDriver()],
        'sibling': [_frozenDriver()],
        'fresh': [_provedDriver(32)],
      };
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          attempts.add(candidate.id);
          final driver = drivers[candidate.id]!.removeAt(0);
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async {
          refreshCalls += 1;
          return refreshed;
        },
        freshResolver: () async {
          resolveCalls += 1;
          return [sibling, fresh];
        },
        startupTimeout: const Duration(milliseconds: 30),
      );

      await coordinator.open(
        candidates: [initial, sibling],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      attempts.clear();

      final result = await coordinator.recover(
        failure: MobileLibVlcFailureKind.frozenVideo,
        observedPosition: const Duration(minutes: 31),
      );

      expect(attempts, ['refreshed', 'sibling', 'fresh']);
      expect(refreshCalls, 1);
      expect(resolveCalls, 1);
      expect(result.candidate.id, 'fresh');
      expect(result.anchor, greaterThanOrEqualTo(const Duration(minutes: 31)));
      await coordinator.close();
    });

    test('simultaneous recovery requests coalesce under one owner', () async {
      final refreshGate = Completer<void>();
      var refreshCalls = 0;
      final initial = _candidate('initial');
      final refreshed = _candidate('refreshed');
      final initialDriver = _provedDriver();
      final refreshedDriver = _provedDriver(33);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver =
              candidate.id == 'initial' ? initialDriver : refreshedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async {
          refreshCalls += 1;
          await refreshGate.future;
          return refreshed;
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [initial],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final first = coordinator.recover(
        failure: MobileLibVlcFailureKind.frozenVideo,
        observedPosition: const Duration(minutes: 31),
      );
      final second = coordinator.recover(
        failure: MobileLibVlcFailureKind.transportFailure,
        observedPosition: const Duration(minutes: 32),
      );
      refreshGate.complete();

      final results = await Future.wait([first, second]);
      expect(refreshCalls, 1);
      expect(results.first.candidate.id, 'refreshed');
      expect(results.last.candidate.id, 'refreshed');
      expect(results.last.anchor,
          greaterThanOrEqualTo(const Duration(minutes: 32)));
      await coordinator.close();
    });

    test('duplicate fresh candidates terminate without a resolve loop',
        () async {
      var resolveCalls = 0;
      final initial = _candidate('initial');
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver =
              candidate.id == 'initial' ? _provedDriver() : _frozenDriver();
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async => _candidate('refreshed'),
        freshResolver: () async {
          resolveCalls += 1;
          return [_candidate('refreshed')];
        },
        startupTimeout: const Duration(milliseconds: 30),
      );
      await coordinator.open(
        candidates: [initial],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      await expectLater(
        coordinator.recover(
          failure: MobileLibVlcFailureKind.frozenVideo,
          observedPosition: const Duration(minutes: 31),
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.sourceExhausted,
          ),
        ),
      );
      expect(resolveCalls, 1);
      await coordinator.close();
    });

    test('runtime monitor owns one bounded stalled-video recovery', () async {
      final recovered = Completer<MobileLibVlcOpenResult>();
      final initial = _candidate('initial');
      final refreshed = _candidate('refreshed');
      final initialDriver = _provedDriver();
      final refreshedDriver = _provedDriver(31);
      var refreshCalls = 0;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver =
              candidate.id == 'initial' ? initialDriver : refreshedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async {
          refreshCalls += 1;
          return refreshed;
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [initial],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic monitored = coordinator;
      monitored.startHealthMonitoring(
        interval: const Duration(milliseconds: 5),
        hardStallAfter: const Duration(milliseconds: 20),
        onRecovered: (MobileLibVlcOpenResult result) {
          if (!recovered.isCompleted) recovered.complete(result);
        },
      );

      final result = await recovered.future.timeout(
        const Duration(milliseconds: 300),
      );
      expect(result.candidate.id, 'refreshed');
      expect(refreshCalls, 1);
      expect(initialDriver.disposeCount, 1);
      expect(coordinator.currentCandidate?.id, 'refreshed');
      await coordinator.close();
    });
  });

  group('MobileLibVlcCoordinator same-source relay seek replacement', () {
    test('explicit seek cancels a blocked runtime recovery before promotion',
        () async {
      const target = Duration(minutes: 12);
      final recoveryTransportStarted = Completer<void>();
      final releaseRecoveryTransport = Completer<void>();
      final oldDriver = _provedDriver();
      final seekDriver = _provedDriver(0);
      final oldTransport = _FakeTransport();
      final recoveryTransport = _FakeTransport();
      final seekTransport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 3,
          estimatedBufferedPosition: Duration(minutes: 14),
          timelineOffset: target,
        ),
      );
      var transportCreates = 0;
      var driverCreates = 0;
      var resolverCalls = 0;
      Future<MobileLibVlcOpenResult>? recovery;
      Future<void>? recoveryCancelled;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = driverCreates++ == 0 ? oldDriver : seekDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async {
          switch (transportCreates++) {
            case 0:
              return oldTransport;
            case 1:
              recoveryTransportStarted.complete();
              await releaseRecoveryTransport.future;
              return recoveryTransport;
            default:
              return seekTransport;
          }
        },
        currentRefresher: (candidate) async => candidate,
        freshResolver: () async {
          resolverCalls += 1;
          return const [];
        },
        startupTimeout: const Duration(milliseconds: 100),
      );
      addTearDown(() async {
        if (!releaseRecoveryTransport.isCompleted) {
          releaseRecoveryTransport.complete();
        }
        try {
          await recoveryCancelled?.timeout(const Duration(seconds: 1));
        } catch (_) {}
        await coordinator.close().timeout(const Duration(seconds: 1));
      });
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      recovery = coordinator.recover(
        failure: MobileLibVlcFailureKind.frozenVideo,
        observedPosition: const Duration(minutes: 30),
      );
      recoveryCancelled = expectLater(
        recovery,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      await recoveryTransportStarted.future.timeout(
        const Duration(seconds: 1),
      );

      final seek = coordinator.reopenCurrentSourceAt(
        anchor: target,
        wasPlaying: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        transportCreates,
        2,
        reason:
            'seek transport cannot stage before recovery cancellation settles',
      );
      expect(
        driverCreates,
        1,
        reason: 'seek driver cannot mount before recovery cancellation settles',
      );
      releaseRecoveryTransport.complete();
      await expectLater(seek, completes);
      final result = await seek.timeout(const Duration(seconds: 1));
      await recoveryCancelled.timeout(const Duration(seconds: 1));

      expect(result.anchor, greaterThanOrEqualTo(target));
      expect(result.anchor, lessThan(target + const Duration(seconds: 3)));
      expect(coordinator.currentDriver, same(seekDriver));
      expect(driverCreates, 2);
      expect(recoveryTransport.stopCount, 1);
      expect(oldDriver.disposeCount, 1);
      expect(oldTransport.stopCount, 1);
      expect(resolverCalls, 0);
    });

    test('keeps the proved controller alive until the anchor relay advances',
        () async {
      const target = Duration(minutes: 10);
      final candidateGate = Completer<void>();
      final oldDriver = _provedDriver();
      final candidateDriver = _FakeDriver(
        initializeGate: candidateGate,
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 80),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(minutes: 80),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1400),
            duration: Duration(minutes: 80),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final oldTransport = _FakeTransport();
      final candidateTransport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 3,
          estimatedBufferedPosition: Duration(minutes: 12),
          timelineOffset: target,
        ),
      );
      var driverCreates = 0;
      var resolverCalls = 0;
      final proofLifecycle = <String>[];
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = driverCreates++ == 0 ? oldDriver : candidateDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async =>
            anchor == target ? candidateTransport : oldTransport,
        freshResolver: () async {
          resolverCalls += 1;
          return const [];
        },
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final reopening = coordinator.reopenCurrentSourceAt(
        anchor: target,
        wasPlaying: true,
        onCandidateInitialized: (generation) async {
          proofLifecycle.add('candidate:$generation');
          expect(candidateDriver.initializeCount, 1);
          expect(candidateDriver.playCount, 0);
        },
        onCandidateRollback: (generation) async {
          proofLifecycle.add('rollback:$generation');
        },
        onBeforePreviousDispose: (result) async {
          expect(result.candidate.id, 'initial');
          expect(coordinator.currentDriver, same(candidateDriver));
          expect(oldDriver.disposeCount, 0);
          expect(oldTransport.stopCount, 0);
        },
      );
      await candidateDriver.created;
      expect(
        oldDriver.pauseCount,
        1,
        reason: 'The retained libVLC driver must yield playback authority '
            'while the staged seek driver proves decoded advancement.',
      );
      expect(oldDriver.disposeCount, 0);
      expect(oldTransport.stopCount, 0);
      candidateGate.complete();

      final result = await reopening;
      expect(result.candidate.id, 'initial');
      expect(result.anchor, greaterThanOrEqualTo(target));
      expect(result.anchor, lessThan(target + const Duration(seconds: 3)));
      expect(candidateDriver.seekPositions, isEmpty);
      expect(oldDriver.disposeCount, 1);
      expect(oldTransport.stopCount, 1);
      expect(resolverCalls, 0);
      expect(proofLifecycle, <String>['candidate:${result.generation}']);
      await coordinator.close();
    });

    test('failed anchor relay retains the proved controller and preseek anchor',
        () async {
      final oldDriver = _provedDriver();
      final failedDriver = _frozenDriver();
      final oldTransport = _FakeTransport();
      final failedTransport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 2,
          estimatedBufferedPosition: Duration(minutes: 12),
          timelineOffset: Duration(minutes: 10),
        ),
      );
      var driverCreates = 0;
      var resolverCalls = 0;
      final proofLifecycle = <String>[];
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = driverCreates++ == 0 ? oldDriver : failedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async =>
            anchor == const Duration(minutes: 10)
                ? failedTransport
                : oldTransport,
        freshResolver: () async {
          resolverCalls += 1;
          return const [];
        },
        startupTimeout: const Duration(milliseconds: 25),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      await expectLater(
        coordinator.reopenCurrentSourceAt(
          anchor: const Duration(minutes: 10),
          wasPlaying: true,
          onCandidateInitialized: (generation) async {
            proofLifecycle.add('candidate:$generation');
          },
          onCandidateRollback: (generation) async {
            proofLifecycle.add('rollback:$generation');
          },
        ),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.anchor,
            'rollback anchor',
            greaterThanOrEqualTo(const Duration(minutes: 30)),
          ),
        ),
      );

      expect(coordinator.currentDriver, same(oldDriver));
      expect(coordinator.currentCandidate?.id, 'initial');
      expect(oldDriver.pauseCount, 1);
      expect(
        oldDriver.playCount,
        2,
        reason: 'A failed seek must resume the retained proved driver.',
      );
      expect(oldDriver.disposeCount, 0);
      expect(oldTransport.stopCount, 0);
      expect(failedDriver.disposeCount, 1);
      expect(failedTransport.stopCount, 1);
      expect(resolverCalls, 0);
      expect(proofLifecycle, hasLength(2));
      expect(proofLifecycle.first, startsWith('candidate:'));
      expect(proofLifecycle.last, startsWith('rollback:'));
      await coordinator.close();
    });

    test('seek transport bytes cannot replace decoded advancing video proof',
        () async {
      const target = Duration(minutes: 42, seconds: 8);
      final oldDriver = _provedDriver(42);
      final transportOnlyDriver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(seconds: 24),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: false,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(seconds: 24),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: false,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1400),
            duration: Duration(seconds: 24),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: false,
          ),
        ],
      );
      final oldTransport = _FakeTransport();
      final transportOnly = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 512 * 1024,
          completedMediaSegments: 5,
          estimatedBufferedPosition: Duration(minutes: 42, seconds: 24),
          timelineOffset: target,
        ),
      );
      var driverCreates = 0;
      var promoted = false;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = driverCreates++ == 0 ? oldDriver : transportOnlyDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async =>
            anchor == target ? transportOnly : oldTransport,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 25),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 42),
        reason: MobileLibVlcOpenReason.resume,
      );
      await coordinator.seekTo(const Duration(minutes: 42, seconds: 23));

      await expectLater(
        coordinator.reopenCurrentSourceAt(
          anchor: target,
          wasPlaying: true,
          onBeforePreviousDispose: (_) async => promoted = true,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );

      expect(promoted, isFalse);
      expect(coordinator.currentDriver, same(oldDriver));
      expect(oldDriver.disposeCount, 0);
      expect(oldTransport.stopCount, 0);
      expect(transportOnlyDriver.disposeCount, 1);
      expect(transportOnly.stopCount, 1);
      await coordinator.close();
    });

    test('a newer anchor cancels an older same-source candidate', () async {
      const firstTarget = Duration(minutes: 10);
      const latestTarget = Duration(minutes: 20);
      final firstGate = Completer<void>();
      final oldDriver = _provedDriver();
      final firstDriver = _FakeDriver(
        initializeGate: firstGate,
        afterPlay: _provedDriver(0).afterPlay,
      );
      final latestDriver = _provedDriver(0);
      final oldTransport = _FakeTransport();
      final firstTransport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 3,
          estimatedBufferedPosition: Duration(minutes: 12),
          timelineOffset: firstTarget,
        ),
      );
      final latestTransport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 4096,
          completedMediaSegments: 3,
          estimatedBufferedPosition: Duration(minutes: 22),
          timelineOffset: latestTarget,
        ),
      );
      var driverCreates = 0;
      var resolverCalls = 0;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = switch (driverCreates++) {
            0 => oldDriver,
            1 => firstDriver,
            _ => latestDriver,
          };
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => switch (anchor) {
          firstTarget => firstTransport,
          latestTarget => latestTransport,
          _ => oldTransport,
        },
        freshResolver: () async {
          resolverCalls += 1;
          return const [];
        },
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final first = coordinator.reopenCurrentSourceAt(
        anchor: firstTarget,
        wasPlaying: true,
      );
      final firstCancelled = expectLater(
        first,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      await firstDriver.created;
      final latest = await coordinator.reopenCurrentSourceAt(
        anchor: latestTarget,
        wasPlaying: true,
      );
      firstGate.complete();

      await firstCancelled;
      expect(latest.anchor, greaterThanOrEqualTo(latestTarget));
      expect(
          latest.anchor, lessThan(latestTarget + const Duration(seconds: 3)));
      expect(firstDriver.disposeCount, 1);
      expect(firstTransport.stopCount, 1);
      expect(oldDriver.disposeCount, 1);
      expect(oldTransport.stopCount, 1);
      expect(coordinator.currentDriver, same(latestDriver));
      expect(resolverCalls, 0);
      await coordinator.close();
    });
  });

  group('MobileLibVlcCoordinator two-phase source switching', () {
    test('relay startup advances the anchor on the global media timeline',
        () async {
      const offset = Duration(minutes: 30);
      final driver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 60),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(minutes: 60),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 1400),
            duration: Duration(minutes: 60),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final transport = _FakeTransport(
        snapshot: const MobileLibVlcTransportSnapshot(
          totalMediaBytes: 1024,
          completedMediaSegments: 3,
          estimatedBufferedPosition: Duration(minutes: 31),
          timelineOffset: offset,
        ),
      );
      final coordinator = _coordinator(driver, transport);

      final result = await coordinator.open(
        candidates: [_candidate('relay')],
        anchor: offset,
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(
        result.anchor,
        const Duration(minutes: 30, milliseconds: 1400),
      );
      await coordinator.close();
    });

    test('saved-title open at 30 minutes never seeks to zero', () async {
      final driver = _provedDriver();
      final coordinator = _coordinator(driver, _FakeTransport());

      final result = await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(result.anchor, greaterThanOrEqualTo(const Duration(minutes: 30)));
      expect(driver.seekPositions, isNot(contains(Duration.zero)));
      expect(driver.seekPositions, contains(const Duration(minutes: 30)));
      await coordinator.close();
    });

    test('recovery at 30 minutes never opens a candidate at zero', () async {
      final initial = _provedDriver();
      final recovered = _provedDriver(31);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? initial : recovered;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        currentRefresher: (candidate) async => _candidate('recovered'),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      await coordinator.recover(
        failure: MobileLibVlcFailureKind.frozenVideo,
        observedPosition: const Duration(minutes: 30, seconds: 20),
      );

      expect(recovered.seekPositions, isNot(contains(Duration.zero)));
      expect(
        recovered.seekPositions,
        everyElement(
          greaterThanOrEqualTo(const Duration(minutes: 30, seconds: 20)),
        ),
      );
      await coordinator.close();
    });

    test('successful switch proves at the anchor then disposes old owners once',
        () async {
      final oldDriver = _provedDriver();
      final newDriver = _provedDriver(31);
      final oldTransport = _FakeTransport();
      final newTransport = _FakeTransport();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : newDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async =>
            candidate.id == 'initial' ? oldTransport : newTransport,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      final MobileLibVlcOpenResult result = await switchable.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 30, seconds: 40),
        wasPlaying: true,
      );

      expect(
        newDriver.seekPositions,
        everyElement(
          greaterThanOrEqualTo(const Duration(minutes: 30, seconds: 40)),
        ),
      );
      expect(result.candidate.id, 'selected');
      expect(result.anchor, greaterThanOrEqualTo(const Duration(minutes: 30)));
      expect(oldDriver.pauseCount, 1);
      expect(oldDriver.disposeCount, 1);
      expect(oldTransport.stopCount, 1);
      expect(newDriver.disposeCount, 0);
      expect(newTransport.stopCount, 0);
      await coordinator.close();
      expect(newDriver.disposeCount, 1);
      expect(newTransport.stopCount, 1);
    });

    test(
        'source switch creates replacement transport under its captured route owner',
        () async {
      final owner = MobilePlaybackRouteStartupOwner(
        generation: 41,
        startedAt: DateTime.now(),
      );
      final oldDriver = _provedDriver();
      final replacementDriver = _provedDriver(31);
      final replacementTransport = _FakeTransport();
      final createdCandidates = <String>[];
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          if (!owner.ownsAttempt(owner.generation)) {
            throw StateError('captured route owner was replaced');
          }
          createdCandidates.add('driver:${candidate.id}');
          final driver =
              candidate.id == 'initial' ? oldDriver : replacementDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async {
          if (!owner.ownsAttempt(owner.generation)) {
            throw StateError('captured route owner was replaced');
          }
          createdCandidates.add('transport:${candidate.id}');
          return candidate.id == 'initial'
              ? _FakeTransport()
              : replacementTransport;
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      owner.completeSuccessfully();

      final result = await coordinator.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 30, seconds: 15),
        wasPlaying: true,
        routeStartupRemainingBudget: () => owner.remainingWorkBudget,
        routeStartupCancellation: owner.whenCancelled,
      );

      expect(result.candidate.id, 'selected');
      expect(
          createdCandidates,
          containsAll(<String>[
            'driver:selected',
            'transport:selected',
          ]));
      expect(owner.ownsAttempt(owner.generation), isTrue);
      await coordinator.close();
      owner.dispose();
    });

    test('cancelled switch owner rejects replacement factory work', () async {
      final startupOwner = MobilePlaybackRouteStartupOwner(
        generation: 42,
        startedAt: DateTime.now(),
      )..completeSuccessfully();
      final switchOwner = MobilePlaybackRouteStartupOwner(
        generation: 43,
        startedAt: DateTime.now(),
      );
      final transportGate = Completer<MobileLibVlcTransport?>();
      final oldDriver = _provedDriver();
      var replacementFactoryStarted = false;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          if (!startupOwner.ownsAttempt(startupOwner.generation) ||
              !switchOwner.ownsAttempt(switchOwner.generation)) {
            throw StateError('switch owner is stale');
          }
          final driver =
              candidate.id == 'initial' ? oldDriver : _provedDriver();
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async {
          if (candidate.id == 'initial') return _FakeTransport();
          replacementFactoryStarted = true;
          return transportGate.future;
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(seconds: 1),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(seconds: 90),
        reason: MobileLibVlcOpenReason.resume,
      );

      final switching = coordinator.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(seconds: 105),
        wasPlaying: true,
        routeStartupRemainingBudget: () => switchOwner.remainingWorkBudget,
        routeStartupCancellation: switchOwner.whenCancelled,
      );
      await Future<void>.delayed(Duration.zero);
      switchOwner.dispose();

      await expectLater(switching, throwsA(isA<MobileLibVlcTerminalFailure>()));
      expect(replacementFactoryStarted, isTrue);
      transportGate.complete(_FakeTransport());
      await coordinator.close();
      startupOwner.dispose();
    });

    test(
        'switch after the old startup cutoff uses its new owner factory budget',
        () async {
      var oldElapsed = const Duration(seconds: 58);
      final startupOwner = MobilePlaybackRouteStartupOwner(
        generation: 44,
        startedAt: DateTime(2026, 8, 10),
        elapsed: () => oldElapsed,
      )..completeSuccessfully();
      oldElapsed = const Duration(seconds: 75);
      final switchOwner = MobilePlaybackRouteStartupOwner(
        generation: 45,
        startedAt: DateTime.now(),
      );
      final oldDriver = _provedDriver();
      final replacementDriver = _provedDriver(48);
      final replacementTransport = _FakeTransport();
      var replacementBuilt = false;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          if (candidate.id == 'initial') {
            oldDriver.markCreated();
            return oldDriver;
          }
          if (!switchOwner.ownsAttempt(switchOwner.generation)) {
            throw StateError('replacement switch owner is stale');
          }
          replacementBuilt = true;
          replacementDriver.markCreated();
          return replacementDriver;
        },
        transportFactory: (candidate, anchor) async =>
            candidate.id == 'initial' ? _FakeTransport() : replacementTransport,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 200),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 20),
        reason: MobileLibVlcOpenReason.resume,
      );

      expect(startupOwner.remainingWorkBudget, Duration.zero);
      final result = await coordinator.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 20, seconds: 15),
        wasPlaying: true,
        routeStartupRemainingBudget: () => switchOwner.remainingWorkBudget,
        routeStartupCancellation: switchOwner.whenCancelled,
      );

      expect(result.candidate.id, 'selected');
      expect(replacementBuilt, isTrue);
      await coordinator.close();
      startupOwner.dispose();
      switchOwner.dispose();
    });

    test('explicit source switch settles inside its route-owned budget',
        () async {
      final oldDriver = _provedDriver();
      final initializeGate = Completer<void>();
      final stalledDriver = _FakeDriver(initializeGate: initializeGate);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : stalledDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(seconds: 1),
      );
      final opened = await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(seconds: 1489),
        reason: MobileLibVlcOpenReason.resume,
      );
      final stopwatch = Stopwatch()..start();
      final dynamic switchable = coordinator;

      await expectLater(
        switchable
            .switchSource(
              candidate: _candidate('selected'),
              anchor: opened.anchor,
              wasPlaying: true,
              routeStartupRemainingBudget: () =>
                  const Duration(milliseconds: 20) - stopwatch.elapsed,
            )
            .timeout(const Duration(milliseconds: 120)),
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.anchor,
            'anchor',
            opened.anchor,
          ),
        ),
      );
      expect(oldDriver.disposeCount, 0);
      initializeGate.complete();
      await coordinator.close();
    });

    test('timed out source switch disposes a transport that completes late',
        () async {
      final oldDriver = _provedDriver();
      final lateTransport = _FakeTransport();
      final transportGate = Completer<MobileLibVlcTransport?>();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          oldDriver.markCreated();
          return oldDriver;
        },
        transportFactory: (candidate, anchor) async {
          if (candidate.id == 'initial') return _FakeTransport();
          return transportGate.future;
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(seconds: 1),
      );
      final opened = await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(seconds: 1489),
        reason: MobileLibVlcOpenReason.resume,
      );
      final stopwatch = Stopwatch()..start();

      await expectLater(
        coordinator.switchSource(
          candidate: _candidate('selected'),
          anchor: opened.anchor,
          wasPlaying: true,
          routeStartupRemainingBudget: () =>
              const Duration(milliseconds: 20) - stopwatch.elapsed,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );
      transportGate.complete(lateTransport);
      await Future<void>.delayed(Duration.zero);

      expect(lateTransport.stopCount, 1);
      expect(oldDriver.disposeCount, 0);
      await coordinator.close();
    });

    test('timed out source switch disposes a driver that completes late',
        () async {
      final oldDriver = _provedDriver();
      final lateDriver = _FakeDriver();
      final driverGate = Completer<MobileLibVlcDriver>();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          if (candidate.id == 'initial') {
            oldDriver.markCreated();
            return oldDriver;
          }
          return driverGate.future;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(seconds: 1),
      );
      final opened = await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(seconds: 1489),
        reason: MobileLibVlcOpenReason.resume,
      );
      final stopwatch = Stopwatch()..start();

      await expectLater(
        coordinator.switchSource(
          candidate: _candidate('selected'),
          anchor: opened.anchor,
          wasPlaying: true,
          routeStartupRemainingBudget: () =>
              const Duration(milliseconds: 20) - stopwatch.elapsed,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );
      driverGate.complete(lateDriver);
      await Future<void>.delayed(Duration.zero);

      expect(lateDriver.disposeCount, 1);
      expect(oldDriver.disposeCount, 0);
      await coordinator.close();
    });

    test('source switch reasserts the anchor after playback starts', () async {
      const anchor = Duration(minutes: 30, seconds: 40);
      final oldDriver = _provedDriver();
      final newDriver = _FakeDriver(
        ignoreSeekUntilPlay: true,
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration.zero,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(milliseconds: 700),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
        afterPlayingSeek: const [
          MobileLibVlcDriverSnapshot(
            position: anchor,
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 30, seconds: 40, milliseconds: 500),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 30, seconds: 41),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : newDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final result = await coordinator.switchSource(
        candidate: _candidate('selected'),
        anchor: anchor,
        wasPlaying: true,
      );

      expect(newDriver.seekPositions, [anchor, anchor]);
      expect(result.driver.position, greaterThanOrEqualTo(anchor));
      await coordinator.close();
    });

    test(
        'failed switch restores old playback and disposes only temporary owners',
        () async {
      final oldDriver = _provedDriver();
      final failedDriver = _frozenDriver();
      final oldTransport = _FakeTransport();
      final failedTransport = _FakeTransport();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : failedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async =>
            candidate.id == 'initial' ? oldTransport : failedTransport,
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 25),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      await expectLater(
        switchable.switchSource(
          candidate: _candidate('failed'),
          anchor: const Duration(minutes: 30, seconds: 45),
          wasPlaying: true,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );

      expect(oldDriver.disposeCount, 0);
      expect(oldTransport.stopCount, 0);
      expect(oldDriver.pauseCount, 1);
      expect(oldDriver.playCount, 2);
      expect(
        oldDriver.seekPositions.last,
        const Duration(minutes: 30, seconds: 45),
      );
      expect(failedDriver.disposeCount, 1);
      expect(failedTransport.stopCount, 1);
      await coordinator.close();
      expect(oldDriver.disposeCount, 1);
      expect(oldTransport.stopCount, 1);
    });

    test('failed switch resumes a retained session without a redundant seek',
        () async {
      final oldDriver = _FakeDriver(
        afterPlay: const [
          MobileLibVlcDriverSnapshot(
            position: Duration(minutes: 30, seconds: 44),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
          MobileLibVlcDriverSnapshot(
            position: Duration(
              minutes: 30,
              seconds: 44,
              milliseconds: 500,
            ),
            duration: Duration(minutes: 90),
            isPlaying: true,
            isBuffering: false,
            hasError: false,
            videoWidth: 1920,
            videoHeight: 1080,
            isInitialized: true,
            hasUsableVideoFrame: true,
          ),
        ],
      );
      final failedDriver = _frozenDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : failedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 25),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      oldDriver.emit(
        const MobileLibVlcDriverSnapshot(
          position: Duration(
            minutes: 30,
            seconds: 44,
            milliseconds: 500,
          ),
          duration: Duration(minutes: 90),
          isPlaying: true,
          isBuffering: false,
          hasError: false,
          videoWidth: 1920,
          videoHeight: 1080,
          isInitialized: true,
          hasUsableVideoFrame: true,
        ),
      );
      final seekCountBeforeSwitch = oldDriver.seekPositions.length;

      await expectLater(
        coordinator.switchSource(
          candidate: _candidate('failed'),
          anchor: const Duration(minutes: 30, seconds: 45),
          wasPlaying: true,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );

      expect(oldDriver.seekPositions.length, seekCountBeforeSwitch);
      expect(oldDriver.playCount, 2);
      await coordinator.close();
    });

    test('failed switch preserves paused intent without resuming old playback',
        () async {
      final oldDriver = _provedDriver();
      final failedDriver = _frozenDriver();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : failedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 25),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      await expectLater(
        switchable.switchSource(
          candidate: _candidate('failed'),
          anchor: const Duration(minutes: 30, seconds: 50),
          wasPlaying: false,
        ),
        throwsA(isA<MobileLibVlcTerminalFailure>()),
      );

      expect(oldDriver.pauseCount, greaterThanOrEqualTo(2));
      expect(oldDriver.playCount, 1);
      expect(
        oldDriver.seekPositions.last,
        const Duration(minutes: 30, seconds: 50),
      );
      await coordinator.close();
    });

    test('newer switch invalidates a stale temporary owner', () async {
      final firstGate = Completer<void>();
      final oldDriver = _provedDriver();
      final firstDriver = _FakeDriver(
        initializeGate: firstGate,
        afterPlay: _provedDriver(31).afterPlay,
      );
      final secondDriver = _provedDriver(32);
      final firstTransport = _FakeTransport();
      final secondTransport = _FakeTransport();
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = switch (candidate.id) {
            'initial' => oldDriver,
            'first' => firstDriver,
            _ => secondDriver,
          };
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => switch (candidate.id) {
          'first' => firstTransport,
          'second' => secondTransport,
          _ => _FakeTransport(),
        },
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      final first = switchable.switchSource(
        candidate: _candidate('first'),
        anchor: const Duration(minutes: 30, seconds: 10),
        wasPlaying: true,
      );
      final firstCancelled = expectLater(
        first,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      await firstDriver.created;
      final MobileLibVlcOpenResult second = await switchable.switchSource(
        candidate: _candidate('second'),
        anchor: const Duration(minutes: 30, seconds: 20),
        wasPlaying: true,
      );
      firstGate.complete();

      await firstCancelled;
      expect(second.candidate.id, 'second');
      expect(firstDriver.disposeCount, 1);
      expect(firstTransport.stopCount, 1);
      expect(secondDriver.disposeCount, 0);
      expect(secondTransport.stopCount, 0);
      await coordinator.close();
    });

    test('switch becoming stale during old-owner disposal cannot publish',
        () async {
      final oldDisposeGate = Completer<void>();
      final oldDriver = _provedDriver(30, oldDisposeGate);
      final firstDriver = _provedDriver(31);
      final secondDriver = _provedDriver(32);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = switch (candidate.id) {
            'initial' => oldDriver,
            'first' => firstDriver,
            _ => secondDriver,
          };
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final first = coordinator.switchSource(
        candidate: _candidate('first'),
        anchor: const Duration(minutes: 30, seconds: 10),
        wasPlaying: true,
      );
      while (oldDriver.disposeCount == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final second = await coordinator.switchSource(
        candidate: _candidate('second'),
        anchor: const Duration(minutes: 30, seconds: 20),
        wasPlaying: true,
      );
      oldDisposeGate.complete();

      await expectLater(
        first,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      expect(second.candidate.id, 'second');
      expect(coordinator.currentCandidate?.id, 'second');
      await coordinator.close();
    });

    test('stale switch rollback cannot control a newer switch owner', () async {
      final rollbackPlayGate = Completer<void>();
      final oldDriver = _provedDriver(30);
      final failingDriver = _FakeDriver(initializeError: StateError('fail'));
      final latestDriver = _provedDriver(32);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = switch (candidate.id) {
            'initial' => oldDriver,
            'failing' => failingDriver,
            _ => latestDriver,
          };
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 20),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      oldDriver.playGate = rollbackPlayGate;

      final first = coordinator.switchSource(
        candidate: _candidate('failing'),
        anchor: const Duration(minutes: 30, seconds: 10),
        wasPlaying: true,
      );
      final initialPlayCount = oldDriver.playCount;
      while (oldDriver.playCount == initialPlayCount) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final rollbackPlayCount = oldDriver.playCount;
      final second = coordinator.switchSource(
        candidate: _candidate('latest'),
        anchor: const Duration(minutes: 30, seconds: 20),
        wasPlaying: true,
      );
      rollbackPlayGate.complete();

      await expectLater(
        first,
        throwsA(
          isA<MobileLibVlcTerminalFailure>().having(
            (failure) => failure.kind,
            'kind',
            MobileLibVlcFailureKind.cancelled,
          ),
        ),
      );
      final result = await second;
      expect(result.candidate.id, 'latest');
      expect(oldDriver.playCount, rollbackPlayCount);
      expect(coordinator.currentCandidate?.id, 'latest');
      await coordinator.close();
    });

    test('promoted reopen survives previous owner disposal failure', () async {
      final oldDriver = _provedDriver(30, null, null, StateError('old'));
      final promotedDriver = _provedDriver(31);
      var driverCreates = 0;
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = driverCreates++ == 0 ? oldDriver : promotedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final result = await coordinator.reopenCurrentSourceAt(
        anchor: const Duration(minutes: 31),
        wasPlaying: true,
      );

      expect(result.anchor, greaterThanOrEqualTo(const Duration(minutes: 31)));
      expect(coordinator.currentDriver, same(promotedDriver));
      expect(promotedDriver.disposeCount, 0);
      await coordinator.close();
    });

    test('promoted switch survives previous owner disposal failure', () async {
      final oldDriver = _provedDriver(30, null, null, StateError('old'));
      final promotedDriver = _provedDriver(31);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : promotedDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final result = await coordinator.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 31),
        wasPlaying: true,
      );

      expect(result.candidate.id, 'selected');
      expect(coordinator.currentDriver, same(promotedDriver));
      expect(promotedDriver.disposeCount, 0);
      await coordinator.close();
    });

    test('manual backward seek becomes the next switch anchor', () async {
      final oldDriver = _provedDriver();
      final newDriver = _provedDriver(10);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : newDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );
      await coordinator.seekTo(const Duration(minutes: 10));

      final dynamic switchable = coordinator;
      await switchable.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 10),
        wasPlaying: true,
      );

      expect(
        newDriver.seekPositions,
        everyElement(const Duration(minutes: 10)),
      );
      expect(newDriver.seekPositions, isNot(contains(Duration.zero)));
      await coordinator.close();
    });

    test('explicit Start over may open at zero', () async {
      final driver = _provedDriver(0);
      final coordinator = _coordinator(driver, _FakeTransport());

      final result = await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: Duration.zero,
        reason: MobileLibVlcOpenReason.explicitStartOver,
      );

      expect(result.anchor, greaterThanOrEqualTo(Duration.zero));
      expect(driver.seekPositions, isEmpty);
      await coordinator.close();
    });

    test('manual source switch clamps a zero request to the credible anchor',
        () async {
      final oldDriver = _provedDriver();
      final newDriver = _provedDriver(31);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : newDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      await switchable.switchSource(
        candidate: _candidate('selected'),
        anchor: Duration.zero,
        wasPlaying: true,
      );

      expect(
        newDriver.seekPositions,
        everyElement(greaterThanOrEqualTo(const Duration(minutes: 30))),
      );
      expect(newDriver.seekPositions, everyElement(isNot(Duration.zero)));
      await coordinator.close();
    });

    test(
        'close after a successful switch disposes latest owners at latest anchor',
        () async {
      final oldDriver = _provedDriver();
      final newDriver = _provedDriver(31);
      final coordinator = MobileLibVlcCoordinator(
        driverFactory: (candidate, playbackUri) async {
          final driver = candidate.id == 'initial' ? oldDriver : newDriver;
          driver.markCreated();
          return driver;
        },
        transportFactory: (candidate, anchor) async => _FakeTransport(),
        freshResolver: () async => const [],
        startupTimeout: const Duration(milliseconds: 100),
      );
      await coordinator.open(
        candidates: [_candidate('initial')],
        anchor: const Duration(minutes: 30),
        reason: MobileLibVlcOpenReason.resume,
      );

      final dynamic switchable = coordinator;
      final MobileLibVlcOpenResult switched = await switchable.switchSource(
        candidate: _candidate('selected'),
        anchor: const Duration(minutes: 30, seconds: 30),
        wasPlaying: true,
      );
      await coordinator.close();

      expect(
          switched.anchor, greaterThanOrEqualTo(const Duration(minutes: 31)));
      expect(oldDriver.disposeCount, 1);
      expect(newDriver.disposeCount, 1);
      expect(newDriver.seekPositions, isNot(contains(Duration.zero)));
    });
  });

  test('coordinator has no Media3 or cross-engine dependency', () {
    final source = File(
      'lib/src/mobile_libvlc_coordinator.dart',
    ).readAsStringSync().toLowerCase();

    expect(source, isNot(contains('media3')));
    expect(source, isNot(contains('exoplayer')));
    expect(source, isNot(contains('nativeplaybackengine')));
  });
}

MobileLibVlcCoordinator _coordinator(
  _FakeDriver driver,
  _FakeTransport transport, {
  Duration startupTimeout = const Duration(milliseconds: 250),
}) {
  return MobileLibVlcCoordinator(
    driverFactory: (candidate, playbackUri) async {
      driver.markCreated();
      return driver;
    },
    transportFactory: (candidate, anchor) async => transport,
    freshResolver: () async => const [],
    startupTimeout: startupTimeout,
  );
}

MobileLibVlcSourceCandidate _candidate([String id = 'source-1']) {
  return MobileLibVlcSourceCandidate(
    id: id,
    mirrorGroup: '1080p',
    qualityLabel: '1080P',
    uri: Uri.parse('https://example.invalid/$id/master.m3u8'),
  );
}

MobileLibVlcSourceCandidate _transportCandidate(
  String id,
  String quality, {
  required String path,
  String query = 'session=expired',
  String mirror = 'mirror-a',
}) {
  return MobileLibVlcSourceCandidate(
    id: id,
    mirrorGroup: mirror,
    qualityLabel: quality,
    uri: Uri.parse('https://media.invalid/$path?$query'),
    headers: const <String, String>{
      'Referer': 'https://app.invalid/watch',
      'User-Agent': 'Juicr-Test',
    },
    providerId: 'anonymous-provider',
    requiresTransport: true,
  );
}

_FakeDriver _provedDriver([
  int minute = 30,
  Completer<void>? disposeGate,
  Completer<void>? seekGate,
  Object? disposeError,
  Completer<void>? playGate,
]) {
  final base = Duration(minutes: minute);
  return _FakeDriver(
    disposeGate: disposeGate,
    seekGate: seekGate,
    disposeError: disposeError,
    playGate: playGate,
    afterPlay: [
      MobileLibVlcDriverSnapshot(
        position: base,
        duration: const Duration(minutes: 90),
        isPlaying: true,
        isBuffering: false,
        hasError: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isInitialized: true,
        hasUsableVideoFrame: true,
      ),
      MobileLibVlcDriverSnapshot(
        position: base + const Duration(milliseconds: 700),
        duration: const Duration(minutes: 90),
        isPlaying: true,
        isBuffering: false,
        hasError: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isInitialized: true,
        hasUsableVideoFrame: true,
      ),
      MobileLibVlcDriverSnapshot(
        position: base + const Duration(milliseconds: 1400),
        duration: const Duration(minutes: 90),
        isPlaying: true,
        isBuffering: false,
        hasError: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isInitialized: true,
        hasUsableVideoFrame: true,
      ),
    ],
  );
}

_FakeDriver _frozenDriver() {
  return _FakeDriver(
    afterPlay: const [
      MobileLibVlcDriverSnapshot(
        position: Duration(minutes: 31),
        duration: Duration(minutes: 90),
        isPlaying: true,
        isBuffering: false,
        hasError: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isInitialized: true,
        hasUsableVideoFrame: true,
      ),
      MobileLibVlcDriverSnapshot(
        position: Duration(minutes: 31),
        duration: Duration(minutes: 90),
        isPlaying: true,
        isBuffering: false,
        hasError: false,
        videoWidth: 1920,
        videoHeight: 1080,
        isInitialized: true,
        hasUsableVideoFrame: true,
      ),
    ],
  );
}

final class _FakeDriver implements MobileLibVlcDriver {
  _FakeDriver({
    this.afterPlay = const [],
    this.afterPlayingSeek = const [],
    this.ignoreSeekUntilPlay = false,
    this.initializeGate,
    this.initializeError,
    this.disposeGate,
    this.seekGate,
    this.disposeError,
    this.playGate,
  });

  final List<MobileLibVlcDriverSnapshot> afterPlay;
  final List<MobileLibVlcDriverSnapshot> afterPlayingSeek;
  final bool ignoreSeekUntilPlay;
  final Completer<void>? initializeGate;
  final Object? initializeError;
  final Completer<void>? disposeGate;
  Completer<void>? seekGate;
  final Object? disposeError;
  Completer<void>? playGate;
  final StreamController<MobileLibVlcDriverSnapshot> _snapshots =
      StreamController<MobileLibVlcDriverSnapshot>.broadcast();
  final Completer<void> _created = Completer<void>();
  MobileLibVlcDriverSnapshot _snapshot =
      const MobileLibVlcDriverSnapshot.idle();
  int initializeCount = 0;
  int playCount = 0;
  int ensureAudioCount = 0;
  int pauseCount = 0;
  int disposeCount = 0;
  bool _disposed = false;
  bool _playStarted = false;
  bool audioEnsuredAfterPlay = false;
  final List<Duration> seekPositions = <Duration>[];

  Future<void> get created => _created.future;

  void markCreated() {
    if (!_created.isCompleted) {
      _created.complete();
    }
  }

  void emit(MobileLibVlcDriverSnapshot value) {
    _snapshot = value;
    if (!_snapshots.isClosed) {
      _snapshots.add(value);
    }
  }

  @override
  MobileLibVlcDriverSnapshot get snapshot => _snapshot;

  @override
  Stream<MobileLibVlcDriverSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> initialize() async {
    initializeCount += 1;
    if (initializeError != null) {
      throw initializeError!;
    }
    if (initializeGate != null) {
      await initializeGate!.future;
    }
  }

  @override
  Future<void> play() async {
    playCount += 1;
    if (playGate != null) {
      await playGate!.future;
    }
    _playStarted = true;
    for (final value in afterPlay) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      emit(value);
    }
  }

  @override
  Future<void> ensureSelectedAudioTrack() async {
    ensureAudioCount += 1;
    audioEnsuredAfterPlay = _playStarted;
  }

  @override
  Future<void> pause() async {
    pauseCount += 1;
  }

  @override
  Future<void> seekTo(Duration position) async {
    seekPositions.add(position);
    if (seekGate != null) {
      await seekGate!.future;
    }
    if (ignoreSeekUntilPlay && !_playStarted) return;
    emit(
      MobileLibVlcDriverSnapshot(
        position: position,
        duration: _snapshot.duration,
        isPlaying: _snapshot.isPlaying,
        isBuffering: _snapshot.isBuffering,
        hasError: _snapshot.hasError,
        videoWidth: _snapshot.videoWidth,
        videoHeight: _snapshot.videoHeight,
      ),
    );
    if (_playStarted) {
      for (final value in afterPlayingSeek) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        emit(value);
      }
    }
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    if (_disposed) return;
    _disposed = true;
    if (disposeGate != null) {
      await disposeGate!.future;
    }
    if (disposeError != null) {
      throw disposeError!;
    }
    await _snapshots.close();
  }
}

final class _FakeTransport implements MobileLibVlcTransport {
  _FakeTransport({
    MobileLibVlcTransportSnapshot snapshot =
        const MobileLibVlcTransportSnapshot.idle(),
  }) : _snapshot = snapshot;

  MobileLibVlcTransportSnapshot _snapshot;
  final StreamController<MobileLibVlcTransportSnapshot> _snapshots =
      StreamController<MobileLibVlcTransportSnapshot>.broadcast();
  int stopCount = 0;
  bool _stopped = false;

  void emit(MobileLibVlcTransportSnapshot value) {
    _snapshot = value;
    if (!_snapshots.isClosed) {
      _snapshots.add(value);
    }
  }

  @override
  MobileLibVlcTransportSnapshot get snapshot => _snapshot;

  @override
  Uri get playbackUri => Uri.parse('http://127.0.0.1:12345/master.m3u8');

  @override
  Stream<MobileLibVlcTransportSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<void> stop() async {
    stopCount += 1;
    if (_stopped) return;
    _stopped = true;
    await _snapshots.close();
  }
}
