import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline detection driving the offline sync queue (CC-04). The app
/// doesn't need to distinguish wifi/cellular — only "can I reach the API".
abstract class ConnectivityService {
  Future<bool> isOnline();

  /// Emits `true`/`false` whenever connectivity changes.
  Stream<bool> get onStatusChange;
}

class ConnectivityPlusService extends ConnectivityService {
  final _connectivity = Connectivity();

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async => _isOnline(await _connectivity.checkConnectivity());

  @override
  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged.map(_isOnline);
}

/// Test/offline-dev double — always reports online unless overridden.
class StubConnectivityService extends ConnectivityService {
  bool online = true;

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onStatusChange => const Stream.empty();
}
