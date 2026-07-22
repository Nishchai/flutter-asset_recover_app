import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';

/// In-memory audit sink. Keeps every event so tests/demos can assert on
/// what was logged, without needing a backend.
class MockAuditRepository implements AuditRepository {
  final List<AuditEvent> events = [];

  @override
  Future<void> send(AuditEvent event) async {
    events.add(event);
  }
}
