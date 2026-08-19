import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/mobile_playback_candidate_inventory.dart';
import 'package:juicr/src/native_player_page.dart';
import 'package:juicr/src/playback_provider.dart';

void main() {
  test(
      'terminal-invalidated controller callbacks remain rejected after a new page generation',
      () {
    final harness = NativePlayerPageLifecycleHarness();

    harness.recordAttach();
    harness.recordDetach();
    harness.recordAttach();
    harness.recordCallback(accepted: false);
    harness.recordCallback(accepted: false);

    expect(harness.attached, 2);
    expect(harness.detached, 1);
    expect(harness.acceptedCallbacks, 0);
    expect(harness.rejectedCallbacks, 2);
  });

  test('replacement factory cancellation cannot publish a switch result', () {
    final harness = NativePlayerPageLifecycleHarness();

    harness.recordSwitch(accepted: false);

    expect(harness.switchSuccessPublications, 0);
    expect(harness.staleSwitchRejections, 1);
  });

  test('superseded source switch catch cannot restore stale page state', () {
    final harness = NativePlayerPageLifecycleHarness();

    harness.recordSwitch(accepted: false);

    expect(harness.switchSuccessPublications, 0);
    expect(harness.staleSwitchRejections, 1);
  });

  testWidgets('player route primes the bounded retained candidate inventory', (
    tester,
  ) async {
    final harness = NativePlayerPageLifecycleHarness(skipInitialOpen: true);
    List<PlaybackSource> sources(String prefix, int count) => [
          for (var index = 0; index < count; index += 1)
            PlaybackSource(
              providerId: prefix,
              name: '$prefix-$index',
              url: 'https://example.invalid/$prefix/$index.m3u8',
            ),
        ];

    await tester.pumpWidget(
      MaterialApp(
        home: NativePlayerPage(
          title: 'Inventory control',
          sources: <NativePlaybackRequest>[
            NativePlaybackRequest(
              providerId: 'addon-control',
              sources: sources('addon-control', 10),
            ),
            NativePlaybackRequest(
              providerId: 'builtin-control',
              sources: sources('builtin-control', 10),
            ),
            NativePlaybackRequest(
              providerId: 'cached-control',
              sources: sources('cached-control', 3),
              candidateFamily: MobilePlaybackCandidateFamily.fallback,
            ),
          ],
          resolveProvider: (_, __) async => const <PlaybackSource>[],
          lifecycleHarness: harness,
        ),
      ),
    );
    await tester.pump();

    expect(harness.retainedCandidateCount?.call(), 17);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(harness.retainedCandidateCount, isNull);
  });
}
