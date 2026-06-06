import 'p2p_stream_bridge.dart';
import 'playback_provider.dart';

typedef PlaybackSourceClassAllowed = bool Function(PlaybackSourceClass value);

const p2pPriorityModeSmartStart = 'smartStart';
const p2pPriorityModeQualityFirst = 'qualityFirst';
const p2pPriorityModeAvailabilityFirst = 'availabilityFirst';
const p2pPriorityModeSmallerFasterFiles = 'smallerFasterFiles';
const p2pPriorityModeBalancedQualityAvailability =
    'balancedQualityAvailability';
const p2pAudioLanguageFollowPlayback = 'followPlayback';

class P2pPriorityConfig {
  const P2pPriorityConfig({
    this.enabled = false,
    this.mode = p2pPriorityModeSmartStart,
    this.resultsPerQuality = 3,
    this.preferredAudioLanguageMode = p2pAudioLanguageFollowPlayback,
    this.avoidRiskyFormats = true,
    this.sizeLimitMb = 0,
  });

  final bool enabled;
  final String mode;
  final int resultsPerQuality;
  final String preferredAudioLanguageMode;
  final bool avoidRiskyFormats;
  final int sizeLimitMb;
}

List<PlaybackSource> rankedNativePlaybackSources(
  List<PlaybackSource> sources, {
  required PlaybackSourceClassAllowed sourceClassAllowed,
  P2pPriorityConfig p2pConfig = const P2pPriorityConfig(),
}) {
  final indexed = <_IndexedPlaybackSource>[
    for (var index = 0; index < sources.length; index++)
      _IndexedPlaybackSource(sources[index], index),
  ];
  indexed.sort((left, right) {
    final leftClassRank = sourceClassRank(left.source, sourceClassAllowed);
    final rightClassRank = sourceClassRank(right.source, sourceClassAllowed);
    final classCompare = leftClassRank.compareTo(rightClassRank);
    if (classCompare != 0) return classCompare;

    final leftIsP2p = left.source.sourceClass == PlaybackSourceClass.p2p;
    final rightIsP2p = right.source.sourceClass == PlaybackSourceClass.p2p;
    if (leftIsP2p && rightIsP2p) {
      final p2pCompare = compareP2pSources(
        left.source,
        right.source,
        p2pConfig,
      );
      if (p2pCompare != 0) return p2pCompare;
    } else {
      final nonP2pCompare = _compareNonP2pSources(left.source, right.source);
      if (nonP2pCompare != 0) return nonP2pCompare;
    }

    return left.index.compareTo(right.index);
  });

  final ranked = indexed.map((item) => item.source).toList(growable: false);
  return limitP2pResultsPerQuality(ranked, p2pConfig);
}

int sourceClassRank(
  PlaybackSource source,
  PlaybackSourceClassAllowed sourceClassAllowed,
) {
  if (!sourceClassAllowed(source.sourceClass)) return 90;
  return switch (source.sourceClass) {
    PlaybackSourceClass.direct || PlaybackSourceClass.debrid => 0,
    PlaybackSourceClass.p2p => 1,
    PlaybackSourceClass.external => 2,
    PlaybackSourceClass.unsupported => 99,
  };
}

int compareP2pSources(
  PlaybackSource left,
  PlaybackSource right,
  P2pPriorityConfig config,
) {
  final effectiveConfig = config.enabled ? config : const P2pPriorityConfig();
  final leftScore = _P2pSourceScore.fromSource(left, effectiveConfig);
  final rightScore = _P2pSourceScore.fromSource(right, effectiveConfig);
  final mode = switch (effectiveConfig.mode) {
    p2pPriorityModeQualityFirst => p2pPriorityModeQualityFirst,
    p2pPriorityModeAvailabilityFirst => p2pPriorityModeAvailabilityFirst,
    p2pPriorityModeSmallerFasterFiles => p2pPriorityModeSmallerFasterFiles,
    p2pPriorityModeBalancedQualityAvailability =>
      p2pPriorityModeBalancedQualityAvailability,
    _ => p2pPriorityModeSmartStart,
  };

  final result = switch (mode) {
    p2pPriorityModeQualityFirst => _compareScoreParts(leftScore, rightScore, [
      (score) => -score.qualityRank,
      (score) => score.riskRank,
      (score) => -score.healthRank,
      (score) => -score.trackerCount,
      (score) => score.fileIndexRank,
      (score) => score.sizeRank,
    ]),
    p2pPriorityModeAvailabilityFirst =>
      _compareScoreParts(leftScore, rightScore, [
        (score) => -score.healthRank,
        (score) => -score.trackerCount,
        (score) => score.riskRank,
        (score) => score.openQualityRank,
        (score) => score.fileIndexRank,
        (score) => score.sizeRank,
      ]),
    p2pPriorityModeSmallerFasterFiles =>
      _compareScoreParts(leftScore, rightScore, [
        (score) => score.sizeLimitPenalty,
        (score) => score.sizeRank,
        (score) => score.riskRank,
        (score) => -score.healthRank,
        (score) => score.openQualityRank,
        (score) => score.fileIndexRank,
      ]),
    p2pPriorityModeBalancedQualityAvailability =>
      _compareScoreParts(leftScore, rightScore, [
        (score) => score.balancedRank,
        (score) => -score.healthRank,
        (score) => score.riskRank,
        (score) => score.openQualityRank,
        (score) => -score.trackerCount,
        (score) => score.fileIndexRank,
        (score) => score.sizeRank,
      ]),
    _ => _compareScoreParts(leftScore, rightScore, [
      (score) => score.openabilityRank,
      (score) => score.riskRank,
      (score) => score.openQualityRank,
      (score) => -score.healthRank,
      (score) => -score.trackerCount,
      (score) => score.fileIndexRank,
    ]),
  };
  return result;
}

