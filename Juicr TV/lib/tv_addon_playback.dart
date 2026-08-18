import 'tv_p2p_stream_bridge.dart';

class TvAddonPlaybackCandidate {
  const TvAddonPlaybackCandidate({
    required this.mediaUrl,
    required this.sourceType,
    required this.sourceClass,
    required this.quality,
    required this.compatibilityRisk,
    required this.headers,
    required this.sourceId,
    required this.subtitles,
    this.p2pDescriptor,
  });

  final String mediaUrl;
  final String sourceType;
  final String sourceClass;
  final String quality;
  final int compatibilityRisk;
  final Map<String, String> headers;
  final String sourceId;
  final List<Map<String, dynamic>> subtitles;
  final TvP2pStreamDescriptor? p2pDescriptor;

  @override
  String toString() {
    return 'TvAddonPlaybackCandidate(type=$sourceType, class=$sourceClass, '
        'quality=$quality, p2p=${p2pDescriptor == null ? 'absent' : 'present'})';
  }
}

List<String> tvAddonPlaybackRequestIds({
  required String id,
  int? tmdbId,
  String? imdbId,
  int? season,
  int? episode,
}) {
  final base = <String>[
    if ((imdbId ?? '').trim().isNotEmpty) imdbId!.trim(),
    id.trim(),
    if (tmdbId != null) tmdbId.toString(),
  ];
  final unique = <String>[];
  for (final value in base) {
    if (value.isEmpty || unique.contains(value)) continue;
    unique.add(value);
  }
  if (season == null || episode == null) return unique;
  return unique
      .map((value) => '$value:$season:$episode')
      .toList(growable: false);
}

List<TvAddonPlaybackCandidate> parseTvAddonPlaybackCandidates(
  Object? value, {
  required String sourceId,
  bool allowP2p = false,
}) {
  if (value is! List) return const <TvAddonPlaybackCandidate>[];
  final candidates = <TvAddonPlaybackCandidate>[];
  final seen = <String>{};
  var p2pOrdinal = 0;
  for (final raw in value.whereType<Map>()) {
    final stream = Map<String, dynamic>.from(raw);
    final p2pDescriptor = TvP2pStreamDescriptor.fromAddonStream(stream);
    if (p2pDescriptor.isUsable) {
      if (!allowP2p) continue;
      p2pOrdinal += 1;
      candidates.add(
        TvAddonPlaybackCandidate(
          mediaUrl: 'juicr-p2p://pending/$p2pOrdinal',
          sourceType: 'p2p',
          sourceClass: 'p2p',
          quality: _tvAddonQuality(stream),
          compatibilityRisk: _tvAddonCompatibilityRisk(stream),
          headers: const <String, String>{},
          sourceId: sourceId,
          subtitles: _tvAddonMaps(stream['subtitles']),
          p2pDescriptor: p2pDescriptor,
        ),
      );
      continue;
    }
    final url = (stream['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || !seen.add(url)) continue;
    final sourceType = _tvAddonSourceType(stream, url);
    if (sourceType == null) continue;
    candidates.add(
      TvAddonPlaybackCandidate(
        mediaUrl: url,
        sourceType: sourceType,
        sourceClass: _tvAddonLooksAccountBacked(stream, url)
            ? 'debrid'
            : 'direct',
        quality: _tvAddonQuality(stream),
        compatibilityRisk: _tvAddonCompatibilityRisk(stream),
        headers: _tvAddonHeaders(stream),
        sourceId: sourceId,
        subtitles: _tvAddonMaps(stream['subtitles']),
      ),
    );
  }
  return candidates;
}

String? _tvAddonSourceType(Map<String, dynamic> stream, String url) {
  final raw = (stream['type'] ?? '').toString().trim().toLowerCase();
  if (raw == 'hls' ||
      raw == 'm3u8' ||
      raw == 'application/x-mpegurl' ||
      raw == 'application/vnd.apple.mpegurl') {
    return 'hls';
  }
  if (raw == 'dash' || raw == 'mpd' || raw == 'application/dash+xml') {
    return 'dash';
  }
  if (raw == 'mp4' ||
      raw == 'video' ||
      raw == 'video/mp4' ||
      raw == 'application/mp4') {
    return 'mp4';
  }
  final lowerUrl = url.toLowerCase();
  if (lowerUrl.contains('.m3u8')) return 'hls';
  if (lowerUrl.contains('.mpd')) return 'dash';
  if (lowerUrl.contains('.mp4') || lowerUrl.contains('.m4v')) return 'mp4';
  if (_tvAddonLooksAccountBacked(stream, url)) return 'mp4';
  return null;
}

bool _tvAddonLooksAccountBacked(Map<String, dynamic> stream, String url) {
  final text = <Object?>[
    stream['name'],
    stream['title'],
    stream['description'],
    stream['behaviorHints'],
    url,
  ].whereType<Object>().join(' ').toLowerCase();
  return text.contains('debrid') ||
      text.contains('cached') ||
      text.contains('premium') ||
      text.contains('usenet') ||
      text.contains('account');
}

String _tvAddonQuality(Map<String, dynamic> stream) {
  final text = <Object?>[
    stream['name'],
    stream['title'],
    stream['description'],
  ].whereType<Object>().join(' ');
  final match = RegExp(
    r'\b(2160p|1440p|1080p|720p|576p|480p|360p|240p|4k)\b',
    caseSensitive: false,
  ).firstMatch(text);
  final value = match?.group(1)?.toUpperCase();
  return value == '4K' ? '2160P' : value ?? 'Auto';
}

int _tvAddonCompatibilityRisk(Map<String, dynamic> stream) {
  final text = <Object?>[
    stream['name'],
    stream['title'],
    stream['description'],
    stream['behaviorHints'],
  ].whereType<Object>().join(' ').toLowerCase();
  var risk = 0;
  final highEfficiency = RegExp(
    r'\b(hevc|h\.?265|x265|hvc1|10\s*bit|10bit|hdr)\b',
  ).hasMatch(text);
  if (highEfficiency) risk += 4;
  if (RegExp(r'\b(dolby\s*vision|dovi|dvhe|truehd|atmos|dts[-\s]?hd)\b')
      .hasMatch(text)) {
    risk += 3;
  }
  if (RegExp(r'\b(av1|vp9)\b').hasMatch(text)) risk += 2;
  final broadlyCompatible = RegExp(r'\b(avc|h\.?264|x264)\b').hasMatch(text);
  if (!broadlyCompatible && !highEfficiency && risk == 0) return 1;
  return risk;
}

Map<String, String> _tvAddonHeaders(Map<String, dynamic> stream) {
  final headers = <String, String>{};
  void add(Object? value) {
    if (value is! Map) return;
    for (final entry in value.entries) {
      final name = entry.key.toString().trim();
      final headerValue = entry.value?.toString().trim() ?? '';
      if (name.isNotEmpty && headerValue.isNotEmpty) {
        headers[name] = headerValue;
      }
    }
  }

  add(stream['headers']);
  final hints = stream['behaviorHints'];
  if (hints is Map) {
    final proxyHeaders = hints['proxyHeaders'];
    if (proxyHeaders is Map) add(proxyHeaders['request']);
  }
  return headers;
}

List<Map<String, dynamic>> _tvAddonMaps(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}
