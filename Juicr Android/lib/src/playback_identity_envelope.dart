import 'catalog_item.dart';

const Set<String> androidPlaybackIdentityPublicKeys = <String>{
  'id',
  'mediaType',
  'season',
  'episode',
  'title',
  'year',
  'imdbId',
  'tmdbId',
  'resolveMode',
  'recoveryAttempt',
};

Map<String, String> buildAndroidPlaybackIdentityEnvelope(
  CatalogItem item, {
  required bool series,
  int? season,
  int? episode,
  int? recoveryAttempt,
}) {
  if (series && ((season ?? 0) <= 0 || (episode ?? 0) <= 0)) {
    throw ArgumentError('Series playback requires positive episode identity.');
  }
  final canonicalId = _canonicalPlaybackId(item);
  if (canonicalId.isEmpty) {
    throw ArgumentError('Playback requires a canonical media identity.');
  }
  final query = <String, String>{
    'id': canonicalId,
    if (series) 'season': season.toString(),
    if (series) 'episode': episode.toString(),
    'mediaType': series ? 'series' : 'movie',
  };
  if (_routeIdentityMatches(item, canonicalId, series: series)) {
    final title = _sanitizedPlaybackTitle(item.name);
    if (title != null) query['title'] = title;
    final year = _validatedPlaybackYear(item.year);
    if (year != null) query['year'] = year;
    final externalIds = _identityConsistentExternalIds(item, canonicalId);
    query.addAll(externalIds);
  }
  if (recoveryAttempt != null) {
    query['resolveMode'] = 'recovery';
    query['recoveryAttempt'] = recoveryAttempt.clamp(0, 7).toString();
  }
  assert(query.keys.every(androidPlaybackIdentityPublicKeys.contains));
  return Map<String, String>.unmodifiable(query);
}

String _canonicalPlaybackId(CatalogItem item) {
  final raw = item.id.trim();
  final tmdbMatch = RegExp(
    r'^tmdb:(\d{1,12})$',
    caseSensitive: false,
  ).firstMatch(raw);
  return tmdbMatch?.group(1) ?? raw;
}

bool _routeIdentityMatches(
  CatalogItem item,
  String canonicalId, {
  required bool series,
}) {
  if (item.type.isPlayableSeries != series) return false;
  final normalizedCanonical = canonicalId.toLowerCase();
  if (_isValidatedImdbId(normalizedCanonical)) {
    final metadataImdb = item.imdbId?.trim().toLowerCase() ?? '';
    return metadataImdb.isEmpty || metadataImdb == normalizedCanonical;
  }
  if (RegExp(r'^\d{1,12}$').hasMatch(canonicalId)) {
    final metadataTmdb = item.tmdbId;
    return metadataTmdb == null || metadataTmdb.toString() == canonicalId;
  }
  return item.tmdbId == null && (item.imdbId?.trim().isEmpty ?? true);
}

String? _sanitizedPlaybackTitle(String value) {
  final collapsed = value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty || collapsed.toLowerCase() == 'untitled') return null;
  return String.fromCharCodes(collapsed.runes.take(160));
}

String? _validatedPlaybackYear(String? value) {
  final clean = value?.trim() ?? '';
  return RegExp(r'^(?:19|20)\d{2}$').hasMatch(clean) ? clean : null;
}

Map<String, String> _identityConsistentExternalIds(
  CatalogItem item,
  String canonicalId,
) {
  final normalizedCanonical = canonicalId.toLowerCase();
  final metadataImdb = item.imdbId?.trim().toLowerCase() ?? '';
  if (_isValidatedImdbId(normalizedCanonical)) {
    return metadataImdb == normalizedCanonical
        ? <String, String>{'imdbId': normalizedCanonical}
        : const <String, String>{};
  }
  if (!RegExp(r'^\d{1,12}$').hasMatch(canonicalId)) {
    return const <String, String>{};
  }
  final metadataTmdb = item.tmdbId;
  if (metadataTmdb == null || metadataTmdb.toString() != canonicalId) {
    return const <String, String>{};
  }
  return <String, String>{
    'tmdbId': canonicalId,
    if (_isValidatedImdbId(metadataImdb)) 'imdbId': metadataImdb,
  };
}

bool _isValidatedImdbId(String value) =>
    RegExp(r'^tt\d{5,12}$', caseSensitive: false).hasMatch(value);
