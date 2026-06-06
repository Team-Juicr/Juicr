import 'app_state.dart';
import 'stream_api.dart';

class AccountLibrarySyncService {
  AccountLibrarySyncService._();

  static final StreamApi _api = StreamApi();

  static void install() {
    AppState.configureAccountLibrarySync(
      fetch: _api.fetchAccountLibrarySnapshot,
      push: (token, snapshot, baseRevision) => _api
          .pushAccountLibrarySnapshot(
            token: token,
            snapshot: snapshot,
            baseRevision: baseRevision,
          ),
    );
  }
}
