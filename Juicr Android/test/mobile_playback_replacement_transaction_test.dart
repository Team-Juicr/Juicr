import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_replacement_transaction.dart';

void main() {
  test('retained owner callbacks are quarantined only while staging', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final retainedOwner = Object();
    final otherOwner = Object();

    final generation = transaction.stage(active: 'active', target: 'target');

    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: retainedOwner,
        retainedOwner: retainedOwner,
      ),
      isTrue,
    );
    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: otherOwner,
        retainedOwner: retainedOwner,
      ),
      isFalse,
    );

    transaction.promote(generation);

    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: retainedOwner,
        retainedOwner: retainedOwner,
      ),
      isFalse,
    );
  });

  test('rollback releases retained owner callback quarantine', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final retainedOwner = Object();
    final generation = transaction.stage(active: 'active', target: 'target');

    transaction.rollback(generation);

    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: retainedOwner,
        retainedOwner: retainedOwner,
      ),
      isFalse,
    );
  });

  test('reserved replacement quarantines callbacks before target creation', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final retainedOwner = Object();

    final generation = transaction.reserve(active: 'active');

    expect(transaction.isPreparing, isTrue);
    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: retainedOwner,
        retainedOwner: retainedOwner,
      ),
      isTrue,
    );
    expect(transaction.stagePrepared(generation, 'target'), isTrue);
    expect(transaction.isPreparing, isFalse);
    expect(transaction.isStaging, isTrue);
  });

  test('cancelled preparation releases retained owner callback quarantine', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final retainedOwner = Object();
    final generation = transaction.reserve(active: 'active');

    expect(transaction.cancelPreparation(generation), isTrue);

    expect(transaction.isPreparing, isFalse);
    expect(
      transaction.quarantinesRetainedOwnerCallback(
        callbackOwner: retainedOwner,
        retainedOwner: retainedOwner,
      ),
      isFalse,
    );
  });

  test('retains active playback until the staged target is promoted', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();

    final generation = transaction.stage(
      active: 'active',
      target: 'target',
    );

    expect(transaction.active, 'active');
    expect(transaction.staged, 'target');
    expect(transaction.visible, 'active');

    final retired = transaction.promote(generation);

    expect(retired, 'active');
    expect(transaction.active, 'target');
    expect(transaction.staged, isNull);
    expect(transaction.visible, 'target');
  });

  test('failed target rolls back without reopening retained playback', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final generation = transaction.stage(
      active: 'active',
      target: 'target',
    );

    final rejected = transaction.rollback(generation);

    expect(rejected, 'target');
    expect(transaction.active, 'active');
    expect(transaction.staged, isNull);
    expect(transaction.visible, 'active');
  });

  test('stale generations cannot promote or roll back a newer target', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final first = transaction.stage(active: 'active', target: 'first');
    expect(transaction.rollback(first), 'first');
    final second = transaction.stage(active: 'active', target: 'second');

    expect(transaction.promote(first), isNull);
    expect(transaction.rollback(first), isNull);
    expect(transaction.active, 'active');
    expect(transaction.staged, 'second');
    expect(transaction.owns(second, 'second'), isTrue);
  });

  test('new replacement retains a controller promoted by an older opening', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    final first = transaction.stage(active: 'original', target: 'promoted');
    expect(transaction.promote(first), 'original');

    transaction.stage(active: 'promoted', target: 'new-target');

    expect(transaction.retainsActive('promoted'), isTrue);
    expect(transaction.retainsActive('original'), isFalse);
    expect(transaction.retainsActive('new-target'), isFalse);
  });

  test('clear returns both owned slots for bounded disposal', () {
    final transaction = MobilePlaybackReplacementTransaction<String>();
    transaction.stage(active: 'active', target: 'target');

    expect(transaction.clear(), ['target', 'active']);
    expect(transaction.active, isNull);
    expect(transaction.staged, isNull);
  });
}
