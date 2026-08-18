const _tvMatureContentPattern =
    r'\b(adult|nsfw|xxx|porn|pornography|erotic|explicit|softcore|sexploitation|sexuality|sexual|sex|nudity|nude|naked|striptease|hentai|seduction|seduce|lust|desire|affair|mistress|virgin|scandal)\b';

bool tvShowMatureContentFromJson(Map<String, dynamic> json) =>
    json['showMatureContent'] == true;

Map<String, String> tvMatureCatalogQuery(bool showMatureContent) =>
    showMatureContent ? const {'allowMature': 'true'} : const {};

bool tvShouldShowCatalogItem({
  required bool showMatureContent,
  required bool hasMatureContentSignal,
}) =>
    showMatureContent || !hasMatureContentSignal;

bool tvHasMatureContentSignal(Map<String, dynamic> json) {
  final type = (json['type'] ?? '').toString().trim().toLowerCase();
  if (json['adult'] == true || type == 'nsfw' || type == 'adult') return true;

  final textParts = <String>[
    (json['name'] ?? json['title'] ?? '').toString(),
    (json['description'] ?? json['overview'] ?? '').toString(),
  ];
  for (final value in [json['genres'], json['genre']]) {
    if (value is Iterable) {
      textParts.addAll(value.map((entry) => entry.toString()));
    } else if (value != null) {
      textParts.add(value.toString());
    }
  }
  final text = textParts.join(' ').toLowerCase();
  if (text.trim().isEmpty) return false;
  return RegExp(_tvMatureContentPattern).hasMatch(text) ||
      RegExp(r'\b(vivamax|viva\s*max)\b').hasMatch(text) ||
      RegExp(r'\bfifty\s+shades\b').hasMatch(text) ||
      RegExp(r'\b365\s+days\b').hasMatch(text);
}
