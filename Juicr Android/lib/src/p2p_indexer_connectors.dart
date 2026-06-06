import 'dart:async';

import 'package:http/http.dart' as http;

import 'diagnostic_log.dart';
import 'p2p_stream_bridge.dart';
import 'playback_provider.dart';

enum P2pIndexerConnectorType { prowlarr, jackett }

extension P2pIndexerConnectorTypeInfo on P2pIndexerConnectorType {
  String get wireName {
    return switch (this) {
      P2pIndexerConnectorType.prowlarr => 'prowlarr',
      P2pIndexerConnectorType.jackett => 'jackett',
    };
  }

  String get label {
    return switch (this) {
      P2pIndexerConnectorType.prowlarr => 'Prowlarr',
      P2pIndexerConnectorType.jackett => 'Jackett',
    };
  }

  static P2pIndexerConnectorType fromWireName(String? value) {
    return switch ((value ?? '').trim().toLowerCase()) {
      'jackett' => P2pIndexerConnectorType.jackett,
      _ => P2pIndexerConnectorType.prowlarr,
    };
  }
}

class P2pIndexerConnector {
  const P2pIndexerConnector({
    required this.id,
    required this.type,
    required this.label,
    required this.baseUrl,
    required this.apiKey,
    required this.enabled,
    this.lastStatusBucket = 'not_checked',
    this.lastCheckedAt,
  });

  factory P2pIndexerConnector.fromJson(Map<String, dynamic> json) {
    return P2pIndexerConnector(
      id: _stringValue(json['id']),
      type: P2pIndexerConnectorTypeInfo.fromWireName(
        _stringValue(json['type']),
      ),
      label: _stringValue(json['label']),
      baseUrl: _stringValue(json['baseUrl'] ?? json['base_url']),
      apiKey: _stringValue(json['apiKey'] ?? json['api_key']),
      enabled: json['enabled'] != false,
      lastStatusBucket: _safeStatusBucket(
        _stringValue(json['lastStatusBucket'] ?? json['last_status_bucket']),
      ),
      lastCheckedAt: DateTime.tryParse(
        _stringValue(json['lastCheckedAt'] ?? json['last_checked_at']),
      ),
    );
  }

  final String id;
  final P2pIndexerConnectorType type;
  final String label;
  final String baseUrl;
  final String apiKey;
  final bool enabled;
  final String lastStatusBucket;
  final DateTime? lastCheckedAt;

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty;

  String get displayLabel {
    final trimmed = label.trim();
    return trimmed.isEmpty ? type.label : trimmed;
  }

