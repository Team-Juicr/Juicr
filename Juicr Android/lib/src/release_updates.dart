import 'dart:convert';

import 'package:http/http.dart' as http;

import 'release_update_assets.dart';

enum ReleaseUpdateChannel { stable, nightly }

class ReleaseUpdateInfo {
  const ReleaseUpdateInfo({
    required this.channel,
    required this.name,
    required this.tag,
    required this.body,
    required this.publishedAt,
    required this.checkedAt,
    required this.fromFallback,
    this.apkAssets = const [],
    this.releaseUrl,
  });

  final ReleaseUpdateChannel channel;
  final String name;
  final String tag;
  final String body;
  final DateTime? publishedAt;
  final DateTime checkedAt;
  final bool fromFallback;
  final List<ReleaseApkAsset> apkAssets;
  final Uri? releaseUrl;

  String get displayVersion {
    final cleanTag = tag.trim();
    if (cleanTag.startsWith('v') && cleanTag.length > 1) {
      return cleanTag.substring(1);
    }
    return cleanTag.isEmpty ? 'Unknown' : cleanTag;
  }
}

final Uri juicrReleasesUri = Uri.parse(
  'https://github.com/Team-Juicr/Juicr/releases',
);

Uri releaseDownloadUri(ReleaseUpdateInfo release) {
  return release.releaseUrl ?? juicrReleasesUri;
}

class ReleaseUpdatesClient {
  ReleaseUpdatesClient({http.Client? client}) : _client = client;

  static final Uri _releasesUri = Uri.parse(
    'https://api.github.com/repos/Team-Juicr/Juicr/releases',
  );

  final http.Client? _client;

  Future<ReleaseUpdateInfo> latestForChannel(
    ReleaseUpdateChannel channel,
  ) async {
    final checkedAt = DateTime.now();
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
        _releasesUri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException('Release lookup failed.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Release lookup was not readable.');
      }
      final releases = decoded
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .where((raw) => raw['draft'] != true)
          .toList(growable: false);
      final candidates = releases.where((raw) {
        final prerelease = raw['prerelease'] == true;
        final tag = (raw['tag_name'] ?? '').toString().toLowerCase();
        final nightly = prerelease || tag.contains('nightly');
        return channel == ReleaseUpdateChannel.nightly ? nightly : !nightly;
      }).toList();
      candidates.sort(_compareReleaseJsonNewestFirst);
      final release = candidates.isEmpty ? null : candidates.first;
      if (release == null) {
        throw const FormatException('No matching release found.');
      }
      return await _fromReleaseJson(release, channel, checkedAt, client);
    } catch (_) {
      return fallbackReleaseInfo(channel, checkedAt: checkedAt);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<ReleaseUpdateInfo> _fromReleaseJson(
    Map<String, dynamic> json,
    ReleaseUpdateChannel channel,
    DateTime checkedAt,
    http.Client client,
  ) async {
    final tag = (json['tag_name'] ?? '').toString().trim();
    final name = (json['name'] ?? tag).toString().trim();
    final body = (json['body'] ?? '').toString().trim();
    final publishedAt = DateTime.tryParse(
      (json['published_at'] ?? '').toString(),
    )?.toLocal();
    final releaseUrl = _safeExternalUri((json['html_url'] ?? '').toString());
    final apkAssets = await _verifiedApkAssets(
      releaseJson: json,
      releaseTag: tag,
      client: client,
    );
    return ReleaseUpdateInfo(
      channel: channel,
      name: name.isEmpty ? tag : name,
      tag: tag,
      body: body.isEmpty ? fallbackChangelog(channel) : body,
      publishedAt: publishedAt,
      checkedAt: checkedAt,
      fromFallback: false,
      apkAssets: apkAssets,
      releaseUrl: releaseUrl,
    );
  }

  Future<List<ReleaseApkAsset>> _verifiedApkAssets({
    required Map<String, dynamic> releaseJson,
    required String releaseTag,
    required http.Client client,
  }) async {
    try {
      if (releaseTag.isEmpty) return const [];
      final rawAssets = releaseJson['assets'];
      if (rawAssets is! List || rawAssets.length > 17) return const [];
      final expectedManifestName = 'juicr-$releaseTag-checksums.json';
      final manifests = <Uri>[];
      final apkAssets = <GithubReleaseAsset>[];
      for (final raw in rawAssets) {
        if (raw is! Map) return const [];
        final asset = Map<String, dynamic>.from(raw);
        final name = (asset['name'] ?? '').toString().trim();
        final size = asset['size'];
        final uri = _safeReleaseAssetUri(
          (asset['browser_download_url'] ?? '').toString(),
          releaseTag: releaseTag,
          assetName: name,
        );
        if (uri == null) return const [];
        if (name == expectedManifestName) {
          manifests.add(uri);
        } else if (name.endsWith('.apk')) {
          if (size is! int || size <= 0) return const [];
          apkAssets.add(
            GithubReleaseAsset(name: name, size: size, downloadUri: uri),
          );
        }
      }
      if (manifests.length != 1 || apkAssets.isEmpty) return const [];
      final response = await client.get(
        manifests.single,
        headers: const {
          'Accept': 'application/json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];
      return parseReleaseApkAssets(
        releaseTag: releaseTag,
        githubAssets: apkAssets,
        manifestJson: Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return const [];
    }
  }
}

Uri? _safeExternalUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https') return null;
  if (uri.host.toLowerCase() != 'github.com') return null;
  final segments = uri.pathSegments;
  if (segments.length < 5 ||
      segments[0] != 'Team-Juicr' ||
      segments[1] != 'Juicr' ||
      segments[2] != 'releases' ||
      segments[3] != 'tag' ||
      segments[4].trim().isEmpty) {
    return null;
  }
  return uri;
}

Uri? _safeReleaseAssetUri(
  String value, {
  required String releaseTag,
  required String assetName,
}) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.toLowerCase() != 'github.com' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != 6 ||
      segments[0] != 'Team-Juicr' ||
      segments[1] != 'Juicr' ||
      segments[2] != 'releases' ||
      segments[3] != 'download' ||
      segments[4] != releaseTag ||
      segments[5] != assetName) {
    return null;
  }
  return uri;
}

