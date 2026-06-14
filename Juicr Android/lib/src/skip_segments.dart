import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String _defaultSkipSegmentsBaseUrl = 'https://api.juicr.app';
const String _compileTimeSkipSegmentsEndpoint = String.fromEnvironment(
  'JUICR_SKIP_SEGMENTS_ENDPOINT',
  defaultValue: '',
);

enum PlaybackSkipSegmentKind {
  intro,
  recap,
  outro,
  preview;

  String get label {
    return switch (this) {
      PlaybackSkipSegmentKind.intro => 'Skip intro',
      PlaybackSkipSegmentKind.recap => 'Skip recap',
      PlaybackSkipSegmentKind.outro => 'Skip outro',
      PlaybackSkipSegmentKind.preview => 'Skip preview',
    };
  }

  static PlaybackSkipSegmentKind? fromValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'intro' || 'opening' => PlaybackSkipSegmentKind.intro,
      'recap' || 'previously' => PlaybackSkipSegmentKind.recap,
      'outro' || 'credits' || 'ending' => PlaybackSkipSegmentKind.outro,
      'preview' || 'next' => PlaybackSkipSegmentKind.preview,
      _ => null,
    };
  }
}

class PlaybackSkipSegment {
  const PlaybackSkipSegment({
    required this.kind,
    required this.start,
    required this.end,
  });

  final PlaybackSkipSegmentKind kind;
  final Duration start;
  final Duration end;

  String get label => kind.label;

  bool activeAt(Duration position, Duration duration) {
    if (duration <= Duration.zero || end <= start) return false;
    final clampedEnd = _targetWithinDuration(end, duration);
    if (clampedEnd <= position + const Duration(seconds: 2)) return false;
    return position >= start && position < end;
  }

  Duration targetFor(Duration duration) => _targetWithinDuration(end, duration);
}

