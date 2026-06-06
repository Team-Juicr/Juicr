String juicrCopyWithoutRepeatedTitlePhrase({
  required String title,
  required String subtitle,
}) {
  final cleanTitle = title.trim();
  var cleanSubtitle = subtitle.trim();
  if (cleanTitle.isEmpty || cleanSubtitle.isEmpty) return cleanSubtitle;

  final titleWords = _copyWords(cleanTitle);
  if (titleWords.isEmpty) return cleanSubtitle;
  final subtitleWords = _copyWords(cleanSubtitle);
  if (_sameWords(titleWords, subtitleWords)) return '';

  final phrase = RegExp.escape(cleanTitle);
  cleanSubtitle = cleanSubtitle.replaceAll(
    RegExp('^$phrase[\\s,.;:!?-]*', caseSensitive: false),
    '',
  );
  cleanSubtitle = cleanSubtitle.replaceAll(
    RegExp('[\\s,;:-]+$phrase([\\s,.;:!?-]*\$)', caseSensitive: false),
    '.',
  );
  cleanSubtitle = cleanSubtitle.replaceAll(
    RegExp('[\\s,;:-]+$phrase[\\s,;:-]+', caseSensitive: false),
    ' ',
  );
  final normalized = _normalizeDisplaySentence(
    _copyWithoutAdjacentDuplicateWords(cleanSubtitle),
  );
  return _isWeakSubtitleFragment(normalized)
      ? _normalizeDisplaySentence(_copyWithoutAdjacentDuplicateWords(subtitle))
      : normalized;
}

List<String> _copyWords(String value) {
  return RegExp(r"[a-z0-9]+")
      .allMatches(value.toLowerCase())
      .map((match) => match.group(0)!)
      .toList(growable: false);
}

bool _sameWords(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _copyWithoutAdjacentDuplicateWords(String value) {
  return value.replaceAllMapped(
    RegExp(r'\b([a-z0-9]+)([\s,.;:!?-]+\1\b)+', caseSensitive: false),
    (match) => match.group(1)!,
  );
}

String _normalizeDisplaySentence(String value) {
  var normalized = value.trim();
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
  normalized = normalized.replaceAllMapped(
    RegExp(r'\s+([,.;:!?])'),
    (match) => match.group(1)!,
  );
  normalized = normalized.replaceAll(RegExp(r'^[,.;:!?-]+\s*'), '');
  normalized = normalized.replaceAll(RegExp(r'\s*[,;:-]+\s*$'), '.');
  normalized = normalized.replaceAll(RegExp(r'\.{2,}$'), '.');
  return normalized.trim();
}

bool _isWeakSubtitleFragment(String value) {
  final words = _copyWords(value);
  if (words.length < 4) return true;
  return RegExp(
    r'^(and|or|but|with|for|from|to|of|in|on|at|by|when|while|that|who|where)\b',
    caseSensitive: false,
  ).hasMatch(value.trim());
}
