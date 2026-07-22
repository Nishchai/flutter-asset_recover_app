import 'dart:async';
import 'dart:convert';

import 'package:asset_recovery_app/core/services/connectivity_service.dart';
import 'package:asset_recovery_app/domain/entities/sync_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Replays a queued [SyncAction]'s payload against the network. Throw to
/// leave the action queued for the next retry.
typedef SyncHandler = Future<void> Function(Map<String, dynamic> payload);

/// Offline action queue (CC-04): "uploads and ticket status updates and all
/// actions related to tickets should be synced" once connectivity returns.
///
/// Every write-side action that must survive going offline — attempt/outcome
/// submission, customer edits, audit events, route captures, emergency flags
/// — enqueues here instead of calling the API directly and losing the write
/// on failure. Persisted to disk so a killed app doesn't lose pending work;
/// drained automatically whenever [ConnectivityService] reports "online".
class SyncQueueService {
  SyncQueueService(this._connectivity);

  static const _prefsKey = 'sync_queue.pending';

  final ConnectivityService _connectivity;
  final _handlers = <String, SyncHandler>{};
  final _pendingCountController = StreamController<int>.broadcast();
  List<SyncAction> _pending = [];
  bool _draining = false;
  StreamSubscription<bool>? _connectivitySub;

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

  void dispose() => _connectivitySub?.cancel();

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
  Future<void> drain() async {
    if (_draining || _pending.isEmpty) return;
    _draining = true;
    try {
      final stillPending = <SyncAction>[];
      for (final action in List.of(_pending)) {
        final handler = _handlers[action.type];
        if (handler == null) {
          // No handler registered (shouldn't happen) — don't lose the data,
          // just leave it queued rather than silently dropping it.
          stillPending.add(action);
          continue;
        }
        try {
          await handler(action.payload);
        } catch (_) {
          action.attempts += 1;
          stillPending.add(action);
        }
      }
      _pending = stillPending;
      await _save();
    } finally {
      _draining = false;
    }
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
