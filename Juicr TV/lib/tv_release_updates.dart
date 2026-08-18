part of 'main.dart';

enum _TvReleaseUpdateChannel { stable, nightly }

class _TvReleaseUpdateInfo {
  const _TvReleaseUpdateInfo({
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

  final _TvReleaseUpdateChannel channel;
  final String name;
  final String tag;
  final String body;
  final DateTime? publishedAt;
  final DateTime checkedAt;
  final bool fromFallback;
  final List<TvReleaseApkAsset> apkAssets;
  final Uri? releaseUrl;

  String get displayVersion {
    final cleanTag = tag.trim();
    if (cleanTag.startsWith('v') && cleanTag.length > 1) {
      return cleanTag.substring(1);
    }
    return cleanTag.isEmpty ? 'Unknown' : cleanTag;
  }
}

class _TvReleaseUpdatesSnapshot {
  const _TvReleaseUpdatesSnapshot({
    required this.installedVersion,
    required this.installedCode,
    required this.channel,
    required this.latest,
  });

  final String installedVersion;
  final String installedCode;
  final _TvReleaseUpdateChannel channel;
  final _TvReleaseUpdateInfo latest;

  bool get updateAvailable {
    if (latest.fromFallback) return false;
    return _isTvReleaseUpdateAvailable(
      installedVersion: installedVersion,
      latestVersion: latest.displayVersion,
    );
  }

  Uri get downloadUri => latest.releaseUrl ?? _tvJuicrReleasesUri;

  String get installedLabel {
    final parts = <String>[installedVersion];
    if (installedCode.isNotEmpty && installedCode != '0') {
      parts.add('($installedCode)');
    }
    return parts.join(' ');
  }
}

final Uri _tvJuicrReleasesUri = Uri.parse(
  'https://github.com/Team-Juicr/Juicr/releases',
);

class _TvReleaseUpdatesClient {
  _TvReleaseUpdatesClient({HttpClient? client}) : _client = client;

  static final Uri _releasesUri = Uri.parse(
    'https://api.github.com/repos/Team-Juicr/Juicr/releases',
  );

  final HttpClient? _client;

  Future<_TvReleaseUpdateInfo> latestForChannel(
    _TvReleaseUpdateChannel channel,
  ) async {
    final checkedAt = DateTime.now();
    final client = _client ?? HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(_releasesUri);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28')
        ..set(HttpHeaders.userAgentHeader, 'JuicrTV/$_tvAppVersion');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const FormatException('Release lookup failed.');
      }
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
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
        return channel == _TvReleaseUpdateChannel.nightly ? nightly : !nightly;
      }).toList();
      candidates.sort(_compareTvReleaseJsonNewestFirst);
      final release = candidates.isEmpty ? null : candidates.first;
      if (release == null) {
        throw const FormatException('No matching release found.');
      }
      return await _fromReleaseJson(release, channel, checkedAt, client);
    } catch (_) {
      return _fallbackTvReleaseInfo(channel, checkedAt: checkedAt);
    } finally {
      if (_client == null) client.close(force: true);
    }
  }

  Future<_TvReleaseUpdateInfo> _fromReleaseJson(
    Map<String, dynamic> json,
    _TvReleaseUpdateChannel channel,
    DateTime checkedAt,
    HttpClient client,
  ) async {
    final tag = (json['tag_name'] ?? '').toString().trim();
    final name = (json['name'] ?? tag).toString().trim();
    final body = (json['body'] ?? '').toString().trim();
    final publishedAt = DateTime.tryParse(
      (json['published_at'] ?? '').toString(),
    )?.toLocal();
    final releaseUrl = _safeTvExternalReleaseUri(
      (json['html_url'] ?? '').toString(),
    );
    final apkAssets = await _verifiedTvApkAssets(
      releaseJson: json,
      releaseTag: tag,
      client: client,
    );
    return _TvReleaseUpdateInfo(
      channel: channel,
      name: name.isEmpty ? tag : name,
      tag: tag,
      body: body.isEmpty ? _fallbackTvChangelog(channel) : body,
      publishedAt: publishedAt,
      checkedAt: checkedAt,
      fromFallback: false,
      apkAssets: apkAssets,
      releaseUrl: releaseUrl,
    );
  }

  Future<List<TvReleaseApkAsset>> _verifiedTvApkAssets({
    required Map<String, dynamic> releaseJson,
    required String releaseTag,
    required HttpClient client,
  }) async {
    try {
      if (releaseTag.isEmpty) return const [];
      final rawAssets = releaseJson['assets'];
      if (rawAssets is! List || rawAssets.length > 17) return const [];
      final expectedManifestName = 'juicr-$releaseTag-checksums.json';
      final manifests = <Uri>[];
      final apkAssets = <TvGithubReleaseAsset>[];
      for (final raw in rawAssets) {
        if (raw is! Map) return const [];
        final asset = Map<String, dynamic>.from(raw);
        final name = (asset['name'] ?? '').toString().trim();
        final size = asset['size'];
        final uri = _safeTvReleaseAssetUri(
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
            TvGithubReleaseAsset(name: name, size: size, downloadUri: uri),
          );
        }
      }
      if (manifests.length != 1 || apkAssets.isEmpty) return const [];
      final request = await client.getUrl(manifests.single);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/json')
        ..set('X-GitHub-Api-Version', '2022-11-28')
        ..set(HttpHeaders.userAgentHeader, 'JuicrTV/$_tvAppVersion');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(await utf8.decodeStream(response));
      if (decoded is! Map) return const [];
      return parseTvReleaseApkAssets(
        releaseTag: releaseTag,
        githubAssets: apkAssets,
        manifestJson: Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      return const [];
    }
  }
}

