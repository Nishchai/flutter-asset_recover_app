import 'package:asset_recovery_app/domain/entities/audit_event.dart';

/// Backend-agnostic contract for shipping audit events to the platform so the
/// coordinator Web App's audit-log dashboard (PRD §12.1) can be populated.
abstract class AuditRepository {
  Future<void> send(AuditEvent event);
}
