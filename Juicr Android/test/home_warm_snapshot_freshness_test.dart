import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/home_page.dart';

void main() {
  final now = DateTime.utc(2026, 8, 12, 6);

  test('accepts a server-owned Home snapshot inside the bounded age', () {
    expect(
      homeWarmSnapshotIsFresh(
        now.subtract(const Duration(hours: 23)).toIso8601String(),
        now: now,
      ),
      isTrue,
    );
  });

  test('rejects expired, malformed, missing, and future snapshots', () {
    expect(
      homeWarmSnapshotIsFresh(
        now.subtract(const Duration(hours: 25)).toIso8601String(),
        now: now,
      ),
      isFalse,
    );
    expect(homeWarmSnapshotIsFresh('not-a-date', now: now), isFalse);
    expect(homeWarmSnapshotIsFresh(null, now: now), isFalse);
    expect(
      homeWarmSnapshotIsFresh(
        now.add(const Duration(seconds: 1)).toIso8601String(),
        now: now,
      ),
      isFalse,
    );
  });
}
