import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tv_release_update_assets.dart';

enum TvNativeUpdateStage {
  idle,
  available,
  downloading,
  paused,
  verifying,
  readyToInstall,
  awaitingPermission,
  installing,
  awaitingConfirmation,
  installed,
  failed,
}

enum TvNativeUpdateActionKind {
  none,
  start,
  pause,
  resume,
  install,
  openPermissionSettings,
}

class TvNativeUpdateAction {
  const TvNativeUpdateAction({
    required this.kind,
    required this.label,
    required this.enabled,
  });

  final TvNativeUpdateActionKind kind;
  final String label;
  final bool enabled;

  @override
  bool operator ==(Object other) =>
      other is TvNativeUpdateAction &&
      other.kind == kind &&
      other.label == label &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(kind, label, enabled);
}

TvNativeUpdateAction tvNativeUpdateActionFor({
  required TvNativeUpdateSnapshot snapshot,
  required bool updateAvailable,
  required bool hasVerifiedAsset,
}) {
  switch (snapshot.stage) {
    case TvNativeUpdateStage.downloading:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.pause,
        label: 'Pause download',
        enabled: true,
      );
    case TvNativeUpdateStage.paused:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.resume,
        label: 'Resume download',
        enabled: true,
      );
    case TvNativeUpdateStage.verifying:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.none,
        label: 'Verifying update...',
        enabled: false,
      );
    case TvNativeUpdateStage.readyToInstall:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.install,
        label: 'Install update',
        enabled: true,
      );
    case TvNativeUpdateStage.awaitingPermission:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.openPermissionSettings,
        label: 'Allow installation',
        enabled: true,
      );
    case TvNativeUpdateStage.installing:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.none,
        label: 'Installing...',
        enabled: false,
      );
    case TvNativeUpdateStage.awaitingConfirmation:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.none,
        label: 'Confirm installation',
        enabled: false,
      );
    case TvNativeUpdateStage.installed:
      return const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.none,
        label: 'Update installed',
        enabled: false,
      );
    case TvNativeUpdateStage.failed:
      if (updateAvailable && hasVerifiedAsset) {
        return const TvNativeUpdateAction(
          kind: TvNativeUpdateActionKind.start,
          label: 'Retry download',
          enabled: true,
        );
      }
      break;
    case TvNativeUpdateStage.idle:
    case TvNativeUpdateStage.available:
      break;
  }
  if (!updateAvailable) {
    return const TvNativeUpdateAction(
      kind: TvNativeUpdateActionKind.none,
      label: 'Up to date',
      enabled: false,
    );
  }
  if (!hasVerifiedAsset) {
    return const TvNativeUpdateAction(
      kind: TvNativeUpdateActionKind.none,
      label: 'Verified download unavailable',
      enabled: false,
    );
  }
  return const TvNativeUpdateAction(
    kind: TvNativeUpdateActionKind.start,
    label: 'Download update',
    enabled: true,
  );
}

class TvNativeUpdateSnapshot {
  const TvNativeUpdateSnapshot({
    required this.stage,
    this.releaseTag,
    this.assetName,
    this.expectedSize = 0,
    this.downloadedBytes = 0,
    this.progressPermille = 0,
    this.failure,
  });

  final TvNativeUpdateStage stage;
  final String? releaseTag;
  final String? assetName;
  final int expectedSize;
  final int downloadedBytes;
  final int progressPermille;
  final String? failure;

  static const _exactKeys = {
    'stage',
    'releaseTag',
    'assetName',
    'expectedSize',
    'downloadedBytes',
    'progressPermille',
    'failure',
  };

  static TvNativeUpdateSnapshot? tryParse(Object? value) {
    if (value is! Map || !setEquals(value.keys.toSet(), _exactKeys)) {
      return null;
    }
    final stageName = value['stage'];
    final expectedSize = value['expectedSize'];
    final downloadedBytes = value['downloadedBytes'];
    final progressPermille = value['progressPermille'];
    final releaseTag = value['releaseTag'];
    final assetName = value['assetName'];
    final failure = value['failure'];
    if (stageName is! String ||
        expectedSize is! int ||
        downloadedBytes is! int ||
        progressPermille is! int ||
        expectedSize < 0 ||
        downloadedBytes < 0 ||
        progressPermille < 0 ||
        progressPermille > 1000 ||
        releaseTag is! String? ||
        assetName is! String? ||
        failure is! String?) {
      return null;
    }
    TvNativeUpdateStage? stage;
    for (final candidate in TvNativeUpdateStage.values) {
      if (candidate.name == stageName) {
        stage = candidate;
        break;
      }
    }
    if (stage == null) return null;
    return TvNativeUpdateSnapshot(
      stage: stage,
      releaseTag: releaseTag,
      assetName: assetName,
      expectedSize: expectedSize,
      downloadedBytes: downloadedBytes,
      progressPermille: progressPermille,
      failure: failure,
    );
  }

  Map<String, Object?> toPublicMap() => {
        'stage': stage.name,
        'releaseTag': releaseTag,
        'assetName': assetName,
        'expectedSize': expectedSize,
        'downloadedBytes': downloadedBytes,
        'progressPermille': progressPermille,
        'failure': failure,
      };
}

