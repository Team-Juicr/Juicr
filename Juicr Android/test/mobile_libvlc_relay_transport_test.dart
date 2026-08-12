import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_libvlc_models.dart';
import 'package:juicr/src/mobile_libvlc_relay_transport.dart';

void main() {
  group('MobileLibVlcTransportSnapshotController', () {
    test('publishes monotonic relay evidence without inventing media',
        () async {
      final clock = <DateTime>[
        DateTime.utc(2026, 7, 30, 1),
        DateTime.utc(2026, 7, 30, 1, 0, 1),
        DateTime.utc(2026, 7, 30, 1, 0, 2),
        DateTime.utc(2026, 7, 30, 1, 0, 3),
        DateTime.utc(2026, 7, 30, 1, 0, 4),
      ].iterator;
      DateTime now() {
        clock.moveNext();
        return clock.current;
      }

      final controller = MobileLibVlcTransportSnapshotController(now: now);
      final snapshots = <MobileLibVlcTransportSnapshot>[];
      final subscription = controller.snapshots.listen(snapshots.add);

      controller.recordTransportActivity();
      controller.recordTotalMediaBytes(4096);
      controller.recordCompletedMediaSegments(2);
      controller.recordBufferedPosition(const Duration(seconds: 18));
      controller.recordTimelineOffset(const Duration(minutes: 12));

      expect(controller.snapshot.totalMediaBytes, 4096);
      expect(controller.snapshot.completedMediaSegments, 2);
      expect(
        controller.snapshot.estimatedBufferedPosition,
        const Duration(seconds: 18),
      );
      expect(
        controller.snapshot.timelineOffset,
        const Duration(minutes: 12),
      );
      expect(controller.snapshot.lastByteAdvanceAt, isNotNull);
      expect(controller.snapshot.lastTransportActivityAt, isNotNull);
      expect(controller.snapshot.hasMediaProof, isTrue);
      expect(snapshots, hasLength(5));

      controller.recordTotalMediaBytes(1024);
      controller.recordCompletedMediaSegments(1);
      controller.recordBufferedPosition(const Duration(seconds: 4));

      expect(controller.snapshot.totalMediaBytes, 4096);
      expect(controller.snapshot.completedMediaSegments, 2);
      expect(
        controller.snapshot.estimatedBufferedPosition,
        const Duration(seconds: 18),
      );
      expect(snapshots, hasLength(5));

      await subscription.cancel();
      await controller.close();
    });

    test('publishes one terminal transport failure and then closes', () async {
      final controller = MobileLibVlcTransportSnapshotController();
      final snapshots = <MobileLibVlcTransportSnapshot>[];
      final subscription = controller.snapshots.listen(snapshots.add);

      controller.recordTerminalFailure(
        MobileLibVlcFailureKind.transportFailure,
      );
      controller.recordTerminalFailure(MobileLibVlcFailureKind.driverError);

      expect(
        controller.snapshot.terminalFailure,
        MobileLibVlcFailureKind.transportFailure,
      );
      expect(snapshots, hasLength(1));

      await controller.close();
      controller.recordTotalMediaBytes(9000);
      expect(controller.snapshot.totalMediaBytes, 0);

      await subscription.cancel();
    });

    test('classifies deterministic auth rejection without request details',
        () async {
      final controller = MobileLibVlcTransportSnapshotController();

      controller.recordTerminalFailure(
        MobileLibVlcFailureKind.transportFailure,
        failureClass:
            MobileLibVlcTransportFailureClass.authSessionUnreadable,
      );

      expect(
        controller.snapshot.terminalFailureClass,
        MobileLibVlcTransportFailureClass.authSessionUnreadable,
      );
      final diagnosticValue = controller.snapshot.terminalFailureClass!.name;
      expect(diagnosticValue, 'authSessionUnreadable');
      expect(diagnosticValue, isNot(contains('http')));
      expect(diagnosticValue, isNot(contains('header')));
      expect(diagnosticValue, isNot(contains('token')));
      await controller.close();
    });
  });
}