int _compareReleaseJsonNewestFirst(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final leftTag = (left['tag_name'] ?? '').toString();
  final rightTag = (right['tag_name'] ?? '').toString();
  final versionOrder = compareReleaseVersions(rightTag, leftTag);
  if (versionOrder != 0) return versionOrder;
  final leftPublished = DateTime.tryParse(
    (left['published_at'] ?? '').toString(),
  );
  final rightPublished = DateTime.tryParse(
    (right['published_at'] ?? '').toString(),
  );
  if (leftPublished == null && rightPublished == null) return 0;
  if (leftPublished == null) return 1;
  if (rightPublished == null) return -1;
  return rightPublished.compareTo(leftPublished);
}

ReleaseUpdateChannel releaseChannelForVersion(String versionName) {
  return versionName.toLowerCase().contains('nightly')
      ? ReleaseUpdateChannel.nightly
      : ReleaseUpdateChannel.stable;
}

bool isReleaseUpdateAvailable({
  required String installedVersion,
  required String latestVersion,
}) {
  return compareReleaseVersions(installedVersion, latestVersion) < 0;
}

int compareReleaseVersions(String left, String right) {
  final leftVersion = _ParsedReleaseVersion.tryParse(left);
  final rightVersion = _ParsedReleaseVersion.tryParse(right);
  if (leftVersion == null || rightVersion == null) return 0;
  return leftVersion.compareTo(rightVersion);
}

class _ParsedReleaseVersion implements Comparable<_ParsedReleaseVersion> {
  const _ParsedReleaseVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static _ParsedReleaseVersion? tryParse(String value) {
    var text = value.trim().toLowerCase();
    if (text.startsWith('v')) text = text.substring(1);
    final plusIndex = text.indexOf('+');
    if (plusIndex >= 0) text = text.substring(0, plusIndex);
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9a-z.-]+))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final preReleaseText = match.group(4);
    return _ParsedReleaseVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: preReleaseText == null || preReleaseText.isEmpty
          ? const []
          : preReleaseText.split('.'),
    );
  }

  @override
  int compareTo(_ParsedReleaseVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    final patchOrder = patch.compareTo(other.patch);
    if (patchOrder != 0) return patchOrder;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    final length = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var index = 0; index < length; index++) {
      if (index >= preRelease.length) return -1;
      if (index >= other.preRelease.length) return 1;
      final left = preRelease[index];
      final right = other.preRelease[index];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        final numberOrder = leftNumber.compareTo(rightNumber);
        if (numberOrder != 0) return numberOrder;
        continue;
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;
      final textOrder = left.compareTo(right);
      if (textOrder != 0) return textOrder;
    }
    return 0;
  }
}

ReleaseUpdateInfo fallbackReleaseInfo(
  ReleaseUpdateChannel channel, {
  DateTime? checkedAt,
}) {
  return ReleaseUpdateInfo(
    channel: channel,
    name: channel == ReleaseUpdateChannel.nightly
        ? 'Juicr nightly'
        : 'Juicr v1.0.1',
    tag: channel == ReleaseUpdateChannel.nightly ? 'nightly' : 'v1.0.1',
    body: fallbackChangelog(channel),
    publishedAt: null,
    checkedAt: checkedAt ?? DateTime.now(),
    fromFallback: true,
  );
}

String fallbackChangelog(ReleaseUpdateChannel channel) {
  if (channel == ReleaseUpdateChannel.nightly) {
    return '''
Nightly build

Added
- Public testing builds are available before the next stable release so fixes can be validated earlier.
- Android and Android TV nightly outputs include universal and ABI-specific APKs.

Changed
- Update checks separate nightly and stable channels so testers see the notes that match their installed build.
- Release notes are presented in-app with a local fallback when release details cannot be refreshed.

Fixed
- Recent mobile fixes include safer startup handling, account library sync protection, and playback stability work from the dev branch.
'''
        .trim();
  }
  return '''
Added
- Release builds now include Android and Android TV APKs from the same version.
- Android and Android TV releases publish universal, arm64-v8a, armeabi-v7a, and x86_64 APK downloads.
- Release notes separate mobile and TV work so the website and app can surface version notes clearly.

Changed
- Release artifacts use stable Juicr names for mobile and TV downloads.
- Android TV is aligned to the current release version so both app lanes can be rebuilt together.

Fixed
- Android release APKs no longer force close during startup when release minification initializes background app services.
- Release publishing no longer stops at mobile-only artifacts when TV downloads are expected.
'''
      .trim();
}