  String get redactedDiagnostic {
    return 'type=${type.wireName} enabled=$enabled status=$lastStatusBucket '
        'url=[hidden] apiKey=[redacted]';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.wireName,
      'label': label,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'enabled': enabled,
      'lastStatusBucket': lastStatusBucket,
      if (lastCheckedAt != null)
        'lastCheckedAt': lastCheckedAt!.toUtc().toIso8601String(),
    };
  }

  P2pIndexerConnector copyWith({
    String? id,
    P2pIndexerConnectorType? type,
    String? label,
    String? baseUrl,
    String? apiKey,
    bool? enabled,
    String? lastStatusBucket,
    DateTime? lastCheckedAt,
  }) {
    return P2pIndexerConnector(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      enabled: enabled ?? this.enabled,
      lastStatusBucket: lastStatusBucket ?? this.lastStatusBucket,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

class P2pIndexerSearchRequest {
  const P2pIndexerSearchRequest({
    required this.mediaType,
    required this.title,
    this.year,
    this.season,
    this.episode,
  });

  final String mediaType;
  final String title;
  final int? year;
  final int? season;
  final int? episode;
}

class P2pIndexerCandidate {
  const P2pIndexerCandidate({
    required this.connectorId,
    required this.title,
    required this.sourceBucket,
    required this.seedersBucket,
    required this.sizeBucket,
    this.infoHash,
    this.trackers = const <String>[],
    this.quality,
  });

  final String connectorId;
  final String title;
  final String sourceBucket;
  final String seedersBucket;
  final String sizeBucket;
  final String? infoHash;
  final List<String> trackers;
  final String? quality;

  bool get hasUsableP2pDescriptor => (infoHash ?? '').trim().isNotEmpty;

  String get redactedDiagnostic {
    return 'connector=[redacted] source=$sourceBucket seeders=$seedersBucket '
        'size=$sizeBucket magnet=[hidden] infoHash=[hidden] url=[hidden]';
  }

  PlaybackSource toLockedPlaybackSource() {
    final p2pDescriptor = P2pStreamDescriptor(
      infoHash: (infoHash ?? '').trim(),
      trackers: trackers,
      displayName: title,
      quality: quality,
    );
    return PlaybackSource(
      providerId: 'p2p-indexer',
      name: 'Indexer P2P candidate',
      url: p2pDescriptor.syntheticUrl,
      type: 'p2p',
      quality: quality,
      sourceClass: PlaybackSourceClass.p2p,
    );
  }
}

class P2pIndexerConnectorClient {
  const P2pIndexerConnectorClient({http.Client? httpClient})
    : _httpClient = httpClient;

  final http.Client? _httpClient;

  Future<String> testConnection(
    P2pIndexerConnector connector, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uri = _buildUri(
      connector,
      const P2pIndexerSearchRequest(mediaType: 'movie', title: 'test'),
    );
    if (uri == null) return 'bad_url';
    DiagnosticLog.add(
      'native p2p indexer test start ${connector.redactedDiagnostic} uri=[hidden]',
    );
    final client = _httpClient ?? http.Client();
    try {
      final response = await client.get(uri).timeout(timeout);
      final bucket = _statusBucket(response.statusCode);
      DiagnosticLog.add(
        'native p2p indexer test result type=${connector.type.wireName} status=$bucket uri=[hidden]',
      );
      return bucket;
    } on TimeoutException {
      DiagnosticLog.add(
        'native p2p indexer test result type=${connector.type.wireName} status=timeout uri=[hidden]',
      );
      return 'timeout';
    } catch (error) {
      DiagnosticLog.add(
        'native p2p indexer test result type=${connector.type.wireName} status=unreachable error=${error.runtimeType} uri=[hidden]',
      );
      return 'unreachable';
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  Future<List<P2pIndexerCandidate>> search(
    P2pIndexerConnector connector,
    P2pIndexerSearchRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!connector.enabled || !connector.isConfigured) return const [];
    final uri = _buildUri(connector, request);
    if (uri == null) return const [];
    DiagnosticLog.add(
      'native p2p indexer search connector=${connector.type.wireName} uri=[hidden]',
    );
    final client = _httpClient ?? http.Client();
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        DiagnosticLog.add(
          'native p2p indexer search rejected connector=${connector.type.wireName} status=${_statusBucket(response.statusCode)} uri=[hidden]',
        );
        return const [];
      }
      final candidates = _parseTorznabItems(connector, response.body);
      DiagnosticLog.add(
        'native p2p indexer search ok connector=${connector.type.wireName} count=${_countBucket(candidates.length)} uri=[hidden]',
      );
      return candidates;
    } on TimeoutException {
      DiagnosticLog.add(
        'native p2p indexer search timeout connector=${connector.type.wireName} uri=[hidden]',
      );
      return const [];
    } catch (error) {
      DiagnosticLog.add(
        'native p2p indexer search failed connector=${connector.type.wireName} error=${error.runtimeType} uri=[hidden]',
      );
      return const [];
    } finally {
      if (_httpClient == null) client.close();
    }
  }

  Uri? _buildUri(
    P2pIndexerConnector connector,
    P2pIndexerSearchRequest request,
  ) {
    final base = Uri.tryParse(connector.baseUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    final path = switch (connector.type) {
      P2pIndexerConnectorType.prowlarr => _joinPath(base.path, 'api/v1/search'),
      P2pIndexerConnectorType.jackett => _joinPath(
        base.path,
        'api/v2.0/indexers/all/results/torznab/api',
      ),
    };
    final query = _queryFor(request);
    return base.replace(
      path: path,
      queryParameters: <String, String>{
        'apikey': connector.apiKey.trim(),
        't': request.season != null ? 'tvsearch' : 'search',
        'q': query,
        if (request.season != null) 'season': '${request.season}',
        if (request.episode != null) 'ep': '${request.episode}',
      },
    );
  }

  static String _joinPath(String basePath, String child) {
    final base = basePath.trim();
    if (base.isEmpty || base == '/') return '/$child';
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/$child';
  }

  static String _queryFor(P2pIndexerSearchRequest request) {
    final parts = <String>[request.title.trim()];
    if (request.year != null && request.year! > 1800) {
      parts.add('${request.year}');
    }
    return parts.where((part) => part.isNotEmpty).join(' ');
  }

  static List<P2pIndexerCandidate> _parseTorznabItems(
    P2pIndexerConnector connector,
    String body,
  ) {
    final itemMatches = RegExp(
      r'<item\b[\s\S]*?</item>',
      caseSensitive: false,
    ).allMatches(body);
    final candidates = <P2pIndexerCandidate>[];
    for (final match in itemMatches.take(24)) {
      final item = match.group(0) ?? '';
      final title = _xmlText(item, 'title');
      final magnet = _firstMagnet(item);
      candidates.add(
        P2pIndexerCandidate(
          connectorId: connector.id,
          title: title.isEmpty ? 'P2P result' : title,
          sourceBucket: connector.type.wireName,
          seedersBucket: _seedersBucket(item),
          sizeBucket: _sizeBucket(_xmlText(item, 'size')),
          infoHash: _infoHashFromMagnet(magnet),
          trackers: _trackersFromMagnet(magnet),
          quality: _qualityBucket(title),
        ),
      );
    }
    return candidates;
  }
}

String _stringValue(Object? value) => (value ?? '').toString().trim();

String _safeStatusBucket(String value) {
  const allowed = {
    'not_checked',
    'ok',
    'unauthorized',
    'unreachable',
    'bad_response',
    'bad_url',
    'timeout',
  };
  return allowed.contains(value) ? value : 'not_checked';
}

String _statusBucket(int statusCode) {
  if (statusCode == 401 || statusCode == 403) return 'unauthorized';
  if (statusCode >= 200 && statusCode < 300) return 'ok';
  if (statusCode >= 400 && statusCode < 500) return 'bad_response';
  if (statusCode >= 500) return 'unreachable';
  return 'bad_response';
}

String _countBucket(int count) {
  if (count <= 0) return '0';
  if (count == 1) return '1';
  if (count <= 4) return '2_to_4';
  if (count <= 12) return '5_to_12';
  return '13_plus';
}

String _xmlText(String body, String tag) {
  final match = RegExp(
    '<$tag(?: [^>]*)?>([\\s\\S]*?)</$tag>',
    caseSensitive: false,
  ).firstMatch(body);
  if (match == null) return '';
  return _decodeXml(match.group(1) ?? '').trim();
}

String _decodeXml(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

String _seedersBucket(String item) {
  final match = RegExp(
    r'''name=["'](?:seeders|grabs|peers)["'][^>]*value=["'](\d+)["']''',
    caseSensitive: false,
  ).firstMatch(item);
  final count = int.tryParse(match?.group(1) ?? '') ?? 0;
  if (count <= 0) return 'unknown';
  if (count < 5) return '1_to_4';
  if (count < 25) return '5_to_24';
  if (count < 100) return '25_to_99';
  return '100_plus';
}

String _sizeBucket(String value) {
  final bytes = int.tryParse(value.trim()) ?? 0;
  if (bytes <= 0) return 'unknown';
  final gb = bytes / (1024 * 1024 * 1024);
  if (gb < 1) return 'under_1gb';
  if (gb < 4) return '1_to_4gb';
  if (gb < 8) return '4_to_8gb';
  return '8gb_plus';
}

String? _qualityBucket(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('2160') || normalized.contains('4k')) return '2160P';
  if (normalized.contains('1080')) return '1080P';
  if (normalized.contains('720')) return '720P';
  if (normalized.contains('480')) return '480P';
  return null;
}

String _firstMagnet(String item) {
  final fields = <String>[_xmlText(item, 'link'), _xmlText(item, 'guid')];
  final attrMatch = RegExp(
    r'''url=["'](magnet:[^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(item);
  if (attrMatch != null) fields.add(_decodeXml(attrMatch.group(1) ?? ''));
  for (final field in fields) {
    final trimmed = field.trim();
    if (trimmed.toLowerCase().startsWith('magnet:')) return trimmed;
  }
  return '';
}

String? _infoHashFromMagnet(String magnet) {
  final match = RegExp(
    r'btih:([a-zA-Z0-9]{32,64})',
    caseSensitive: false,
  ).firstMatch(magnet);
  return match?.group(1)?.trim();
}

List<String> _trackersFromMagnet(String magnet) {
  final uri = Uri.tryParse(magnet);
  if (uri == null) return const <String>[];
  return uri.queryParametersAll['tr']
          ?.where((tracker) {
            final trimmed = tracker.trim();
            return trimmed.startsWith('udp://') ||
                trimmed.startsWith('http://') ||
                trimmed.startsWith('https://');
          })
          .toList(growable: false) ??
      const <String>[];
}