List<PlaybackSource> limitP2pResultsPerQuality(
  List<PlaybackSource> ranked,
  P2pPriorityConfig config,
) {
  if (!config.enabled) return ranked.toList(growable: false);
  final maxPerQuality = config.resultsPerQuality.clamp(1, 5).toInt();
  final qualityCounts = <String, int>{};
  final limited = <PlaybackSource>[];
  for (final source in ranked) {
    if (source.sourceClass != PlaybackSourceClass.p2p) {
      limited.add(source);
      continue;
    }
    final quality = playbackQualityLabel(_sourceWithDescriptorQuality(source));
    final count = qualityCounts[quality] ?? 0;
    if (count >= maxPerQuality) continue;
    qualityCounts[quality] = count + 1;
    limited.add(source);
  }
  return limited;
}

int? p2pSeederCount(String text) {
  final normalized = text.toLowerCase();
  final patterns = <RegExp>[
    RegExp(r'\b(?:s|seeds?|seeders?)\s*[:=]\s*(\d{1,6})\b'),
    RegExp(r'\b(\d{1,6})\s*(?:seeds?|seeders?)\b'),
    RegExp(r'\b(\d{1,6})\s*/\s*\d{1,6}\b'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    if (match == null) continue;
    final value = int.tryParse(match.group(1) ?? '');
    if (value != null) return value;
  }
  return null;
}

double? p2pSourceSizeGb(String text) {
  final normalized = text.toLowerCase();
  final match = RegExp(
    r'\b(\d+(?:[.,]\d+)?)\s*(gib|gb|mib|mb)\b',
  ).firstMatch(normalized);
  if (match == null) return null;
  final value = double.tryParse((match.group(1) ?? '').replaceAll(',', '.'));
  if (value == null) return null;
  final unit = match.group(2) ?? '';
  if (unit == 'mb' || unit == 'mib') return value / 1024;
  return value;
}

String p2pSourceRankText(PlaybackSource source) {
  final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
  return [
    source.name,
    source.type,
    source.quality,
    descriptor?.displayName,
    descriptor?.quality,
  ].whereType<String>().join(' ');
}

int p2pPlaybackHealthRank(PlaybackSource source) {
  final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
  return _p2pPlaybackHealthRank(p2pSourceRankText(source), descriptor);
}

int p2pPlaybackRiskRank(
  PlaybackSource source, {
  P2pPriorityConfig config = const P2pPriorityConfig(),
}) {
  final effectiveConfig = config.enabled ? config : const P2pPriorityConfig();
  return _p2pPlaybackRiskRank(p2pSourceRankText(source), effectiveConfig);
}

int _compareNonP2pSources(PlaybackSource left, PlaybackSource right) {
  final qualityCompare = playbackQualityRank(
    playbackQualityLabel(right),
  ).compareTo(playbackQualityRank(playbackQualityLabel(left)));
  if (qualityCompare != 0) return qualityCompare;
  return playbackLanguageRank(
    playbackSourceLanguageLabel(left),
  ).compareTo(playbackLanguageRank(playbackSourceLanguageLabel(right)));
}

int _compareScoreParts(
  _P2pSourceScore left,
  _P2pSourceScore right,
  List<int Function(_P2pSourceScore score)> selectors,
) {
  for (final selector in selectors) {
    final compare = selector(left).compareTo(selector(right));
    if (compare != 0) return compare;
  }
  return 0;
}

PlaybackSource _sourceWithDescriptorQuality(PlaybackSource source) {
  final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
  final quality =
      source.quality ?? descriptor?.quality ?? descriptor?.displayName;
  if (quality == source.quality) return source;
  return source.copyWith(quality: quality);
}

class _IndexedPlaybackSource {
  const _IndexedPlaybackSource(this.source, this.index);

  final PlaybackSource source;
  final int index;
}

class _P2pSourceScore {
  const _P2pSourceScore({
    required this.openabilityRank,
    required this.riskRank,
    required this.openQualityRank,
    required this.qualityRank,
    required this.healthRank,
    required this.trackerCount,
    required this.fileIndexRank,
    required this.sizeRank,
    required this.sizeLimitPenalty,
  });

  factory _P2pSourceScore.fromSource(
    PlaybackSource source,
    P2pPriorityConfig config,
  ) {
    final descriptor = P2pStreamDescriptor.fromSyntheticUrl(source.url);
    final rankText = p2pSourceRankText(source);
    final qualitySource = _sourceWithDescriptorQuality(source);
    final qualityLabel = playbackQualityLabel(qualitySource);
    final sizeGb = p2pSourceSizeGb(rankText);
    final sizeLimitGb = config.sizeLimitMb > 0 ? config.sizeLimitMb / 1024 : 0;
    final riskRank = _p2pPlaybackRiskRank(rankText, config);
    final healthRank = _p2pPlaybackHealthRank(rankText, descriptor);
    final openQualityRank = _p2pOpenQualityRank(qualityLabel);
    return _P2pSourceScore(
      openabilityRank: descriptor == null
          ? 2
          : descriptor.trackers.isEmpty
          ? 1
          : 0,
      riskRank: riskRank,
      openQualityRank: openQualityRank,
      qualityRank: playbackQualityRank(qualityLabel),
      healthRank: healthRank,
      trackerCount: descriptor?.trackers.length ?? 0,
      fileIndexRank: descriptor?.fileIdx ?? 9999,
      sizeRank: sizeGb == null ? 999999 : (sizeGb * 1000).round(),
      sizeLimitPenalty:
          sizeLimitGb > 0 && sizeGb != null && sizeGb > sizeLimitGb ? 1000 : 0,
    );
  }

  final int openabilityRank;
  final int riskRank;
  final int openQualityRank;
  final int qualityRank;
  final int healthRank;
  final int trackerCount;
  final int fileIndexRank;
  final int sizeRank;
  final int sizeLimitPenalty;

  int get balancedRank {
    final cappedHealth = healthRank.clamp(0, 5).toInt();
    return sizeLimitPenalty +
        (riskRank * 4) +
        ((5 - cappedHealth) * 3) +
        (openQualityRank * 2);
  }
}

int _p2pPlaybackHealthRank(String text, P2pStreamDescriptor? descriptor) {
  final seeders = p2pSeederCount(text);
  final seederRank = switch (seeders ?? -1) {
    >= 200 => 5,
    >= 75 => 4,
    >= 20 => 3,
    >= 5 => 2,
    >= 1 => 1,
    _ => 0,
  };
  final trackerRank = (descriptor?.trackers.length ?? 0).clamp(0, 3).toInt();
  return seederRank + trackerRank;
}

int _p2pPlaybackRiskRank(String text, P2pPriorityConfig config) {
  final normalized = text.toLowerCase();
  var risk = 0;
  if (RegExp(
    r'\b(hevc|h\.?265|x265|10\s*bit|10bit|hdr|dv)\b',
  ).hasMatch(normalized)) {
    risk += config.avoidRiskyFormats ? 4 : 1;
  }
  if (RegExp(
    r'\b(dolby\s*vision|dovi|truehd|atmos|dts[-\s]?hd)\b',
  ).hasMatch(normalized)) {
    risk += config.avoidRiskyFormats ? 3 : 1;
  }
  if (RegExp(r'\b(cam|ts|telesync|hdcam|xbet)\b').hasMatch(normalized)) {
    risk += 2;
  }
  final sizeGb = p2pSourceSizeGb(text);
  if (sizeGb != null && config.sizeLimitMb > 0) {
    final sizeLimitGb = config.sizeLimitMb / 1024;
    if (sizeGb > sizeLimitGb) risk += 20;
  }
  return risk;
}

int _p2pOpenQualityRank(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('720')) return 0;
  if (normalized.contains('1080')) return 1;
  if (normalized.contains('480') || normalized.contains('360')) return 2;
  if (normalized == 'auto') return 3;
  if (normalized.contains('4k') || normalized.contains('2160')) return 4;
  return 5;
}
