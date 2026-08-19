import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'release_update_assets.dart';
import 'release_updates.dart';

enum NativeUpdateStage {
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

class NativeUpdateSnapshot {
  const NativeUpdateSnapshot({
    required this.stage,
    this.releaseTag,
    this.assetName,
    this.expectedSize = 0,
    this.downloadedBytes = 0,
    this.progressPermille = 0,
    this.failure,
  });

  final NativeUpdateStage stage;
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

  static NativeUpdateSnapshot? tryParse(Object? value) {
    if (value is! Map || !setEquals(value.keys.toSet(), _exactKeys)) {
      return null;
    }
    final stageName = value['stage'];
    final expectedSize = value['expectedSize'];
    final downloadedBytes = value['downloadedBytes'];
    final progressPermille = value['progressPermille'];
    if (stageName is! String ||
        expectedSize is! int ||
        downloadedBytes is! int ||
        progressPermille is! int ||
        expectedSize < 0 ||
        downloadedBytes < 0 ||
        progressPermille < 0 ||
        progressPermille > 1000) {
      return null;
    }
    final stage = NativeUpdateStage.values
        .where((candidate) => candidate.name == stageName)
        .firstOrNull;
    final releaseTag = value['releaseTag'];
    final assetName = value['assetName'];
    final failure = value['failure'];
    if (stage == null ||
        releaseTag is! String? ||
        assetName is! String? ||
        failure is! String?) {
      return null;
    }
    return NativeUpdateSnapshot(
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

class NativeUpdatePlatformInfo {
  const NativeUpdatePlatformInfo({
    required this.lane,
    required this.supportedAbis,
    required this.canInstallPackages,
  });

  final ReleaseAppLane lane;
  final List<String> supportedAbis;
  final bool canInstallPackages;
}

abstract interface class NativeUpdatePlatform {
  Stream<NativeUpdateSnapshot> get snapshots;
  Future<NativeUpdatePlatformInfo> getPlatformInfo();
  Future<NativeUpdateSnapshot> getSnapshot();
  Future<NativeUpdateSnapshot> start(Map<String, Object?> request);
  Future<NativeUpdateSnapshot> command(String name);
}

class MethodChannelNativeUpdatePlatform implements NativeUpdatePlatform {
  static const _methods = MethodChannel('app.juicr.flutter/app_update');
  static const _events = EventChannel('app.juicr.flutter/app_update_events');

  @override
  Stream<NativeUpdateSnapshot> get snapshots => _events
      .receiveBroadcastStream()
      .map(NativeUpdateSnapshot.tryParse)
      .where((value) => value != null)
      .cast<NativeUpdateSnapshot>();

  @override
  Future<NativeUpdatePlatformInfo> getPlatformInfo() async {
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
    return NativeUpdatePlatformInfo(
      lane: laneValue == 'android' ? ReleaseAppLane.android : ReleaseAppLane.tv,
      supportedAbis: List.unmodifiable(abis.cast<String>()),
      canInstallPackages: canInstall,
    );
  }

  @override
  Future<NativeUpdateSnapshot> getSnapshot() => _invoke('snapshot');

  @override
  Future<NativeUpdateSnapshot> start(Map<String, Object?> request) =>
      _invoke('start', request);

  @override
  Future<NativeUpdateSnapshot> command(String name) => _invoke(name);

  Future<NativeUpdateSnapshot> _invoke(
    String method, [
    Object? arguments,
  ]) async {
    final value = await _methods.invokeMethod<Object?>(method, arguments);
    return NativeUpdateSnapshot.tryParse(value) ??
        (throw const FormatException('Native update state is invalid.'));
  }
}

class NativeAppUpdater extends ChangeNotifier {
  NativeAppUpdater({NativeUpdatePlatform? platform})
      : _platform = platform ?? MethodChannelNativeUpdatePlatform();

  static final instance = NativeAppUpdater();

  final NativeUpdatePlatform _platform;
  StreamSubscription<NativeUpdateSnapshot>? _subscription;
  NativeUpdateSnapshot snapshot =
      const NativeUpdateSnapshot(stage: NativeUpdateStage.idle);

  Future<void> initialize() async {
    if (_subscription != null) return;
    snapshot = await _platform.getSnapshot();
    notifyListeners();
    _subscription = _platform.snapshots.listen(_adopt);
  }

  Future<bool> startRelease(ReleaseUpdateInfo release) async {
    if (release.fromFallback || release.apkAssets.isEmpty) return false;
    final info = await _platform.getPlatformInfo();
    final asset = selectReleaseApkAsset(
      assets: release.apkAssets,
      lane: info.lane,
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

  void _adopt(NativeUpdateSnapshot value) {
    snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
