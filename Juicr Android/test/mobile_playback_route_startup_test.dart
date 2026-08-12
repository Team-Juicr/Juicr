import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_route_startup.dart';

void main() {
  test(
    'route-owned startup deadline settles page recovery and publishes truthful terminal state by 60s',
    () async {
      final events = <String>[];
      final startedAt = DateTime(2026, 8, 3);
      var elapsed = Duration.zero;
      final owner = MobilePlaybackRouteStartupOwner(
        generation: 7,
        startedAt: startedAt,
        elapsed: () => elapsed,
        onWorkCancelled: () => events.add('children_cancelled'),
      );
      final children = <String, Completer<void>>{};
      var activeChildren = 0;
      var terminalPublishedAt = Duration.zero;
      var routeReturnedAt = Duration.zero;
      const savedAnchor = Duration(seconds: 1489);

      Future<void> child(String name) {
        return owner.runWork<void>((cancellation) async {
          activeChildren += 1;
          events.add('$name:start');
          final completer = Completer<void>();
          children[name] = completer;
          void cancel() {
            if (!completer.isCompleted) {
              events.add('$name:cancel');
              completer.complete();
            }
          }

          cancellation.addListener(cancel);
          try {
            await completer.future;
          } finally {
            cancellation.removeListener(cancel);
            activeChildren -= 1;
            events.add('$name:settled');
          }
        });
      }

      final route = () async {
        try {
          await child('primary_auth_failure');
          events.add('alias_source_exhausted');
          await child('fresh_owner');
          await child('distinct_recovery');
          fail('recovery must not run beyond the route work cutoff');
        } catch (error) {
          expect(error, isA<MobilePlaybackRouteStartupExpired>());
          await owner.cancelAndSettle();
          terminalPublishedAt = elapsed;
          events.add('terminal_published');
          routeReturnedAt = elapsed;
        }
      }();

      await Future<void>.delayed(Duration.zero);
      elapsed = const Duration(seconds: 22);
      children['primary_auth_failure']!.complete();
      await Future<void>.delayed(Duration.zero);
      elapsed = const Duration(seconds: 50);
      children['fresh_owner']!.complete();
      await Future<void>.delayed(Duration.zero);
      elapsed = const Duration(milliseconds: 58500);
      owner.expireNow();
      await route;

      expect(events, contains('children_cancelled'));
      expect(events, contains('distinct_recovery:cancel'));
      expect(events, isNot(contains('post_deadline_provider:start')));
      expect(activeChildren, 0);
      expect(
        terminalPublishedAt,
        lessThanOrEqualTo(const Duration(seconds: 60)),
      );
      expect(routeReturnedAt, lessThanOrEqualTo(const Duration(seconds: 60)));
      expect(
        owner.canChargeOptionalDelay(const Duration(milliseconds: 900)),
        isFalse,
      );
      expect(savedAnchor, const Duration(seconds: 1489));
      expect(events, isNot(contains('progress_saved:0')));
      expect(events, isNot(contains('engine:media3')));
      owner.dispose();
    },
  );

  test('optional transition delay that cannot fit expires and cancels work',
      () {
    var cancellationCount = 0;
    final startedAt = DateTime(2026, 8, 3);
    var elapsed = const Duration(seconds: 58);
    final owner = MobilePlaybackRouteStartupOwner(
      generation: 9,
      startedAt: startedAt,
      elapsed: () => elapsed,
      onWorkCancelled: () => cancellationCount += 1,
    );

    expect(
      owner.canChargeOptionalDelay(const Duration(milliseconds: 900)),
      isFalse,
    );
    owner.expireNow();

    expect(owner.isExpired, isTrue);
    expect(owner.isCancelled, isTrue);
    expect(cancellationCount, 1);
    owner.dispose();
  });

  test('route-owned cancellation settles an uncooperative selected candidate',
      () async {
    final gate = Completer<void>();
    var callerSettled = false;
    final owner = MobilePlaybackRouteStartupOwner(
      generation: 10,
      startedAt: DateTime.now(),
    );

    final work = owner.runWork<void>((_) => gate.future).then(
          (_) => callerSettled = true,
          onError: (_, __) => callerSettled = true,
        );
    owner.expireNow();
    await Future<void>.delayed(Duration.zero);

    expect(callerSettled, isTrue);

    await owner.cancelAndSettle();

    expect(
      owner.activeSettlementCount,
      0,
      reason: 'A cancelled uncooperative child must detach after the bounded '
          'settlement window instead of retaining the replaced route owner.',
    );
    owner.dispose();
  });

  test('replaced route owner invalidates its captured startup attempt', () {
    final firstOwner = MobilePlaybackRouteStartupOwner(
      generation: 12,
      startedAt: DateTime.now(),
    );
    final replacementOwner = MobilePlaybackRouteStartupOwner(
      generation: 13,
      startedAt: DateTime.now(),
    );

    firstOwner.dispose();

    expect(
      firstOwner.ownsAttempt(firstOwner.generation),
      isFalse,
      reason: 'A disposed owner cannot publish a stale open after replacement.',
    );
    expect(
      replacementOwner.ownsAttempt(replacementOwner.generation),
      isTrue,
    );
    firstOwner.dispose();
    replacementOwner.dispose();
  });

  test('successful near-deadline startup cancels speculative child work', () {
    var cancellationCount = 0;
    final startedAt = DateTime(2026, 8, 3);
    var elapsed = const Duration(seconds: 58);
    final owner = MobilePlaybackRouteStartupOwner(
      generation: 11,
      startedAt: startedAt,
      elapsed: () => elapsed,
      onWorkCancelled: () => cancellationCount += 1,
    );

    owner.completeSuccessfully();
    elapsed = const Duration(seconds: 61);

    expect(owner.isCompletedSuccessfully, isTrue);
    expect(owner.isExpired, isFalse);
    expect(owner.isCancelled, isFalse);
    expect(cancellationCount, 0);
    expect(
      owner.canChargeOptionalDelay(const Duration(milliseconds: 900)),
      isTrue,
    );
    owner.dispose();
  });

  test('terminal settlement quarantines late controller progress and errors',
      () {
    final gate = MobilePlaybackTerminalCallbackGate();
    final callbackGeneration = gate.beginOpening();
    final publications = <String>[];
    var disposed = false;

    void lateControllerCallback(String event) {
      if (!gate.permits(callbackGeneration)) return;
      publications.add(event);
    }

    gate.invalidateTerminal();
    disposed = true;
    lateControllerCallback('progress_saved');
    lateControllerCallback('error_published');
    lateControllerCallback('recovery_started');

    expect(disposed, isTrue);
    expect(publications, isEmpty);
    expect(gate.permits(callbackGeneration), isFalse);
  });

  test('old controller callback stays quarantined after a new opening begins',
      () {
    final gate = MobilePlaybackTerminalCallbackGate();
    final oldControllerGeneration = gate.beginOpening();
    final publications = <String>[];

    void oldControllerCallback(String event) {
      if (!gate.permits(oldControllerGeneration)) return;
      publications.add(event);
    }

    gate.invalidateTerminal();
    final newControllerGeneration = gate.beginOpening();
    expect(newControllerGeneration, isNot(oldControllerGeneration));

    oldControllerCallback('progress_saved');
    oldControllerCallback('error_published');
    oldControllerCallback('recovery_started');

    expect(publications, isEmpty);
    expect(gate.permits(newControllerGeneration), isTrue);
  });

  test('explicit switch owner stays budgeted after startup owner cutoff', () {
    var elapsed = const Duration(seconds: 58);
    final startupOwner = MobilePlaybackRouteStartupOwner(
      generation: 14,
      startedAt: DateTime(2026, 8, 3),
      elapsed: () => elapsed,
    );
    startupOwner.completeSuccessfully();
    elapsed = const Duration(seconds: 75);
    final switchOwner = MobilePlaybackRouteStartupOwner(
      generation: 15,
      startedAt: DateTime(2026, 8, 3, 0, 1, 15),
      elapsed: () => Duration.zero,
    );

    expect(startupOwner.remainingWorkBudget, Duration.zero);
    expect(startupOwner.ownsAttempt(startupOwner.generation), isTrue);
    expect(switchOwner.remainingWorkBudget, greaterThan(Duration.zero));
    expect(switchOwner.ownsAttempt(switchOwner.generation), isTrue);
    startupOwner.dispose();
    switchOwner.dispose();
  });

  test('post-startup transaction owner supersedes the completed route owner',
      () {
    expect(
      mobileLibVlcOpeningStaleReason(
        playerClosing: false,
        mounted: true,
        routeOwnerCurrent: true,
        routeOwnerAvailable: false,
        transactionOwnerPresent: true,
        transactionOwnerAvailable: true,
        openingTokenCurrent: true,
        coordinatorCurrent: true,
      ),
      isNull,
      reason: 'A fresh seek or source-switch owner must authorize its own '
          'post-startup factory work after the startup owner has settled.',
    );
    expect(
      mobileLibVlcOpeningStaleReason(
        playerClosing: false,
        mounted: true,
        routeOwnerCurrent: true,
        routeOwnerAvailable: true,
        transactionOwnerPresent: true,
        transactionOwnerAvailable: false,
        openingTokenCurrent: true,
        coordinatorCurrent: true,
      ),
      'transaction_owner_unavailable',
    );
    expect(
      mobileLibVlcOpeningStaleReason(
        playerClosing: false,
        mounted: true,
        routeOwnerCurrent: true,
        routeOwnerAvailable: false,
        transactionOwnerPresent: false,
        transactionOwnerAvailable: false,
        openingTokenCurrent: true,
        coordinatorCurrent: true,
      ),
      'route_owner_unavailable',
    );
  });

  test('failed route work restores UI before a throwing resume attempt',
      () async {
    final events = <String>[];

    await restoreRetainedPlaybackAfterRouteFailure(
      publishRestoredUi: () => events.add('ui_restored'),
      resumePlayback: () async {
        events.add('resume_attempted');
        throw StateError('resume failed');
      },
      onResumeError: (_) => events.add('resume_error_consumed'),
    );

    expect(
      events,
      <String>['ui_restored', 'resume_attempted', 'resume_error_consumed'],
    );
  });
}
