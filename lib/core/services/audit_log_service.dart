import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';

/// Audit event emission (item 15 groundwork). Every state-changing mobile
/// action calls [log] so the coordinator Web App's audit-log dashboard
/// (PRD §12.1) can be populated. [log] itself never blocks or fails a
/// user-facing action — but a failed send (e.g. offline, per CC-04) is
/// queued for retry via [SyncQueueService] rather than silently dropped, so
/// the audit trail doesn't have gaps just because the agent was offline.
class AuditLogService {
  AuditLogService(this._repo, this._config, this._syncQueue);

  final AuditRepository _repo;
  final ConfigService _config;
  final SyncQueueService _syncQueue;

  Future<void> log({
    required String agentId,
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (!_config.flag('features.auditLogging', fallback: true)) return;
    final event = AuditEvent(
      agentId: agentId,
      action: action,
      timestamp: DateTime.now(),
      entityType: entityType,
      entityId: entityId,
      metadata: metadata,
    );
    try {
      await _repo.send(event);
    } catch (_) {
      await _syncQueue.enqueue('audit_event', event.toJson());
    }
  }
}
