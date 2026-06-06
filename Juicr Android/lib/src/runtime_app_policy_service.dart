import 'app_state.dart';
import 'diagnostic_log.dart';
import 'stream_api.dart';

class RuntimeAppPolicyService {
  RuntimeAppPolicyService._();

  static final StreamApi _api = StreamApi();

  static Future<void> refresh() async {
    try {
      final policy = await _api.runtimeAppPolicy();
      AppState.applyRuntimeAppPolicy(policy);
    } catch (_) {
      AppState.applyRuntimeAppPolicy(null);
      DiagnosticLog.add('runtime app policy refresh failed');
    }
  }
}