class PlaybackSkipSegmentClient {
  PlaybackSkipSegmentClient({
    http.Client? client,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client(),
       _endpoint = endpoint ?? defaultPlaybackSkipSegmentEndpoint();

  final http.Client _client;
  final Uri _endpoint;
  final Duration timeout;

  Future<List<PlaybackSkipSegment>> lookup({
    required int? tmdbId,
    required String? imdbId,
    required int? season,
    required int? episode,
    Duration? duration,
  }) async {
    final cleanTmdbId = tmdbId != null && tmdbId > 0 ? tmdbId : null;
    final cleanImdbId = _cleanImdbId(imdbId);
    if ((cleanTmdbId == null && cleanImdbId == null) ||
        season == null ||
        season <= 0 ||
        episode == null ||
        episode <= 0) {
      return const <PlaybackSkipSegment>[];
    }
    if (!_endpoint.hasScheme || _endpoint.host.isEmpty) {
      return const <PlaybackSkipSegment>[];
    }
    final response = await _client
        .get(
          _endpoint.replace(
            queryParameters: <String, String>{
              ..._endpoint.queryParameters,
              if (cleanTmdbId != null) 'tmdb_id': cleanTmdbId.toString(),
              if (cleanImdbId != null) 'imdb_id': cleanImdbId,
              'season': season.toString(),
              'episode': episode.toString(),
              if (duration != null && duration > Duration.zero)
                'duration_ms': duration.inMilliseconds.toString(),
            },
          ),
        )
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const <PlaybackSkipSegment>[];
    }
    final decoded = jsonDecode(response.body);
    return parsePlaybackSkipSegments(decoded);
  }
}

Uri defaultPlaybackSkipSegmentEndpoint() {
  final override = _compileTimeSkipSegmentsEndpoint.trim();
  if (override.isNotEmpty) return Uri.parse(override);
  return Uri.parse(_defaultSkipSegmentsBaseUrl).resolve('/skip-segments');
}

PlaybackSkipSegment? activePlaybackSkipSegment(
  List<PlaybackSkipSegment> segments,
  Duration position,
  Duration duration,
) {
  for (final segment in segments) {
    if (segment.activeAt(position, duration)) return segment;
  }
  return null;
}

bool allowFixedSkipSegmentFallback({
  required int? season,
  required int? episode,
}) {
  return season == null || season <= 0 || episode == null || episode <= 0;
}

Duration defaultFixedIntroSkipTarget() => const Duration(seconds: 30);

List<PlaybackSkipSegment> parsePlaybackSkipSegments(Object? payload) {
  final entries = <PlaybackSkipSegment>[];
  for (final raw in _segmentCandidates(payload)) {
    final segment = _parseSegment(raw);
    if (segment != null) entries.add(segment);
  }
  entries.sort((left, right) {
    final startCompare = left.start.compareTo(right.start);
    if (startCompare != 0) return startCompare;
    return left.end.compareTo(right.end);
  });
  return entries;
}

Iterable<Map<String, Object?>> _segmentCandidates(Object? payload) sync* {
  if (payload is List) {
    for (final entry in payload) {
      if (entry is Map) yield Map<String, Object?>.from(entry);
    }
    return;
  }
  if (payload is! Map) return;
  final map = Map<String, Object?>.from(payload);
  final nested =
      map['segments'] ?? map['data'] ?? map['items'] ?? map['results'];
  if (nested is List) {
    yield* _segmentCandidates(nested);
    return;
  }
  var yieldedNamedSegment = false;
  for (final kind in PlaybackSkipSegmentKind.values) {
    final value = map[kind.name];
    if (value is Map) {
      yieldedNamedSegment = true;
      yield {
        ...Map<String, Object?>.from(value),
        'type': value['type'] ?? kind.name,
      };
    }
  }
  if (yieldedNamedSegment) return;
  if (_readDuration(map, const ['start', 'start_sec', 'start_time']) != null &&
      _readDuration(map, const ['end', 'end_sec', 'end_time']) != null) {
    yield map;
  }
}

PlaybackSkipSegment? _parseSegment(Map<String, Object?> raw) {
  final kind =
      PlaybackSkipSegmentKind.fromValue(
        raw['type'] ?? raw['kind'] ?? raw['segment_type'],
      ) ??
      PlaybackSkipSegmentKind.intro;
  final start = _readDuration(raw, const [
    'start',
    'start_sec',
    'start_time',
    'startSeconds',
    'startTime',
  ]);
  final end = _readDuration(raw, const [
    'end',
    'end_sec',
    'end_time',
    'endSeconds',
    'endTime',
  ]);
  if (start == null || end == null) return null;
  if (end <= start + const Duration(seconds: 2)) return null;
  return PlaybackSkipSegment(
    kind: kind,
    start: start < Duration.zero ? Duration.zero : start,
    end: end,
  );
}

Duration? _readDuration(Map<String, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final duration = _parseDuration(value);
    if (duration != null) return duration;
  }
  return null;
}

Duration? _parseDuration(Object? value) {
  if (value is num) {
    return Duration(milliseconds: (value * 1000).round());
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final numeric = num.tryParse(trimmed);
    if (numeric != null) {
      return Duration(milliseconds: (numeric * 1000).round());
    }
    final parts = trimmed.split(':');
    if (parts.length == 2 || parts.length == 3) {
      final values = parts.map((part) => num.tryParse(part)).toList();
      if (values.any((part) => part == null)) return null;
      final seconds = parts.length == 2
          ? (values[0]! * 60) + values[1]!
          : (values[0]! * 3600) + (values[1]! * 60) + values[2]!;
      return Duration(milliseconds: (seconds * 1000).round());
    }
  }
  return null;
}

Duration _targetWithinDuration(Duration target, Duration duration) {
  if (duration <= Duration.zero) return target;
  final latestTarget = duration - const Duration(seconds: 2);
  if (latestTarget <= Duration.zero) return target;
  return target > latestTarget ? latestTarget : target;
}

String? _cleanImdbId(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final match = RegExp(r'tt\d+', caseSensitive: false).firstMatch(trimmed);
  return match?.group(0)?.toLowerCase();
}
