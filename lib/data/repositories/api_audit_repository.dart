import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';

/// Real backend implementation — posts to `audit.log` (see `api_endpoints.json`).
class ApiAuditRepository implements AuditRepository {
  ApiAuditRepository(this._api);
  final ApiClient _api;

  @override
  Future<void> send(AuditEvent event) async {
    await _api.call('audit.log', body: event.toJson());
  }
}
