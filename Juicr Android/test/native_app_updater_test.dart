import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/native_app_updater.dart';
import 'package:juicr/src/release_update_assets.dart';
import 'package:juicr/src/release_updates.dart';

void main() {
  test('snapshot parser accepts only exact bounded public schema', () {
    final snapshot = NativeUpdateSnapshot.tryParse({
      'stage': 'downloading',
      'releaseTag': 'v2.0.0',
      'assetName': 'juicr-android-v2.0.0-x86_64.apk',
      'expectedSize': 100,
      'downloadedBytes': 25,
      'progressPermille': 250,
      'failure': null,
    });

    expect(snapshot?.stage, NativeUpdateStage.downloading);
    expect(snapshot?.progressPermille, 250);
    expect(
      NativeUpdateSnapshot.tryParse({
        ...snapshot!.toPublicMap(),
        'localPath': '/private/update.apk',
      }),
      isNull,
    );
  });

  test('controller selects exact ABI asset and sends safe request only',
      () async {
    final platform = FakeNativeUpdatePlatform(
      platformInfo: const NativeUpdatePlatformInfo(
        lane: ReleaseAppLane.android,
        supportedAbis: ['x86_64'],
        canInstallPackages: true,
      ),
    );
    final controller = NativeAppUpdater(platform: platform);

    await controller.startRelease(release());

    expect(platform.started?['assetName'], 'juicr-android-v2.0.0-x86_64.apk');
    expect(platform.started?.keys, {
      'releaseTag',
      'assetName',
      'assetUrl',
      'expectedSize',
      'sha256',
    });
  });

  test('missing verified asset leaves browser fallback available', () async {
    final platform = FakeNativeUpdatePlatform(
      platformInfo: const NativeUpdatePlatformInfo(
        lane: ReleaseAppLane.android,
        supportedAbis: ['x86_64'],
        canInstallPackages: true,
      ),
    );
    final controller = NativeAppUpdater(platform: platform);

    final started = await controller.startRelease(
      release(assets: const []),
    );

    expect(started, isFalse);
    expect(platform.started, isNull);
  });

  test('controller mirrors events and delegates explicit actions', () async {
    final platform = FakeNativeUpdatePlatform(
      platformInfo: const NativeUpdatePlatformInfo(
        lane: ReleaseAppLane.android,
        supportedAbis: ['x86_64'],
        canInstallPackages: false,
      ),
    );
    final controller = NativeAppUpdater(platform: platform);
    await controller.initialize();
    platform.events.add(snapshot(NativeUpdateStage.readyToInstall));
    await Future<void>.delayed(Duration.zero);

    expect(controller.snapshot.stage, NativeUpdateStage.readyToInstall);
    await controller.install();
    await controller.pause();
    await controller.cancel();
    await controller.openInstallPermissionSettings();
    expect(platform.commands,
        ['install', 'pause', 'cancel', 'openInstallPermissionSettings']);
  });
}

ReleaseUpdateInfo release({List<ReleaseApkAsset>? assets}) => ReleaseUpdateInfo(
      channel: ReleaseUpdateChannel.stable,
      name: 'Juicr v2.0.0',
      tag: 'v2.0.0',
      body: 'Test',
      publishedAt: null,
      checkedAt: DateTime(2026),
      fromFallback: false,
      apkAssets: assets ??
          [
            asset('universal'),
            asset('x86_64'),
          ],
      releaseUrl:
          Uri.parse('https://github.com/Team-Juicr/Juicr/releases/tag/v2.0.0'),
    );

ReleaseApkAsset asset(String abi) => ReleaseApkAsset(
      releaseTag: 'v2.0.0',
      name: 'juicr-android-v2.0.0-$abi.apk',
      downloadUri: Uri.parse(
        'https://github.com/Team-Juicr/Juicr/releases/download/v2.0.0/juicr-android-v2.0.0-$abi.apk',
      ),
      size: 100,
      sha256: List.filled(64, 'a').join(),
      lane: ReleaseAppLane.android,
      abi: abi,
    );

NativeUpdateSnapshot snapshot(NativeUpdateStage stage) => NativeUpdateSnapshot(
      stage: stage,
      releaseTag: 'v2.0.0',
      assetName: 'juicr-android-v2.0.0-x86_64.apk',
      expectedSize: 100,
      downloadedBytes: 100,
      progressPermille: 1000,
    );

class FakeNativeUpdatePlatform implements NativeUpdatePlatform {
  FakeNativeUpdatePlatform({required this.platformInfo});

  final NativeUpdatePlatformInfo platformInfo;
  final events = StreamController<NativeUpdateSnapshot>.broadcast();
  final commands = <String>[];
  Map<String, Object?>? started;

  @override
  Stream<NativeUpdateSnapshot> get snapshots => events.stream;

  @override
  Future<NativeUpdatePlatformInfo> getPlatformInfo() async => platformInfo;

  @override
  Future<NativeUpdateSnapshot> getSnapshot() async =>
      const NativeUpdateSnapshot(stage: NativeUpdateStage.idle);

  @override
  Future<NativeUpdateSnapshot> start(Map<String, Object?> request) async {
    started = request;
    return snapshot(NativeUpdateStage.downloading);
  }

  @override
  Future<NativeUpdateSnapshot> command(String name) async {
    commands.add(name);
    return snapshot(NativeUpdateStage.idle);
  }
}
