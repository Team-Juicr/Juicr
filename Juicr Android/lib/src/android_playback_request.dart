import 'catalog_item.dart';
import 'playback_identity_envelope.dart';

const String androidPlaybackRequestContractVersion =
    'android-playback-request-v2';

const Map<String, String> androidPlaybackRequestHeaders = <String, String>{
  'user-agent': 'JuicrMobile/1 Flutter',
  'x-juicr-client': 'mobile',
  'x-juicr-client-version': '1',
  'x-juicr-capabilities':
      'playback_v2,source_pool,mirrors,playback_feedback,subtitle_v2,opaque_playback_session',
};

class AndroidPlaybackRequestSpec {
  const AndroidPlaybackRequestSpec({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> headers;

  Uri uri(String baseUrl) => Uri.parse(baseUrl).replace(
        path: path,
        queryParameters: query,
      );

  Map<String, Object> toProcessJson() => <String, Object>{
        'contractVersion': androidPlaybackRequestContractVersion,
        'method': method,
        'path': path,
        'query': query,
        'headers': headers,
        'signingInputs': const <String, String>{},
      };
}

AndroidPlaybackRequestSpec buildAndroidPlaybackRequestSpec(
  CatalogItem item, {
  required bool series,
  int? season,
  int? episode,
  int? recoveryAttempt,
  bool opaqueSession = true,
  Map<String, String> additionalQuery = const <String, String>{},
}) {
  final query = <String, String>{
    ...buildAndroidPlaybackIdentityEnvelope(
      item,
      series: series,
      season: season,
      episode: episode,
      recoveryAttempt: recoveryAttempt,
    ),
    ...additionalQuery,
  };
  return AndroidPlaybackRequestSpec(
    method: 'GET',
    path: opaqueSession
        ? '/mobile/playback/session'
        : (series ? '/resolve/tv' : '/resolve/movie'),
    query: Map<String, String>.unmodifiable(query),
    headers: androidPlaybackRequestHeaders,
  );
}
