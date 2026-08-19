enum ReleaseAppLane { android, tv }

class GithubReleaseAsset {
  const GithubReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUri,
  });

  final String name;
  final int size;
  final Uri downloadUri;
}

class ReleaseApkAsset {
  const ReleaseApkAsset({
    required this.releaseTag,
    required this.name,
    required this.downloadUri,
    required this.size,
    required this.sha256,
    required this.lane,
    required this.abi,
  });

  final String releaseTag;
  final String name;
  final Uri downloadUri;
  final int size;
  final String sha256;
  final ReleaseAppLane lane;
  final String abi;
}

List<ReleaseApkAsset> parseReleaseApkAssets({
  required String releaseTag,
  required Iterable<GithubReleaseAsset> githubAssets,
  required Map<String, Object?> manifestJson,
}) {
  final tag = releaseTag.trim();
  if (tag.isEmpty ||
      manifestJson.keys.toSet().difference(
        const {'schemaVersion', 'tag', 'assets'},
      ).isNotEmpty ||
      manifestJson.keys.length != 3 ||
      manifestJson['schemaVersion'] != 1 ||
      manifestJson['tag'] != tag) {
    throw const FormatException('Release manifest is invalid.');
  }

  final rawManifestAssets = manifestJson['assets'];
  if (rawManifestAssets is! List ||
      rawManifestAssets.isEmpty ||
      rawManifestAssets.length > 16) {
    throw const FormatException('Release manifest assets are invalid.');
  }

  final githubByName = <String, GithubReleaseAsset>{};
  for (final asset in githubAssets) {
    if (!_isSafeGithubReleaseAssetUri(asset.downloadUri, tag, asset.name) ||
        asset.size <= 0 ||
        githubByName.containsKey(asset.name)) {
      throw const FormatException('Release asset inventory is invalid.');
    }
    githubByName[asset.name] = asset;
  }
  if (githubByName.isEmpty || githubByName.length > 16) {
    throw const FormatException('Release asset inventory is invalid.');
  }

  final filenamePattern = RegExp(
    '^juicr-(android|tv)-${RegExp.escape(tag)}-'
    r'(universal|armeabi-v7a|arm64-v8a|x86_64)\.apk$',
  );
  final parsed = <ReleaseApkAsset>[];
  final seen = <String>{};
  for (final raw in rawManifestAssets) {
    if (raw is! Map || raw.keys.length != 3) {
      throw const FormatException('Release manifest entry is invalid.');
    }
    final entry = Map<String, Object?>.from(raw);
    if (entry.keys
        .toSet()
        .difference(const {'name', 'size', 'sha256'}).isNotEmpty) {
      throw const FormatException('Release manifest entry is invalid.');
    }
    final name = entry['name'];
    final size = entry['size'];
    final sha256 = entry['sha256'];
    if (name is! String ||
        size is! int ||
        size <= 0 ||
        sha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256) ||
        !seen.add(name)) {
      throw const FormatException('Release manifest entry is invalid.');
    }
    final match = filenamePattern.firstMatch(name);
    final github = githubByName[name];
    if (match == null || github == null || github.size != size) {
      throw const FormatException('Release manifest does not match assets.');
    }
    parsed.add(
      ReleaseApkAsset(
        releaseTag: tag,
        name: name,
        downloadUri: github.downloadUri,
        size: size,
        sha256: sha256,
        lane: match.group(1) == 'android'
            ? ReleaseAppLane.android
            : ReleaseAppLane.tv,
        abi: match.group(2)!,
      ),
    );
  }

  if (seen.length != githubByName.length ||
      !seen.containsAll(githubByName.keys)) {
    throw const FormatException('Release manifest inventory is incomplete.');
  }
  parsed.sort((left, right) => left.name.compareTo(right.name));
  return List.unmodifiable(parsed);
}

ReleaseApkAsset? selectReleaseApkAsset({
  required Iterable<ReleaseApkAsset> assets,
  required ReleaseAppLane lane,
  required Iterable<String> supportedAbis,
}) {
  final laneAssets = <String, ReleaseApkAsset>{};
  for (final asset in assets.where((asset) => asset.lane == lane)) {
    if (laneAssets.containsKey(asset.abi)) return null;
    laneAssets[asset.abi] = asset;
  }
  for (final abi in supportedAbis) {
    final selected = laneAssets[abi.trim()];
    if (selected != null) return selected;
  }
  return laneAssets['universal'];
}

bool _isSafeGithubReleaseAssetUri(Uri uri, String tag, String name) {
  if (uri.scheme != 'https' ||
      uri.host.toLowerCase() != 'github.com' ||
      uri.hasPort ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  final segments = uri.pathSegments;
  return segments.length == 6 &&
      segments[0] == 'Team-Juicr' &&
      segments[1] == 'Juicr' &&
      segments[2] == 'releases' &&
      segments[3] == 'download' &&
      segments[4] == tag &&
      segments[5] == name;
}
