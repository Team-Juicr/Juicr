class JuicrLanguageOption {
  const JuicrLanguageOption({
    required this.label,
    required this.code,
    this.unknown = false,
  });

  const JuicrLanguageOption.any() : this(label: 'Any language', code: '');

  const JuicrLanguageOption.unknown()
    : this(label: 'Language unknown', code: 'unknown', unknown: true);

  final String label;
  final String code;
  final bool unknown;

  bool get isAny => code.isEmpty;

  String get shortLabel => isAny ? 'Any' : label;

  @override
  bool operator ==(Object other) {
    return other is JuicrLanguageOption &&
        other.code == code &&
        other.unknown == unknown;
  }

  @override
  int get hashCode => Object.hash(code, unknown);
}

const List<JuicrLanguageOption> juicrCatalogLanguageOptions = [
  JuicrLanguageOption.any(),
  JuicrLanguageOption.unknown(),
];

List<JuicrLanguageOption> juicrLanguageOptionsFromJson(dynamic value) {
  final seen = <String>{};
  final options = <JuicrLanguageOption>[const JuicrLanguageOption.any()];
  if (value is Iterable) {
    for (final item in value) {
      final option = _languageOptionFromJson(item);
      if (option == null || !seen.add(option.code)) continue;
      options.add(option);
    }
  }
  options.sort((left, right) {
    if (left.isAny) return -1;
    if (right.isAny) return 1;
    return left.label.toLowerCase().compareTo(right.label.toLowerCase());
  });
  options.add(const JuicrLanguageOption.unknown());
  return options.length > 2
      ? List.unmodifiable(options)
      : juicrCatalogLanguageOptions;
}

JuicrLanguageOption? _languageOptionFromJson(dynamic value) {
  if (value is Map) {
    final code = _normalizeLanguageCode(value['code']?.toString());
    if (code.isEmpty || code == 'unknown') return null;
    final rawLabel = (value['label'] ?? value['englishName'] ?? value['name'])
        ?.toString()
        .trim();
    final label = rawLabel == null || rawLabel.isEmpty
        ? code.toUpperCase()
        : rawLabel;
    return JuicrLanguageOption(label: label, code: code);
  }
  final code = _normalizeLanguageCode(value?.toString());
  if (code.isEmpty || code == 'unknown') return null;
  return JuicrLanguageOption(label: code.toUpperCase(), code: code);
}

JuicrLanguageOption juicrLanguageOptionForCode(String? rawCode) {
  return juicrLanguageOptionForCodeIn(rawCode, juicrCatalogLanguageOptions);
}

JuicrLanguageOption juicrLanguageOptionForCodeIn(
  String? rawCode,
  List<JuicrLanguageOption> options,
) {
  final code = _normalizeLanguageCode(rawCode);
  if (code.isEmpty) return const JuicrLanguageOption.any();
  return options.firstWhere(
    (option) => option.code == code,
    orElse: () => code == 'unknown'
        ? const JuicrLanguageOption.unknown()
        : JuicrLanguageOption(label: code.toUpperCase(), code: code),
  );
}

String juicrLanguageLabelForCode(String? rawCode) {
  final option = juicrLanguageOptionForCode(rawCode);
  return option.isAny ? 'Language unknown' : option.label;
}

String juicrCatalogLanguageCode(String? rawCode) {
  final code = _normalizeLanguageCode(rawCode);
  if (code == 'unknown') return '';
  return code;
}

String _normalizeLanguageCode(String? rawCode) {
  final value = (rawCode ?? '').trim().toLowerCase();
  if (value.isEmpty) return '';
  if (value == 'unknown' || value == 'und' || value == 'null') {
    return 'unknown';
  }
  final normalized = value.replaceAll('_', '-');
  final match = RegExp(r'^[a-z]{2,3}').firstMatch(normalized);
  return match?.group(0) ?? '';
}
