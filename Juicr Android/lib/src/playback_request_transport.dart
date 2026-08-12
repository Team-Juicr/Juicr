import 'dart:async';

import 'package:http/http.dart' as http;

typedef PlaybackHttpClientFactory = http.Client Function();

class PlaybackRequestCancelledException implements Exception {
  const PlaybackRequestCancelledException();
}

class PlaybackRequestCancellation {
  final Set<void Function()> _listeners = <void Function()>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }
}

Future<T> runCancelablePlaybackAttempt<T>({
  required Duration timeout,
  required Future<T> Function(PlaybackRequestCancellation cancellation)
      operation,
  PlaybackRequestCancellation? parentCancellation,
}) async {
  if (parentCancellation?.isCancelled == true) {
    throw const PlaybackRequestCancelledException();
  }
  final cancellation = PlaybackRequestCancellation();
  void cancelFromParent() => cancellation.cancel();
  parentCancellation?.addListener(cancelFromParent);
  final operationFuture = operation(cancellation);
  try {
    return await operationFuture.timeout(
      timeout,
      onTimeout: () async {
        cancellation.cancel();
        try {
          await operationFuture.timeout(const Duration(milliseconds: 250));
        } catch (_) {
          // Cancellation settlement errors are expected and remain private.
        }
        throw TimeoutException('Playback attempt timed out.', timeout);
      },
    );
  } finally {
    cancellation.cancel();
    parentCancellation?.removeListener(cancelFromParent);
  }
}

class PlaybackRequestTransport {
  PlaybackRequestTransport(this._clientFactory);

  final PlaybackHttpClientFactory _clientFactory;
  final Set<Future<void> Function()> _activeCancellations =
      <Future<void> Function()>{};
  bool _closed = false;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final active = List<Future<void> Function()>.of(_activeCancellations);
    _activeCancellations.clear();
    await Future.wait(active.map((cancel) => cancel()));
  }

  Future<http.Response> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    PlaybackRequestCancellation? cancellation,
  }) async {
    if (_closed) throw const PlaybackRequestCancelledException();
    if (cancellation?.isCancelled == true) {
      throw const PlaybackRequestCancelledException();
    }
    final client = _clientFactory();
    final result = Completer<http.Response>();
    Timer? timer;
    var clientClosed = false;
    var aborting = false;
    late final Future<http.Response> requestFuture;

    void closeClient() {
      if (clientClosed) return;
      clientClosed = true;
      client.close();
    }

    void completeError(Object error, StackTrace stackTrace) {
      if (result.isCompleted) return;
      closeClient();
      result.completeError(error, stackTrace);
    }

    Future<void> abort(Object error, StackTrace stackTrace) async {
      if (result.isCompleted || aborting) return;
      aborting = true;
      closeClient();
      try {
        await requestFuture.timeout(const Duration(milliseconds: 250));
      } catch (_) {
        // Closing the owned client is the abort; settlement errors are expected.
      }
      if (!result.isCompleted) result.completeError(error, stackTrace);
    }

    Future<void> cancel() => abort(
          const PlaybackRequestCancelledException(),
          StackTrace.current,
        );

    requestFuture = client.get(uri, headers: headers);
    _activeCancellations.add(cancel);
    cancellation?.addListener(cancel);
    timer = Timer(
      timeout,
      () => unawaited(
        abort(
          TimeoutException('Playback request timed out.', timeout),
          StackTrace.current,
        ),
      ),
    );
    requestFuture.then((response) {
      if (!result.isCompleted && !aborting) result.complete(response);
    }, onError: (Object error, StackTrace stackTrace) {
      if (!aborting) completeError(error, stackTrace);
    });
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _activeCancellations.remove(cancel);
      cancellation?.removeListener(cancel);
      closeClient();
    }
  }
}