Uri? _safeTvReleaseAssetUri(
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

_TvReleaseUpdateChannel _tvReleaseChannelForVersion(String versionName) {
  return versionName.toLowerCase().contains('nightly')
      ? _TvReleaseUpdateChannel.nightly
      : _TvReleaseUpdateChannel.stable;
}

bool _isTvReleaseUpdateAvailable({
  required String installedVersion,
  required String latestVersion,
}) {
  return _compareTvReleaseVersions(installedVersion, latestVersion) < 0;
}

int _compareTvReleaseVersions(String left, String right) {
  final leftVersion = _ParsedTvReleaseVersion.tryParse(left);
  final rightVersion = _ParsedTvReleaseVersion.tryParse(right);
  if (leftVersion == null || rightVersion == null) return 0;
  return leftVersion.compareTo(rightVersion);
}

class _ParsedTvReleaseVersion implements Comparable<_ParsedTvReleaseVersion> {
  const _ParsedTvReleaseVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static _ParsedTvReleaseVersion? tryParse(String value) {
    var text = value.trim().toLowerCase();
    if (text.startsWith('v')) text = text.substring(1);
    final plusIndex = text.indexOf('+');
    if (plusIndex >= 0) text = text.substring(0, plusIndex);
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9a-z.-]+))?$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    final preReleaseText = match.group(4);
    return _ParsedTvReleaseVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: preReleaseText == null || preReleaseText.isEmpty
          ? const []
          : preReleaseText.split('.'),
    );
  }

  @override
  int compareTo(_ParsedTvReleaseVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    final patchOrder = patch.compareTo(other.patch);
    if (patchOrder != 0) return patchOrder;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;
    final length = math.max(preRelease.length, other.preRelease.length);
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

int _compareTvReleaseJsonNewestFirst(
  Map<String, dynamic> left,
  Map<String, dynamic> right,
) {
  final leftTag = (left['tag_name'] ?? '').toString();
  final rightTag = (right['tag_name'] ?? '').toString();
  final versionOrder = _compareTvReleaseVersions(rightTag, leftTag);
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

Uri? _safeTvExternalReleaseUri(String value) {
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

_TvReleaseUpdateInfo _fallbackTvReleaseInfo(
  _TvReleaseUpdateChannel channel, {
  DateTime? checkedAt,
}) {
  return _TvReleaseUpdateInfo(
    channel: channel,
    name: channel == _TvReleaseUpdateChannel.nightly
        ? 'Juicr nightly'
        : 'Juicr v$_tvAppVersion',
    tag: channel == _TvReleaseUpdateChannel.nightly
        ? 'nightly'
        : 'v$_tvAppVersion',
    body: _fallbackTvChangelog(channel),
    publishedAt: null,
    checkedAt: checkedAt ?? DateTime.now(),
    fromFallback: true,
  );
}

String _fallbackTvChangelog(_TvReleaseUpdateChannel channel) {
  if (channel == _TvReleaseUpdateChannel.nightly) {
    return '''
Nightly build

Added
- Public testing builds are available before the next stable release so fixes can be validated earlier.
- Android TV nightly outputs include universal and device-specific APKs.

Changed
- Update checks separate nightly and stable channels so testers see the notes that match their installed build.
- Release notes are presented in-app with a local fallback when release details cannot be refreshed.

Fixed
- Recent TV fixes include safer focus restoration, library sync protection, and playback stability work.
'''
        .trim();
  }
  return '''
Added
- Release builds include Android TV APKs from the same version family as Juicr mobile.
- Release notes separate mobile and TV work so the app can surface version notes clearly.

Changed
- Android TV release artifacts use stable Juicr names for living-room installs.
- TV builds stay aligned with the current public release channel.

Fixed
- Recent TV fixes include settings focus handling, library sync, and safer redacted diagnostics.
'''
      .trim();
}
