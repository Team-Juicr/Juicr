import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/native_player_page.dart';

void main() {
  test('terminal-invalidated controller callbacks remain rejected after a new page generation', () {
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
}
