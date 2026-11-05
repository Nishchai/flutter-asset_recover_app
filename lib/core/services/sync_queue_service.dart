import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/services/connectivity_service.dart';
import 'package:asset_recovery_app/domain/entities/sync_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replays a queued [SyncAction]'s payload against the network. Throw to
/// leave the action queued for the next retry.
typedef SyncHandler = Future<void> Function(Map<String, dynamic> payload);

/// Thrown by a [SyncHandler] when retrying can never succeed (the server
/// rejected the payload itself, e.g. a 4xx validation error). The queue drops
/// the action instead of retrying it forever.
class SyncDropException implements Exception {
  SyncDropException(this.reason);
  final String reason;

  @override
  String toString() => 'SyncDropException($reason)';
}

/// Offline action queue (CC-04): "uploads and ticket status updates and all
/// actions related to tickets should be synced" once connectivity returns.
///
/// Every write-side action that must survive going offline — attempt/outcome
/// submission, customer edits, audit events, route captures, emergency flags
/// — enqueues here instead of calling the API directly and losing the write
/// on failure. Persisted to disk so a killed app doesn't lose pending work;
/// drained automatically whenever [ConnectivityService] reports "online", and
/// retried on a backoff while anything is still pending — the connectivity
/// event can arrive before the network is actually usable, so relying on it
/// alone left actions stuck until the next connectivity change.
class SyncQueueService {
  SyncQueueService(
    this._connectivity, {
    this.retryInitialDelay = const Duration(seconds: 15),
    this.retryMaxDelay = const Duration(minutes: 5),
  });

  static const _prefsKey = 'sync_queue.pending';

  final ConnectivityService _connectivity;

  /// First retry delay after a drain that left actions pending; doubles per
  /// consecutive failed drain up to [retryMaxDelay].
  final Duration retryInitialDelay;
  final Duration retryMaxDelay;

  final _handlers = <String, SyncHandler>{};
  final _pendingCountController = StreamController<int>.broadcast();
  List<SyncAction> _pending = [];
  Future<void>? _inFlight;
  StreamSubscription<bool>? _connectivitySub;
  Timer? _retryTimer;
  Duration _retryDelay = Duration.zero;
  bool _disposed = false;

  /// Current queue depth, for a "N pending sync" indicator in the UI.
  int get pendingCount => _pending.length;
  Stream<int> get pendingCountStream => _pendingCountController.stream;

  /// Registers how to replay actions of [type]. Call once per action kind
  /// during app startup (see injector.dart) before [init].
  void registerHandler(String type, SyncHandler handler) => _handlers[type] = handler;

  Future<void> init() async {
    await _load();
    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      if (online) unawaited(drain());
    });
    if (await _connectivity.isOnline()) unawaited(drain());
  }

  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    _pending.add(SyncAction(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_pending.length}',
      type: type,
      payload: payload,
      createdAt: DateTime.now(),
    ),);
    await _save();
    if (await _connectivity.isOnline()) unawaited(drain());
  }

  /// Attempts to replay every queued action; actions that still fail (still
  /// offline, or a real server error) stay queued for the next trigger.
  ///
  /// Concurrent callers share the drain already in flight rather than
  /// returning early, so a screen that awaits this (e.g. ticket detail, before
  /// it reads the attempt history) really does wait for the flush to finish.
  Future<void> drain() {
    if (_pending.isEmpty) return Future.value();
    return _inFlight ??= _drain().whenComplete(() => _inFlight = null);
  }

  Future<void> _drain() async {
    final snapshot = List.of(_pending);
    final stillPending = <SyncAction>[];
    for (final action in snapshot) {
      final handler = _handlers[action.type];
      if (handler == null) {
        // No handler registered (shouldn't happen) — don't lose the data,
        // just leave it queued rather than silently dropping it.
        stillPending.add(action);
        continue;
      }
      try {
        await handler(action.payload);
      } on SyncDropException catch (e) {
        // The server will never accept this payload — retrying is pointless.
        developer.log('Dropped queued ${action.type}: ${e.reason}',
            name: 'SyncQueue',);
      } catch (e) {
        developer.log('Queued ${action.type} not sent yet: $e',
            name: 'SyncQueue',);
        action.attempts += 1;
        stillPending.add(action);
      }
    }
    // Actions enqueued while this drain was running were not in the snapshot;
    // keep them (replacing the list with only `stillPending` would lose them).
    final snapshotIds = {for (final a in snapshot) a.id};
    _pending = [
      ...stillPending,
      ..._pending.where((a) => !snapshotIds.contains(a.id)),
    ];
    await _save();
    _scheduleRetry();
  }

  /// Arms a backoff retry while anything is left pending, and resets the
  /// backoff once the queue is empty.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed) return;
    if (_pending.isEmpty) {
      _retryDelay = Duration.zero;
      return;
    }
    _retryDelay = _retryDelay == Duration.zero
        ? retryInitialDelay
        : Duration(
            milliseconds: (_retryDelay.inMilliseconds * 2)
                .clamp(0, retryMaxDelay.inMilliseconds),
          );
    _retryTimer = Timer(_retryDelay, () async {
      if (_disposed) return;
      if (await _connectivity.isOnline()) {
        await drain();
      } else {
        // Offline: nothing to try. The connectivity listener drains on
        // reconnect; keep the timer chain alive in case that event is missed.
        _scheduleRetry();
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List;
    _pending = list
        .map((e) => SyncAction.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _pendingCountController.add(_pending.length);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_pending.map((a) => a.toJson()).toList()));
    _pendingCountController.add(_pending.length);
  }
}
