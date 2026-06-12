import 'dart:convert';

import 'package:http/http.dart' as http;

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
  });

  final ReleaseUpdateChannel channel;
  final String name;
  final String tag;
  final String body;
  final DateTime? publishedAt;
  final DateTime checkedAt;
  final bool fromFallback;

  String get displayVersion {
    final cleanTag = tag.trim();
    if (cleanTag.startsWith('v') && cleanTag.length > 1) {
      return cleanTag.substring(1);
    }
    return cleanTag.isEmpty ? 'Unknown' : cleanTag;
  }
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
      final release = releases.cast<Map<String, dynamic>?>().firstWhere(
        (raw) {
          if (raw == null) return false;
          final prerelease = raw['prerelease'] == true;
          final tag = (raw['tag_name'] ?? '').toString().toLowerCase();
          final nightly = prerelease || tag.contains('nightly');
          return channel == ReleaseUpdateChannel.nightly ? nightly : !nightly;
        },
        orElse: () => null,
      );
      if (release == null) {
        throw const FormatException('No matching release found.');
      }
      return _fromReleaseJson(release, channel, checkedAt);
    } catch (_) {
      return fallbackReleaseInfo(channel, checkedAt: checkedAt);
    } finally {
      if (_client == null) client.close();
    }
  }

  ReleaseUpdateInfo _fromReleaseJson(
    Map<String, dynamic> json,
    ReleaseUpdateChannel channel,
    DateTime checkedAt,
  ) {
    final tag = (json['tag_name'] ?? '').toString().trim();
    final name = (json['name'] ?? tag).toString().trim();
    final body = (json['body'] ?? '').toString().trim();
    final publishedAt = DateTime.tryParse(
      (json['published_at'] ?? '').toString(),
    )?.toLocal();
    return ReleaseUpdateInfo(
      channel: channel,
      name: name.isEmpty ? tag : name,
      tag: tag,
      body: body.isEmpty ? fallbackChangelog(channel) : body,
      publishedAt: publishedAt,
      checkedAt: checkedAt,
      fromFallback: false,
    );
  }
}

ReleaseUpdateChannel releaseChannelForVersion(String versionName) {
  return versionName.toLowerCase().contains('nightly')
      ? ReleaseUpdateChannel.nightly
      : ReleaseUpdateChannel.stable;
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
