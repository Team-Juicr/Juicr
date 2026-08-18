import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _ResponseBody = FutureOr<String> Function(Uri uri);

class _TestHttpOverrides extends HttpOverrides {
  _TestHttpOverrides(this.bodyFor);

  final _ResponseBody bodyFor;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _TestHttpClient(bodyFor);
  }
}

class _TestHttpClient implements HttpClient {
  _TestHttpClient(this.bodyFor);

  final _ResponseBody bodyFor;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _TestHttpRequest(url, bodyFor);
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _TestHttpRequest(url, bodyFor);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpRequest implements HttpClientRequest {
  _TestHttpRequest(this.url, this.bodyFor);

  final Uri url;
  final _ResponseBody bodyFor;

  @override
  final HttpHeaders headers = _TestHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return _TestHttpResponse(await bodyFor(url));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestHttpResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _TestHttpResponse(String body) : _bytes = utf8.encode(body);

  final List<int> _bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  HttpHeaders get headers => _TestHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpTvHome(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'tv_first_run_welcome_seen_v1': true,
  });
  await tester.binding.setSurfaceSize(const Size(1280, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const JuicrTvApp());
  await tester.pumpAndSettle();
}

String _catalogBody(List<Map<String, Object?>> items) {
  return jsonEncode({'items': items});
}

Map<String, Object?> _catalogItem(String id, String title) {
  return {
    'id': id,
    'type': 'movie',
    'name': title,
    'logo': 'https://images.invalid/$id.png',
  };
}

Future<void> _disposeTvHome(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _sendTvLogicalKey(
  WidgetTester tester,
  LogicalKeyboardKey logicalKey,
) async {
  if (logicalKey == LogicalKeyboardKey.gameButtonB) {
    await tester.sendKeyEvent(
      logicalKey,
      physicalKey: PhysicalKeyboardKey.gameButtonB,
    );
    return;
  }
  await tester.sendKeyEvent(
    logicalKey,
    platform: 'web',
    physicalKey: PhysicalKeyboardKey.browserBack,
  );
}

Future<void> _openSettingsSection(
  WidgetTester tester,
  String sectionTitle,
) async {
  await tester.tap(find.byIcon(Icons.settings_rounded).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(find.text(sectionTitle));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets(
      'selected navigation owns startup focus when Home has no focusable catalog content',
      (tester) async {
    await _pumpTvHome(tester);

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-Home');
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await _disposeTvHome(tester);
  });

  testWidgets(
      'Search Down from text entry keeps the search bar focused when results are empty',
      (tester) async {
    await _pumpTvHome(tester);

    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-search-bar');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-search-text');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-search-bar');
    await _disposeTvHome(tester);
  });

  testWidgets(
      'Search replacement restores the same keyed result after its old node is removed',
      (tester) async {
    final replacement = Completer<String>();
    final missingKeyReplacement = Completer<String>();
    final originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _TestHttpOverrides((uri) {
      if (uri.path != '/catalog') return '{}';
      final query = uri.queryParameters['search'];
      final type = uri.queryParameters['type'];
      if (type != 'movie') return _catalogBody(const []);
      if (query == 'one') {
        return _catalogBody([_catalogItem('target', 'Target result')]);
      }
      if (query == 'two') return replacement.future;
      if (query == 'three') return missingKeyReplacement.future;
      return _catalogBody(const []);
    });
    addTearDown(() => HttpOverrides.global = originalOverrides);
    await _pumpTvHome(tester);

    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.enterText(find.byType(EditableText), 'one');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Target result'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-search-results-first',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.enterText(find.byType(EditableText), 'two');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-search-results-first',
    );

    replacement.complete(
      _catalogBody([
        _catalogItem('other', 'Other result'),
        _catalogItem('target', 'Target result updated'),
      ]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Target result updated'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-grid-card-1');
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.enterText(find.byType(EditableText), 'three');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-grid-card-1');

    missingKeyReplacement.complete(
      _catalogBody([_catalogItem('fallback', 'Fallback result')]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Fallback result'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-search-results-first',
    );
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await _disposeTvHome(tester);
  });

  testWidgets(
      'diagnostic pending state keeps a visible enabled Back action focused',
      (tester) async {
    final diagnosticResponse = Completer<String>();
    final originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _TestHttpOverrides((uri) {
      if (uri.path.contains('diagnostic')) return diagnosticResponse.future;
      return '{}';
    });
    addTearDown(() => HttpOverrides.global = originalOverrides);
    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'About & Diagnostics');
    await tester.tap(find.text('Send diagnostic'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Send').last);
    await tester.pump();

    final primary = FocusManager.instance.primaryFocus;
    expect(primary?.debugLabel, 'tv-diagnostic-back');
    expect(primary?.context, isNotNull);
    expect(primary?.canRequestFocus, isTrue);
    expect(find.text('Back'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    diagnosticResponse.complete('{"ticketId":"late"}');
    await _disposeTvHome(tester);
  });

  testWidgets('About rows yield focus to a meaningful Back action',
      (tester) async {
    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'About & Diagnostics');
    await tester.tap(find.text('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
        FocusManager.instance.primaryFocus?.debugLabel, 'tv-info-dialog-back');
    expect(find.text('Back'), findsOneWidget);
    await _disposeTvHome(tester);
  });

  testWidgets(
      'General mature content toggle defaults off and retains remote focus',
      (tester) async {
    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'General');

    expect(find.text('Show mature content'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    for (var index = 0; index < 4; index += 1) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-settings-action-4',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('On'), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-settings-action-4',
    );
    expect(FocusManager.instance.primaryFocus?.context, isNotNull);
    await _disposeTvHome(tester);
  });

  testWidgets('Player Guide rows yield focus to intentional scroll controls',
      (tester) async {
    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'Playback');
    await tester.ensureVisible(find.text('Player guide'));
    await tester.pump();
    await tester.tap(find.text('Player guide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf('tv-info-dialog-scroll-down', 'tv-info-dialog-back'),
    );
    expect(find.text('Back'), findsOneWidget);
    await _disposeTvHome(tester);
  });

  testWidgets('changelog rows yield focus to intentional scroll controls',
      (tester) async {
    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'About & Diagnostics');
    await tester.tap(find.text('Check for updates'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Read changelog'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      anyOf('tv-changelog-scroll', 'tv-changelog-back'),
    );
    expect(find.text('Back'), findsOneWidget);
    await _disposeTvHome(tester);
  });

  testWidgets(
      'Updates dialog restores paused native download with primary focus and browser fallback',
      (tester) async {
    const updateChannel = MethodChannel('app.juicr.flutter/app_update');
    final invoked = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(updateChannel, (call) async {
      invoked.add(call.method);
      if (call.method == 'snapshot') {
        return {
          'stage': 'paused',
          'releaseTag': 'v2.0.0',
          'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
          'expectedSize': 100,
          'downloadedBytes': 50,
          'progressPermille': 500,
          'failure': null,
        };
      }
      if (call.method == 'platformInfo') {
        return {
          'sdkInt': 35,
          'abis': ['x86_64'],
          'canInstallPackages': true,
          'lane': 'tv',
        };
      }
      if (call.method == 'resume') {
        return {
          'stage': 'downloading',
          'releaseTag': 'v2.0.0',
          'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
          'expectedSize': 100,
          'downloadedBytes': 50,
          'progressPermille': 500,
          'failure': null,
        };
      }
      return {
        'stage': 'paused',
        'releaseTag': 'v2.0.0',
        'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
        'expectedSize': 100,
        'downloadedBytes': 50,
        'progressPermille': 500,
        'failure': null,
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, null);
    });

    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'About & Diagnostics');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tv-settings-action-1',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Resume download'), findsOneWidget);
    expect(find.text('Open release page'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-updates-primary');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(invoked, contains('resume'));
    expect(find.text('Pause download'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-updates-primary');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Pause download'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-settings-action-1');
    await _disposeTvHome(tester);
  });

  testWidgets(
      'Updates dialog moves focus when async state disables the focused action',
      (tester) async {
    const updateChannel = MethodChannel('app.juicr.flutter/app_update');
    const updateEvents = 'app.juicr.flutter/app_update_events';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(updateChannel, (call) async {
      if (call.method == 'platformInfo') {
        return {
          'sdkInt': 35,
          'abis': ['x86_64'],
          'canInstallPackages': true,
          'lane': 'tv',
        };
      }
      return {
        'stage': 'paused',
        'releaseTag': 'v2.0.0',
        'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
        'expectedSize': 100,
        'downloadedBytes': 50,
        'progressPermille': 500,
        'failure': null,
      };
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(updateChannel, null);
    });

    await _pumpTvHome(tester);
    await _openSettingsSection(tester, 'About & Diagnostics');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-updates-primary');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-updates-discard');

    final verifying = const StandardMethodCodec().encodeSuccessEnvelope({
      'stage': 'verifying',
      'releaseTag': 'v2.0.0',
      'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
      'expectedSize': 100,
      'downloadedBytes': 100,
      'progressPermille': 1000,
      'failure': null,
    });
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(updateEvents, verifying, (_) {});
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-updates-changelog');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _disposeTvHome(tester);
  });

  testWidgets('informational content cannot take remote focus', (tester) async {
    final informationalNode = FocusNode(debugLabel: 'informational');
    addTearDown(informationalNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: TvInformationalContent(
          child: Focus(
            focusNode: informationalNode,
            child: const Text('Nothing here yet'),
          ),
        ),
      ),
    );

    informationalNode.requestFocus();
    await tester.pump();

    expect(informationalNode.hasFocus, isFalse);
  });

  testWidgets('dialog focus restorer returns to the exact opener',
      (tester) async {
    final opener = FocusNode(debugLabel: 'account-action-4');
    final firstAction = FocusNode(debugLabel: 'account-action-0');
    addTearDown(opener.dispose);
    addTearDown(firstAction.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Focus(focusNode: firstAction, child: const Text('First action')),
            Focus(focusNode: opener, child: const Text('Delete account')),
          ],
        ),
      ),
    );
    opener.requestFocus();
    await tester.pump();
    final restorer = TvDialogFocusRestorer.capture();

    firstAction.requestFocus();
    await tester.pump();
    restorer.restore();
    await tester.pump();

    expect(opener.hasFocus, isTrue);
    expect(firstAction.hasFocus, isFalse);
  });

  testWidgets(
      'dialog focus owner assigns and recovers meaningful topmost focus',
      (tester) async {
    final firstAction = FocusNode(debugLabel: 'dialog-first-action');
    final secondAction = FocusNode(debugLabel: 'dialog-second-action');
    addTearDown(firstAction.dispose);
    addTearDown(secondAction.dispose);

    var showFirstAction = true;
    late StateSetter rebuildDialog;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => TvDialogFocusOwner(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuildDialog = setState;
                      return Dialog(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showFirstAction)
                              TextButton(
                                focusNode: firstAction,
                                onPressed: () {},
                                child: const Text('First action'),
                              ),
                            TextButton(
                              focusNode: secondAction,
                              onPressed: () {},
                              child: const Text('Second action'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            child: const Text('Open dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(firstAction.hasFocus, isTrue);

    rebuildDialog(() => showFirstAction = false);
    await tester.pumpAndSettle();
    expect(secondAction.hasFocus, isTrue);
  });

  testWidgets('parent dialog focus owner does not steal from a child route',
      (tester) async {
    final parentAction = FocusNode(debugLabel: 'parent-action');
    final childAction = FocusNode(debugLabel: 'child-action');
    addTearDown(parentAction.dispose);
    addTearDown(childAction.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (parentContext) => TvDialogFocusOwner(
                  child: Dialog(
                    child: TextButton(
                      focusNode: parentAction,
                      onPressed: () {
                        showDialog<void>(
                          context: parentContext,
                          builder: (_) => TvDialogFocusOwner(
                            child: Dialog(
                              child: TextButton(
                                focusNode: childAction,
                                onPressed: () {},
                                child: const Text('Child action'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open child'),
                    ),
                  ),
                ),
              );
            },
            child: const Text('Open parent'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open parent'));
    await tester.pumpAndSettle();
    expect(parentAction.hasFocus, isTrue);
    final parentRestorer = TvDialogFocusRestorer.capture();

    await tester.tap(find.text('Open child'));
    await tester.pumpAndSettle();
    expect(childAction.hasFocus, isTrue);

    parentRestorer.restore();
    await tester.pump();
    expect(childAction.hasFocus, isTrue);
  });

  testWidgets('dialog focus owner recovers an async re-enabled only action',
      (tester) async {
    final action = FocusNode(debugLabel: 'async-dialog-action');
    addTearDown(action.dispose);

    var enabled = true;
    late StateSetter rebuildDialog;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => TvDialogFocusOwner(
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      rebuildDialog = setState;
                      return Dialog(
                        child: TextButton(
                          focusNode: action,
                          onPressed: enabled ? () {} : null,
                          child: const Text('Send'),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            child: const Text('Open async dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open async dialog'));
    await tester.pumpAndSettle();
    expect(action.hasFocus, isTrue);

    rebuildDialog(() => enabled = false);
    await tester.pump();
    expect(action.hasFocus, isFalse);

    rebuildDialog(() => enabled = true);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(action.hasFocus, isTrue);
  });

  testWidgets('dialog inner layer consumes Back without popping its route',
      (tester) async {
    var returnedToParent = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => TvDialogFocusOwner(
                  child: TvDialogInnerLayer(
                    onBack: () => returnedToParent = true,
                    child: const Dialog(child: Text('Create list')),
                  ),
                ),
              );
            },
            child: const Text('Open list picker'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open list picker'));
    await tester.pumpAndSettle();
    expect(find.text('Create list'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(returnedToParent, isTrue);
    expect(find.text('Create list'), findsOneWidget);
  });

  test('dialog Back classifier includes every supported TV Back key', () {
    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.goBack,
      LogicalKeyboardKey.browserBack,
      LogicalKeyboardKey.navigateOut,
      LogicalKeyboardKey.gameButtonB,
    ]) {
      expect(tvIsDialogBackKey(key), isTrue, reason: key.keyLabel);
    }
    expect(tvIsDialogBackKey(LogicalKeyboardKey.arrowLeft), isFalse);
  });

  for (final key in <LogicalKeyboardKey>[
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
    LogicalKeyboardKey.navigateOut,
    LogicalKeyboardKey.gameButtonB,
  ]) {
    testWidgets('dialog route closes one layer for ${key.keyLabel}',
        (tester) async {
      final opener = FocusNode(debugLabel: 'route-opener');
      addTearDown(opener.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              focusNode: opener,
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => TvDialogRouteLayer(
                    child: TvDialogFocusOwner(
                      child: Dialog(
                        child: TextButton(
                          onPressed: () {},
                          child: const Text('Dialog action'),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open route dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open route dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog action'), findsOneWidget);

      await _sendTvLogicalKey(tester, key);
      await tester.pumpAndSettle();

      expect(find.text('Dialog action'), findsNothing);
    });
  }

  testWidgets(
      'rapid separate Back presses close one dialog layer and restore each opener',
      (tester) async {
    var pageBackCount = 0;
    final pageOpener = FocusNode(debugLabel: 'page-opener');
    final childOpener = FocusNode(debugLabel: 'child-opener');
    addTearDown(pageOpener.dispose);
    addTearDown(childOpener.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) pageBackCount += 1;
          },
          child: Builder(
            builder: (context) => TextButton(
              focusNode: pageOpener,
              onPressed: () async {
                final focusRestorer = TvDialogFocusRestorer.capture();
                await showDialog<void>(
                  context: context,
                  builder: (parentContext) => TvDialogRouteLayer(
                    child: TvDialogFocusOwner(
                      child: Dialog(
                        child: TextButton(
                          focusNode: childOpener,
                          onPressed: () async {
                            final childFocusRestorer =
                                TvDialogFocusRestorer.capture();
                            await showDialog<void>(
                              context: parentContext,
                              builder: (_) => const TvDialogRouteLayer(
                                child: TvDialogFocusOwner(
                                  child: Dialog(
                                    child: Text('Child dialog'),
                                  ),
                                ),
                              ),
                            );
                            childFocusRestorer.restore();
                          },
                          child: const Text('Open child dialog'),
                        ),
                      ),
                    ),
                  ),
                );
                focusRestorer.restore();
              },
              child: const Text('Open parent dialog'),
            ),
          ),
        ),
      ),
    );

    pageOpener.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open parent dialog'));
    await tester.pumpAndSettle();
    childOpener.requestFocus();
    await tester.pump();
    await tester.tap(find.text('Open child dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Child dialog'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Child dialog'), findsNothing);
    expect(find.text('Open child dialog'), findsOneWidget);
    expect(childOpener.hasFocus, isTrue);
    expect(pageBackCount, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Open child dialog'), findsNothing);
    expect(find.text('Open parent dialog'), findsOneWidget);
    expect(pageOpener.hasFocus, isTrue);
    expect(pageBackCount, 0);
  });

  testWidgets('platform Back closes one nested dialog route per dispatch',
      (tester) async {
    var pageBackCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) pageBackCount += 1;
          },
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (parentContext) => TvDialogRouteLayer(
                    child: TvDialogFocusOwner(
                      child: Dialog(
                        child: TextButton(
                          onPressed: () {
                            showDialog<void>(
                              context: parentContext,
                              builder: (_) => const TvDialogRouteLayer(
                                child: TvDialogFocusOwner(
                                  child: Dialog(child: Text('Platform child')),
                                ),
                              ),
                            );
                          },
                          child: const Text('Open platform child'),
                        ),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open platform parent'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open platform parent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open platform child'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Platform child'), findsNothing);
    expect(find.text('Open platform child'), findsOneWidget);
    expect(pageBackCount, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Open platform child'), findsNothing);
    expect(find.text('Open platform parent'), findsOneWidget);
    expect(pageBackCount, 0);
  });

  testWidgets('dialog form focus owner keeps directional focus in its layer',
      (tester) async {
    final field = FocusNode(debugLabel: 'list-name');
    final create = FocusNode(debugLabel: 'create-list');
    final back = FocusNode(debugLabel: 'back-to-lists');
    addTearDown(field.dispose);
    addTearDown(create.dispose);
    addTearDown(back.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvDialogFormFocusOwner(
            fieldFocusNode: field,
            actionFocusNodes: [create, back],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(focusNode: field),
                TextButton(
                  focusNode: create,
                  onPressed: () {},
                  child: const Text('Create'),
                ),
                TextButton(
                  focusNode: back,
                  onPressed: () {},
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    field.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(create.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(back.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(create.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(field.hasFocus, isTrue);
  });

  test('settings copy describes autoplay and reachable subtitle controls', () {
    expect(TvRemoteUxCopy.autoplayTitle, 'Autoplay next episode');
    expect(
      TvRemoteUxCopy.autoplaySubtitle.toLowerCase(),
      allOf(contains('automatically'), contains('episode finishes')),
    );
    expect(
      TvRemoteUxCopy.subtitleStyleSubtitle,
      'Configure caption size, color, and background.',
    );
    expect(TvRemoteUxCopy.subtitleStyleSubtitle.toLowerCase(),
        isNot(contains('delay')));
  });

  test('remote catalog identity disambiguates duplicate titles by year', () {
    expect(
      tvRemoteCatalogItemLabel(
        title: 'Bumblebee',
        year: '2018',
        imdbRating: '6.7',
      ),
      'IMDb\n6.7\n2018\nBumblebee',
    );
    expect(
      tvRemoteCatalogItemLabel(
        title: 'Bumblebee',
        year: null,
        imdbRating: null,
      ),
      'Bumblebee',
    );
  });

  test('player guide covers every reachable remote workflow', () {
    final guide = TvRemoteUxCopy.playerGuideLines
        .map((line) => '${line.title} ${line.description}'.toLowerCase())
        .join(' ');

    for (final term in [
      'reveal',
      'hud',
      'lock',
      'seekbar',
      'skip',
      'sources',
      'settings',
      'subtitle',
      'resume',
      'next episode',
      'back',
      'escape',
    ]) {
      expect(guide, contains(term), reason: 'missing player guide term: $term');
    }
    expect(guide, contains('only while the seekbar is focused'));
  });
}
