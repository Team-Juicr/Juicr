import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr_tv/tv_native_app_updater.dart';
import 'package:juicr_tv/tv_release_update_assets.dart';

void main() {
  test('snapshot parser accepts only the exact bounded public schema', () {
    final snapshot = TvNativeUpdateSnapshot.tryParse({
      'stage': 'downloading',
      'releaseTag': 'v2.0.0',
      'assetName': 'juicr-tv-v2.0.0-x86_64.apk',
      'expectedSize': 100,
      'downloadedBytes': 25,
      'progressPermille': 250,
      'failure': null,
    });

    expect(snapshot?.stage, TvNativeUpdateStage.downloading);
    expect(snapshot?.progressPermille, 250);
    expect(
      TvNativeUpdateSnapshot.tryParse({
        ...snapshot!.toPublicMap(),
        'localPath': '/private/update.apk',
      }),
      isNull,
    );
  });

  test('controller selects the exact TV ABI and sends safe request only', () async {
    final platform = _FakeTvNativeUpdatePlatform(
      platformInfo: const TvNativeUpdatePlatformInfo(
        lane: TvReleaseAppLane.tv,
        supportedAbis: ['x86_64'],
        canInstallPackages: true,
      ),
    );
    final controller = TvNativeAppUpdater(platform: platform);

    final started = await controller.startAssets([_asset('universal'), _asset('x86_64')]);

    expect(started, isTrue);
    expect(platform.started?['assetName'], 'juicr-tv-v2.0.0-x86_64.apk');
    expect(platform.started?.keys, {
      'releaseTag',
      'assetName',
      'assetUrl',
      'expectedSize',
      'sha256',
    });
  });

  test('missing verified TV asset leaves release page fallback available', () async {
    final platform = _FakeTvNativeUpdatePlatform(
      platformInfo: const TvNativeUpdatePlatformInfo(
        lane: TvReleaseAppLane.tv,
        supportedAbis: ['x86_64'],
        canInstallPackages: true,
      ),
    );
    final controller = TvNativeAppUpdater(platform: platform);

    expect(await controller.startAssets(const []), isFalse);
    expect(platform.started, isNull);
  });

  test('controller mirrors events and delegates explicit actions', () async {
    final platform = _FakeTvNativeUpdatePlatform(
      platformInfo: const TvNativeUpdatePlatformInfo(
        lane: TvReleaseAppLane.tv,
        supportedAbis: ['x86_64'],
        canInstallPackages: false,
      ),
    );
    final controller = TvNativeAppUpdater(platform: platform);
    await controller.initialize();
    platform.events.add(_snapshot(TvNativeUpdateStage.readyToInstall));
    await Future<void>.delayed(Duration.zero);

    expect(controller.snapshot.stage, TvNativeUpdateStage.readyToInstall);
    await controller.install();
    await controller.pause();
    await controller.cancel();
    await controller.openInstallPermissionSettings();
    expect(platform.commands, [
      'install',
      'pause',
      'cancel',
      'openInstallPermissionSettings',
    ]);
  });

  test('remote dialog action model follows native lifecycle exactly', () {
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.idle),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ),
      const TvNativeUpdateAction(
        kind: TvNativeUpdateActionKind.start,
        label: 'Download update',
        enabled: true,
      ),
    );
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.downloading),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ).kind,
      TvNativeUpdateActionKind.pause,
    );
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.paused),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ).kind,
      TvNativeUpdateActionKind.resume,
    );
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.readyToInstall),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ).kind,
      TvNativeUpdateActionKind.install,
    );
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.awaitingPermission),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ).kind,
      TvNativeUpdateActionKind.openPermissionSettings,
    );
    expect(
      tvNativeUpdateActionFor(
        snapshot: _snapshot(TvNativeUpdateStage.verifying),
        updateAvailable: true,
        hasVerifiedAsset: true,
      ).enabled,
      isFalse,
    );
  });

  test('unverified release never turns browser fallback into native download', () {
    final action = tvNativeUpdateActionFor(
      snapshot: _snapshot(TvNativeUpdateStage.idle),
      updateAvailable: true,
      hasVerifiedAsset: false,
    );

    expect(action.kind, TvNativeUpdateActionKind.none);
    expect(action.label, 'Verified download unavailable');
    expect(action.enabled, isFalse);
  });
}

TvReleaseApkAsset _asset(String abi) => TvReleaseApkAsset(
      releaseTag: 'v2.0.0',
      name: 'juicr-tv-v2.0.0-$abi.apk',
      downloadUri: Uri.parse(
        'https://github.com/Team-Juicr/Juicr/releases/download/v2.0.0/juicr-tv-v2.0.0-$abi.apk',
      ),
      size: 100,
      sha256: List.filled(64, 'a').join(),
      lane: TvReleaseAppLane.tv,
      abi: abi,
    );

TvNativeUpdateSnapshot _snapshot(TvNativeUpdateStage stage) =>
    TvNativeUpdateSnapshot(
      stage: stage,
      releaseTag: 'v2.0.0',
      assetName: 'juicr-tv-v2.0.0-x86_64.apk',
      expectedSize: 100,
      downloadedBytes: 100,
      progressPermille: 1000,
    );

class _FakeTvNativeUpdatePlatform implements TvNativeUpdatePlatform {
  _FakeTvNativeUpdatePlatform({required this.platformInfo});

  final TvNativeUpdatePlatformInfo platformInfo;
  final events = StreamController<TvNativeUpdateSnapshot>.broadcast();
  final commands = <String>[];
  Map<String, Object?>? started;

  @override
  Stream<TvNativeUpdateSnapshot> get snapshots => events.stream;

  @override
  Future<TvNativeUpdatePlatformInfo> getPlatformInfo() async => platformInfo;

  @override
  Future<TvNativeUpdateSnapshot> getSnapshot() async =>
      const TvNativeUpdateSnapshot(stage: TvNativeUpdateStage.idle);

  @override
  Future<TvNativeUpdateSnapshot> start(Map<String, Object?> request) async {
    started = request;
    return _snapshot(TvNativeUpdateStage.downloading);
  }

  @override
  Future<TvNativeUpdateSnapshot> command(String name) async {
    commands.add(name);
    return _snapshot(TvNativeUpdateStage.idle);
  }
}
