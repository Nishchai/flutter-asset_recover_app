import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/session_store.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/core/utils/ist_time.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';

/// Audit event emission (item 15 groundwork). Every state-changing mobile
/// action calls [log] so the coordinator Web App's audit-log dashboard
/// (PRD §12.1) can be populated. [log] itself never blocks or fails a
/// user-facing action — but a failed send (e.g. offline, per CC-04) is
/// queued for retry via [SyncQueueService] rather than silently dropped, so
/// the audit trail doesn't have gaps just because the agent was offline.
///
/// Call sites only describe WHAT happened (the activity, the entity it acted
/// on and any extras). The identity and app columns the platform Audit Log
/// contract wants around that — `userName`, `appName`, `appVersion` — are
/// filled in here from the signed-in session and the active config, so no
/// caller has to thread them through.
class AuditLogService {
  AuditLogService(this._repo, this._config, this._syncQueue, this._session);

  final AuditRepository _repo;
  final ConfigService _config;
  final SyncQueueService _syncQueue;
  final SessionStore _session;

  /// Records one activity.
  ///
  /// [agentId] is the signed-in agent's `userId` and [action] the activity name
  /// (`login_success`, `outcome_submitted`, …) — they become `userId` /
  /// `userActivity`
  /// on the wire. [entityType]/[entityId]/[metadata] become the entry's
  /// `activityContext`.
  ///
  /// [startedAt] marks the beginning of a longer activity; for the
  /// instantaneous actions the app logs, leaving it null timestamps both ends
  /// at "now". [transactionId] correlates several entries belonging to one
  /// operation — omitted, this defaults to the signed-in session's own id
  /// (`PersistedSession.transactionId`, minted once at login and carried
  /// through to logout) so every entry in a session shares one id; with
  /// nobody signed in, each entry gets its own.
  Future<void> log({
    required String agentId,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic> metadata = const {},
    String? userName,
    String status = AuditEvent.statusSuccess,
    String? transactionId,
    DateTime? startedAt,
    DateTime? endedAt,
  }) async {
    if (!_config.flag('features.auditLogging', fallback: true)) return;
    final now = nowIst();
    final context = ActivityContext(
      entityType: entityType,
      entityId: entityId,
      details: metadata,
    );
    final event = AuditEvent(
      transactionId: transactionId ??
          _session.current?.transactionId ??
          AuditEvent.newTransactionId(),
      userId: agentId,
      userName: userName ?? _signedInUserName,
      activityStartDate: startedAt ?? now,
      activityEndDate: endedAt ?? now,
      userActivity: action,
      appName: _config.appName,
      appVersion: _config.appVersion,
      status: status,
      activityContext: context.isEmpty ? null : context,
    );
    try {
      await _repo.send(event);
    } catch (_) {
      await _syncQueue.enqueue('audit_event', event.toJson());
    }
  }

  /// The signed-in agent's display name: the `commonLogin` record's `userName`
  /// where there is one, else the projected agent's name. Null when nobody is
  /// signed in (the field is optional on the contract).
  String? get _signedInUserName {
    final session = _session.current;
    if (session == null) return null;
    final fromProfile = session.profile?.userName ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    final fromAgent = session.agent.name;
    return fromAgent.isEmpty ? null : fromAgent;
  }
}
