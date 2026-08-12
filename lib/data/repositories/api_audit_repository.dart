import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';

/// Real backend implementation — posts to `audit.log` (see `api_endpoints.json`)
/// on the shared platform app API, whose host differs per environment and from
/// the recovery API's own (`EnvironmentConfig.auditLogBaseUrl`):
///
/// * prod — `https://smartnetwork.azure-api.net/app/api/v1`
/// * dev  — `https://smartnetwork-dev.azure-api.net/app-staging/api/v1`
///
/// The body is [AuditEvent.toJson] verbatim — the entity mirrors the API's
/// request contract field-for-field.
class ApiAuditRepository implements AuditRepository {
  ApiAuditRepository(this._api, this._config);
  final ApiClient _api;
  final ConfigService _config;

  @override
  Future<void> send(AuditEvent event) async {
    final baseUrl = _config.env.auditLogBaseUrl;
    // No audit host configured for this environment — nothing to send to. Throw
    // rather than pretend it succeeded, so AuditLogService keeps the entry on
    // the offline queue instead of dropping it.
    if (baseUrl.isEmpty) {
      throw ApiException('No auditLogBaseUrl configured for '
          '${_config.env.environment}');
    }
    await _api.call('audit.log', body: event.toJson(), baseUrl: baseUrl);
  }
}
