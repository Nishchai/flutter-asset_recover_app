import 'dart:async';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/core/services/connectivity_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/proof_service.dart';
import 'package:asset_recovery_app/core/services/route_tracking_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:asset_recovery_app/data/repositories/api_audit_repository.dart';
import 'package:asset_recovery_app/data/repositories/api_ticket_repository.dart';
import 'package:asset_recovery_app/data/repositories/mock_audit_repository.dart';
import 'package:asset_recovery_app/data/repositories/mock_ticket_repository.dart';
import 'package:asset_recovery_app/domain/entities/audit_event.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/repositories/audit_repository.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_assigned_tickets_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_road_distance_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_shift_stats_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/handover_otp_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/login_otp_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/submit_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/ticket_pickup_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/validate_battery_scan_usecase.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:get_it/get_it.dart';

/// Service-locator instance (composition root).
final GetIt sl = GetIt.instance;

/// Registers the full dependency graph: core services → data repository →
/// domain use cases → presentation state. Pass overrides in tests to inject a
/// deterministic mock backend. Selecting mock vs. real API is the ONLY
/// backend-wiring decision and it lives here.
Future<void> configureDependencies({
  ConfigService? config,
  TicketRepository? repository,
  LocationService? location,
  ProofService? proof,
}) async {
  final cfg = config ?? await ConfigService.load();

  // --- Core -----------------------------------------------------------------
  sl.registerSingleton<ConfigService>(cfg);
  sl.registerLazySingleton<LocationService>(
      () => location ?? StubLocationService(seed: cfg.env.deterministicSeed),);
  sl.registerLazySingleton<ProofService>(
      () => proof ?? CameraProofService(sl<LocationService>(), cfg),);
  sl.registerLazySingleton<AttemptFlowConfig>(
      () => AttemptFlowConfig.fromJson(cfg.attemptFlow),);

  // Connectivity + offline sync queue (CC-04). Platform channels aren't
  // available under flutter_test, so the deterministic test environment
  // gets an always-online stub instead of the real plugin.
  sl.registerLazySingleton<ConnectivityService>(
      () => cfg.env.environment == 'test' ? StubConnectivityService() : ConnectivityPlusService(),);
  sl.registerLazySingleton<SyncQueueService>(() => SyncQueueService(sl()));
  sl.registerLazySingleton<RouteTrackingService>(() => RouteTrackingService(
        sl(),
        sampleIntervalSeconds: cfg.intValue('business.routeTrackingIntervalSeconds', fallback: 30),
        minDistanceMeters: cfg.doubleValue('business.routeTrackingMinDistanceMeters', fallback: 50),
        maxPoints: cfg.intValue('business.routeTrackingMaxPoints', fallback: 500),
      ),);

  // --- Data (repository selection: mock vs real API) ------------------------
  // Single shared ApiClient so the auth token set on login (see
  // ApiTicketRepository.login) is visible to every other API-backed repo.
  sl.registerLazySingleton<ApiClient>(() => ApiClient(cfg));

  // Direct-to-Gupshup OTP client (login OTP send/verify). Credentials live in
  // the active environment file (cfg.env.gupshup).
  sl.registerLazySingleton<GupshupOtpDataSource>(() => GupshupOtpDataSource(cfg));

  sl.registerLazySingleton<TicketRepository>(
    () =>
        repository ??
        (cfg.env.useMockData
            ? MockTicketRepository(seed: cfg.env.deterministicSeed)
            : ApiTicketRepository(sl(), sl())),
  );

  sl.registerLazySingleton<AuditRepository>(
    () => cfg.env.useMockData ? MockAuditRepository() : ApiAuditRepository(sl()),
  );
  sl.registerLazySingleton<AuditLogService>(() => AuditLogService(sl(), sl(), sl()));

  sl.registerLazySingleton<AppServices>(() => AppServices(
        config: sl(),
        location: sl(),
        proof: sl(),
        attemptFlow: sl(),
        auditLog: sl(),
        syncQueue: sl(),
        routeTracking: sl(),
      ),);

  // --- Domain use cases -----------------------------------------------------
  sl.registerLazySingleton(() => RequestLoginOtpUseCase(sl()));
  sl.registerLazySingleton(() => VerifyLoginOtpUseCase(sl()));
  sl.registerLazySingleton(() => GetAssignedTicketsUseCase(sl()));
  sl.registerLazySingleton(() => GetShiftStatsUseCase(sl()));
  sl.registerLazySingleton(() => SubmitAttemptUseCase(sl()));
  sl.registerLazySingleton(() => ValidateBatteryScanUseCase(sl()));
  sl.registerLazySingleton(() => GetRoadDistanceUseCase(sl()));
  sl.registerLazySingleton(() => UpdateCustomerUseCase(sl()));
  sl.registerLazySingleton(() => RequestHandoverOtpUseCase(sl()));
  sl.registerLazySingleton(() => VerifyHandoverOtpUseCase(sl()));
  sl.registerLazySingleton(() => GetDraftUseCase(sl()));
  sl.registerLazySingleton(() => SaveDraftUseCase(sl()));
  sl.registerLazySingleton(() => GetLiveLocationUseCase(sl()));
  sl.registerLazySingleton(() => StartCallUseCase(sl()));
  sl.registerLazySingleton(() => GetCallRecordingsUseCase(sl()));
  sl.registerLazySingleton(() => GetNearbyUnassignedTicketsUseCase(sl()));
  sl.registerLazySingleton(() => PickupTicketUseCase(sl()));

  // --- Offline sync queue handlers (CC-04) -----------------------------------
  // 'submit_attempt' is registered by TicketProvider itself (asset_recovery_
  // app.dart) since replaying it needs to refresh that provider's ticket list.
  final syncQueue = sl<SyncQueueService>();
  syncQueue.registerHandler('audit_event', (payload) async {
    await sl<AuditRepository>().send(AuditEvent.fromJson(payload));
  });
  syncQueue.registerHandler('update_customer', (payload) async {
    final result = await sl<UpdateCustomerUseCase>()(UpdateCustomerParams(
      payload['bpId'] as String,
      Customer.fromJson(Map<String, dynamic>.from(payload['customer'] as Map)),
    ),);
    if (result.isErr) throw StateError(result.failureOrNull!.message);
  });
  unawaited(syncQueue.init());

  // --- Presentation state (fresh instance per provider scope) ---------------
  sl.registerFactory(() => AuthProvider(sl(), sl(), sl()));
  sl.registerFactory(() => TicketProvider(
        getAssigned: sl(),
        getStats: sl(),
        submitAttempt: sl(),
        roadDistance: sl(),
        config: sl(),
        location: sl(),
        syncQueue: sl(),
        getNearbyUnassigned: sl(),
        pickupTicket: sl(),
      ),);
  sl.registerFactory(() => ShiftProvider());
}

/// Clears all registrations (used between tests).
Future<void> resetDependencies() => sl.reset();