class TvNativeUpdatePlatformInfo {
  const TvNativeUpdatePlatformInfo({
    required this.lane,
    required this.supportedAbis,
    required this.canInstallPackages,
  });

  final TvReleaseAppLane lane;
  final List<String> supportedAbis;
  final bool canInstallPackages;
}

abstract interface class TvNativeUpdatePlatform {
  Stream<TvNativeUpdateSnapshot> get snapshots;
  Future<TvNativeUpdatePlatformInfo> getPlatformInfo();
  Future<TvNativeUpdateSnapshot> getSnapshot();
  Future<TvNativeUpdateSnapshot> start(Map<String, Object?> request);
  Future<TvNativeUpdateSnapshot> command(String name);
}

class MethodChannelTvNativeUpdatePlatform implements TvNativeUpdatePlatform {
  static const _methods = MethodChannel('app.juicr.flutter/app_update');
  static const _events = EventChannel('app.juicr.flutter/app_update_events');

  @override
  Stream<TvNativeUpdateSnapshot> get snapshots => _events
      .receiveBroadcastStream()
      .map(TvNativeUpdateSnapshot.tryParse)
      .where((value) => value != null)
      .cast<TvNativeUpdateSnapshot>();

  @override
  Future<TvNativeUpdatePlatformInfo> getPlatformInfo() async {
    final value = await _methods.invokeMethod<Object?>('platformInfo');
    if (value is! Map ||
        !setEquals(
          value.keys.toSet(),
          const {'sdkInt', 'abis', 'canInstallPackages', 'lane'},
        )) {
      throw const FormatException('Native update capability is invalid.');
    }
    final laneValue = value['lane'];
    final abis = value['abis'];
    final canInstall = value['canInstallPackages'];
    if ((laneValue != 'android' && laneValue != 'tv') ||
        abis is! List ||
        abis.any((abi) => abi is! String) ||
        canInstall is! bool) {
      throw const FormatException('Native update capability is invalid.');
    }
    return TvNativeUpdatePlatformInfo(
      lane: laneValue == 'tv' ? TvReleaseAppLane.tv : TvReleaseAppLane.android,
      supportedAbis: List.unmodifiable(abis.cast<String>()),
      canInstallPackages: canInstall,
    );
  }

  @override
  Future<TvNativeUpdateSnapshot> getSnapshot() => _invoke('snapshot');

  @override
  Future<TvNativeUpdateSnapshot> start(Map<String, Object?> request) =>
      _invoke('start', request);

  @override
  Future<TvNativeUpdateSnapshot> command(String name) => _invoke(name);

  Future<TvNativeUpdateSnapshot> _invoke(String method, [Object? arguments]) async {
    final value = await _methods.invokeMethod<Object?>(method, arguments);
    return TvNativeUpdateSnapshot.tryParse(value) ??
        (throw const FormatException('Native update state is invalid.'));
  }
}

class TvNativeAppUpdater extends ChangeNotifier {
  TvNativeAppUpdater({TvNativeUpdatePlatform? platform})
      : _platform = platform ?? MethodChannelTvNativeUpdatePlatform();

  static final instance = TvNativeAppUpdater();

  final TvNativeUpdatePlatform _platform;
  StreamSubscription<TvNativeUpdateSnapshot>? _subscription;
  TvNativeUpdateSnapshot snapshot =
      const TvNativeUpdateSnapshot(stage: TvNativeUpdateStage.idle);

  Future<void> initialize() async {
    if (_subscription != null) return;
    snapshot = await _platform.getSnapshot();
    notifyListeners();
    _subscription = _platform.snapshots.listen(
      _adopt,
      onError: (Object _) {
        // Method responses remain authoritative if the event stream is absent.
      },
    );
  }

  Future<bool> startAssets(List<TvReleaseApkAsset> assets) async {
    if (assets.isEmpty) return false;
    final info = await _platform.getPlatformInfo();
    if (info.lane != TvReleaseAppLane.tv) return false;
    final asset = selectTvReleaseApkAsset(
      assets: assets,
      lane: TvReleaseAppLane.tv,
      supportedAbis: info.supportedAbis,
    );
    if (asset == null) return false;
    _adopt(
      await _platform.start({
        'releaseTag': asset.releaseTag,
        'assetName': asset.name,
        'assetUrl': asset.downloadUri.toString(),
        'expectedSize': asset.size,
        'sha256': asset.sha256,
      }),
    );
    return true;
  }

  Future<void> pause() => _command('pause');
  Future<void> resume() => _command('resume');
  Future<void> cancel() => _command('cancel');
  Future<void> deleteDownload() => _command('deleteDownload');
  Future<void> install() => _command('install');
  Future<void> openInstallPermissionSettings() =>
      _command('openInstallPermissionSettings');

  Future<void> _command(String command) async {
    _adopt(await _platform.command(command));
  }

  void _adopt(TvNativeUpdateSnapshot value) {
    snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
