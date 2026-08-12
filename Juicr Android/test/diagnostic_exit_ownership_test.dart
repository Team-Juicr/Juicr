import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:juicr/src/diagnostic_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object?> exitEntry({
  required String ownership,
  required String reason,
  required int timestamp,
  String? eventFingerprint,
}) {
  return <String, Object?>{
    'processOwnership': ownership,
    'reason': reason,
    'timestamp': timestamp,
    if (eventFingerprint != null) 'eventFingerprint': eventFingerprint,
  };
}

String fingerprint(String character) => character * 64;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('app.juicr.flutter/diagnostics'),
      null,
    );
  });

  Future<SharedPreferences> bootHistoricalSession({
    required String androidReason,
    required bool installChanged,
    String? eventFingerprint,
    bool installInfoAvailable = true,
    String? acknowledgedFingerprint,
  }) async {
    const channel = MethodChannel('app.juicr.flutter/diagnostics');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'processExitInfo') {
        if (androidReason == 'unavailable') return <Object?>[];
        return <Object?>[
          exitEntry(
            ownership: 'main_app',
            reason: androidReason,
            timestamp: 100,
            eventFingerprint: eventFingerprint,
          ),
        ];
      }
      if (call.method == 'installInfo') {
        if (!installInfoAvailable) return null;
        return <String, Object?>{
          'packageName': 'app.juicr.flutter',
          'versionName': installChanged ? 'next' : 'current',
          'versionCode': installChanged ? 2 : 1,
          'firstInstallTime': 10,
          'lastUpdateTime': installChanged ? 30 : 20,
        };
      }
      return null;
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'diagnostic_session_state': 'running',
      'diagnostic_session_id': 'old-session',
      'diagnostic_install_marker':
          'app.juicr.flutter|current|1|10|20',
      'diagnostic_native_engine_active': 'libvlc|active',
      if (acknowledgedFingerprint != null)
        'diagnostic_last_prompted_android_exit_event':
            acknowledgedFingerprint,
    });
    final prefs = await SharedPreferences.getInstance();
    final revision = DiagnosticLog.sessionRevision.value;
    await DiagnosticLog.initPersistentSession(prefs: prefs);
    while (DiagnosticLog.sessionRevision.value == revision) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    return prefs;
  }
  test('newer isolated exit cannot override older main user stop', () {
    final selected = selectLatestMainAndroidExitInfo(<Object?>[
      exitEntry(ownership: 'isolated_child', reason: 'other', timestamp: 20),
      exitEntry(ownership: 'main_app', reason: 'user_requested', timestamp: 10),
    ]);

    expect(selected['reason'], 'user_requested');
    final classification = classifyDiagnosticPreviousSessionExit(
      previousWasRunning: true,
      previousInstallChanged: false,
      androidReason: selected['reason']?.toString() ?? 'unavailable',
    );
    expect(classification, 'android_user_or_system_stop');
    expect(shouldPromptForDiagnosticPreviousExit(classification), isFalse);
  });

  test('newer isolated exit cannot hide older main crash', () {
    final selected = selectLatestMainAndroidExitInfo(<Object?>[
      exitEntry(ownership: 'isolated_child', reason: 'other', timestamp: 20),
      exitEntry(ownership: 'main_app', reason: 'crash', timestamp: 10),
    ]);

    expect(selected['reason'], 'crash');
    final classification = classifyDiagnosticPreviousSessionExit(
      previousWasRunning: true,
      previousInstallChanged: false,
      androidReason: selected['reason']?.toString() ?? 'unavailable',
    );
    expect(classification, 'app_crash');
    expect(shouldPromptForDiagnosticPreviousExit(classification), isTrue);
  });

  test('child-only exit history does not become an app crash prompt', () {
    final selected = selectLatestMainAndroidExitInfo(<Object?>[
      exitEntry(ownership: 'child', reason: 'crash', timestamp: 30),
      exitEntry(ownership: 'isolated_child', reason: 'other', timestamp: 20),
    ]);

    expect(selected, isEmpty);
    final classification = classifyDiagnosticPreviousSessionExit(
      previousWasRunning: true,
      previousInstallChanged: false,
      androidReason: 'unavailable',
    );
    expect(classification, 'android_exit_identity_unavailable');
    expect(shouldPromptForDiagnosticPreviousExit(classification), isFalse);
  });

  test('genuine newest main ANR prompts', () {
    final selected = selectLatestMainAndroidExitInfo(<Object?>[
      exitEntry(ownership: 'main_app', reason: 'anr', timestamp: 30),
      exitEntry(ownership: 'main_app', reason: 'user_requested', timestamp: 20),
    ]);

    expect(selected['reason'], 'anr');
    final classification = classifyDiagnosticPreviousSessionExit(
      previousWasRunning: true,
      previousInstallChanged: false,
      androidReason: selected['reason']?.toString() ?? 'unavailable',
    );
    expect(classification, 'app_anr');
    expect(shouldPromptForDiagnosticPreviousExit(classification), isTrue);
  });

  test('legacy unknown process identity is bounded and neutral', () {
    final selected = selectLatestMainAndroidExitInfo(<Object?>[
      <String, Object?>{'reason': 'crash', 'timestamp': 30},
      exitEntry(ownership: 'unknown', reason: 'anr', timestamp: 20),
    ]);

    expect(selected, isEmpty);
    final classification = classifyDiagnosticPreviousSessionExit(
      previousWasRunning: true,
      previousInstallChanged: false,
      androidReason: 'unavailable',
    );
    expect(shouldPromptForDiagnosticPreviousExit(classification), isFalse);
  });

  group('package replace native marker ownership', () {
    test('package replace plus user stop never falls back to native prompt',
        () async {
      final prefs = await bootHistoricalSession(
        androidReason: 'user_requested',
        installChanged: true,
      );

      expect(DiagnosticLog.previousInstallChanged, isTrue);
      expect(
        DiagnosticLog.previousSessionExit,
        'android_app_update_or_reinstall',
      );
      expect(DiagnosticLog.shouldShowCrashPrompt, isFalse);
      expect(prefs.getString('diagnostic_native_engine_active'), isNull);
    });

    test('package replace plus unavailable Android exit suppresses native prompt',
        () async {
      final prefs = await bootHistoricalSession(
        androidReason: 'unavailable',
        installChanged: true,
      );

      expect(DiagnosticLog.previousInstallChanged, isTrue);
      expect(
        DiagnosticLog.previousSessionExit,
        'android_app_update_or_reinstall',
      );
      expect(DiagnosticLog.shouldShowCrashPrompt, isFalse);
      expect(prefs.getString('diagnostic_native_engine_active'), isNull);
    });

    test('package replace preserves genuine new Android crash priority',
        () async {
      final event = fingerprint('9');
      final prefs = await bootHistoricalSession(
        androidReason: 'crash',
        installChanged: true,
        eventFingerprint: event,
      );

      expect(DiagnosticLog.previousSessionExit, 'app_crash');
      expect(DiagnosticLog.shouldShowCrashPrompt, isTrue);
      await DiagnosticLog.dismissCrashPrompt();
      expect(
        prefs.getString('diagnostic_last_prompted_android_exit_event'),
        event,
      );

      await bootHistoricalSession(
        androidReason: 'crash',
        installChanged: true,
        eventFingerprint: event,
        acknowledgedFingerprint: event,
      );
      expect(DiagnosticLog.shouldShowCrashPrompt, isFalse);
    });

    test('native marker still prompts when install did not change', () async {
      final prefs = await bootHistoricalSession(
        androidReason: 'user_requested',
        installChanged: false,
      );

      expect(DiagnosticLog.previousInstallChanged, isFalse);
      expect(DiagnosticLog.previousSessionExit, 'native_engine_interrupted');
      expect(DiagnosticLog.shouldShowCrashPrompt, isTrue);
      expect(prefs.getString('diagnostic_native_engine_active'), isNull);
    });

    test('unknown install marker keeps bounded legacy native fallback',
        () async {
      final prefs = await bootHistoricalSession(
        androidReason: 'user_requested',
        installChanged: false,
        installInfoAvailable: false,
      );

      expect(DiagnosticLog.previousInstallChanged, isFalse);
      expect(DiagnosticLog.previousSessionExit, 'native_engine_interrupted');
      expect(DiagnosticLog.shouldShowCrashPrompt, isTrue);
      expect(prefs.getString('diagnostic_native_engine_active'), isNull);
    });
  });

  group('historical Android exit event dedupe', () {
    test('same acknowledged exit never prompts across new sessions', () {
      final event = fingerprint('a');

      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'app_crash',
          eventFingerprint: event,
          acknowledgedFingerprint: event,
        ),
        isFalse,
      );
    });

    test('same acknowledged exit remains suppressed after package replace', () {
      final event = fingerprint('b');
      final classification = classifyDiagnosticPreviousSessionExit(
        previousWasRunning: true,
        previousInstallChanged: true,
        androidReason: 'crash',
      );

      expect(classification, 'app_crash');
      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: classification,
          eventFingerprint: event,
          acknowledgedFingerprint: event,
        ),
        isFalse,
      );
    });

    test('dismiss and successful send acknowledge the same event identity', () {
      final event = fingerprint('c');

      expect(
        acknowledgedDiagnosticAndroidExitFingerprint(
          selectedEventFingerprint: event,
        ),
        event,
      );
      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'app_crash',
          eventFingerprint: event,
          acknowledgedFingerprint:
              acknowledgedDiagnosticAndroidExitFingerprint(
            selectedEventFingerprint: event,
          ),
        ),
        isFalse,
      );
    });

    test('newer crash prompts after an acknowledged older crash', () {
      final oldEvent = fingerprint('d');
      final newEvent = fingerprint('e');

      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'app_crash',
          eventFingerprint: newEvent,
          acknowledgedFingerprint: oldEvent,
        ),
        isTrue,
      );
    });

    test('identical reason with a different timestamp remains a new event', () {
      final selected = selectLatestMainAndroidExitInfo(<Object?>[
        exitEntry(
          ownership: 'main_app',
          reason: 'crash',
          timestamp: 20,
          eventFingerprint: fingerprint('f'),
        ),
        exitEntry(
          ownership: 'main_app',
          reason: 'crash',
          timestamp: 10,
          eventFingerprint: fingerprint('0'),
        ),
      ]);

      expect(selected['eventFingerprint'], fingerprint('f'));
      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'app_crash',
          eventFingerprint: selected['eventFingerprint']!.toString(),
          acknowledgedFingerprint: fingerprint('0'),
        ),
        isTrue,
      );
    });

    test('child unknown and legacy missing fingerprints fail closed', () {
      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'app_crash',
          eventFingerprint: '',
          acknowledgedFingerprint: null,
        ),
        isFalse,
      );
      expect(
        shouldPromptForDiagnosticAndroidExit(
          classification: 'android_exit_identity_unavailable',
          eventFingerprint: fingerprint('1'),
          acknowledgedFingerprint: null,
        ),
        isFalse,
      );
    });

    test('legacy session dedupe remains independent for native-only exits', () {
      expect(
        shouldPromptForDiagnosticSessionExit(
          classification: 'native_engine_interrupted',
          previousSessionId: 'session-a',
          promptedSessionId: 'session-a',
        ),
        isFalse,
      );
      expect(
        shouldPromptForDiagnosticSessionExit(
          classification: 'native_engine_interrupted',
          previousSessionId: 'session-b',
          promptedSessionId: 'session-a',
        ),
        isTrue,
      );
    });

    test('private fingerprint never enters reports or diagnostic events', () {
      final source = File('lib/src/diagnostic_log.dart').readAsStringSync();
      final reportStart = source.indexOf('static String report()');
      final uploadStart = source.indexOf('static String uploadReport()');
      final reportBody = source.substring(reportStart, uploadStart);
      final addBody = source.substring(
        source.indexOf('static void add(String message)'),
        source.indexOf('static Future<void> initPersistentSession'),
      );

      expect(reportBody.toLowerCase(), isNot(contains('fingerprint')));
      expect(addBody.toLowerCase(), isNot(contains('fingerprint')));
    });

    test('dismiss persists event acknowledgment across a fresh app session',
        () async {
      final event = fingerprint('a');
      const channel = MethodChannel('app.juicr.flutter/diagnostics');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'processExitInfo') {
          return <Object?>[
            exitEntry(
              ownership: 'main_app',
              reason: 'crash',
              timestamp: 100,
              eventFingerprint: event,
            ),
          ];
        }
        if (call.method == 'installInfo') {
          return <String, Object?>{
            'packageName': 'app.juicr.flutter',
            'versionName': 'test',
            'versionCode': 1,
            'firstInstallTime': 10,
            'lastUpdateTime': 20,
          };
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        'diagnostic_session_state': 'running',
        'diagnostic_session_id': 'old-session',
        'diagnostic_install_marker': 'app.juicr.flutter|test|1|10|20',
      });
      final prefs = await SharedPreferences.getInstance();

      var revision = DiagnosticLog.sessionRevision.value;
      await DiagnosticLog.initPersistentSession(prefs: prefs);
      while (DiagnosticLog.sessionRevision.value == revision) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(DiagnosticLog.shouldShowCrashPrompt, isTrue);
      await DiagnosticLog.dismissCrashPrompt();
      expect(
        prefs.getString('diagnostic_last_prompted_android_exit_event'),
        event,
      );

      revision = DiagnosticLog.sessionRevision.value;
      await DiagnosticLog.initPersistentSession(prefs: prefs);
      while (DiagnosticLog.sessionRevision.value == revision) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(DiagnosticLog.shouldShowCrashPrompt, isFalse);
    });
  });
}
