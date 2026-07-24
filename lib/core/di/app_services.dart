import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/core/services/blob_upload_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/proof_service.dart';
import 'package:asset_recovery_app/core/services/route_tracking_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';

/// Presentation-facing **Facade** over the config + device services that
/// screens and controllers need (config, GPS, proof capture, the parsed wizard
/// flow, audit logging, offline sync, route tracking). Data access goes
/// through use cases, not this facade — so it holds no ticket repository.
/// Constructed by the DI container ([configureDependencies]).
class AppServices {
  AppServices({
    required this.config,
    required this.location,
    required this.proof,
    required this.blobUpload,
    required this.attemptFlow,
    required this.auditLog,
    required this.syncQueue,
    required this.routeTracking,
  });

  final ConfigService config;
  final LocationService location;
  final ProofService proof;
  final BlobUploadService blobUpload;
  final AttemptFlowConfig attemptFlow;
  final AuditLogService auditLog;
  final SyncQueueService syncQueue;
  final RouteTrackingService routeTracking;
}
