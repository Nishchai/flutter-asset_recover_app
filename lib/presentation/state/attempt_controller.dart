import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/core/services/blob_upload_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/proof_service.dart';
import 'package:asset_recovery_app/core/services/sim_call_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/attempt_submission.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/proof.dart';
import 'package:asset_recovery_app/domain/usecases/call_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/draft_attempt_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/get_live_location_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/submit_attempt_record_usecase.dart';
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/foundation.dart';

/// Translator signature so the controller can produce localized errors without
/// depending on BuildContext.
typedef Translate = String Function(String key, [Map<String, Object?> params]);

/// How much of a section's required fields have been filled — drives the
/// status chip on each Ticket Actions hub card.
enum SectionStatus { empty, partial, done }

/// How one visit section maps onto an [AttemptSubmission]: which of its fields
/// supplies the `outcome` and the `notes`, and what `attemptType` it reports.
/// See `AttemptController._sectionAttempts`.
class _SectionAttemptSpec {
  const _SectionAttemptSpec({
    required this.attemptType,
    required this.outcomeField,
    required this.notesField,
  });

  final String attemptType;

  /// `_values` key of the dropdown sent as `outcome`.
  final String outcomeField;

  /// `_values` key of the remarks field sent as `notes`.
  final String notesField;
}

/// Drives the free-choice recovery actions (PRD-derived, item 4): Call
/// Customer / Visit BP Location / Visit Customer Address / Update Status are
/// independent actions the Field Agent can complete in any order, any number
/// of times. Progress is persisted as a [DraftAttempt] (item 13) so it
/// survives navigating away or closing the app, until the Outcome action is
/// submitted, at which point it becomes a real [Attempt] and the draft clears.
///
/// No business rule is hard-coded here — visibility/requirement rules still
/// come entirely from `attempt_flow.json`, same as before.
class AttemptController extends ChangeNotifier {
  AttemptController({
    required this.flow,
    required this.ticketId,
    required this.battery,
    required this.agentId,
    required ConfigService config,
    required LocationService location,
    required ProofService proof,
    BlobUploadService? blobUpload,
    required GetDraftUseCase getDraft,
    required SaveDraftUseCase saveDraft,
    required UpdateCustomerUseCase updateCustomer,
    required AuditLogService auditLog,
    required GetLiveLocationUseCase getLiveLocation,
    required StartCallUseCase startCallUseCase,
    required GetCallRecordingsUseCase getCallRecordings,
    required SyncQueueService syncQueue,
    this.agentName = '',
    this.batteryDetail,
    SubmitAttemptRecordUseCase? submitAttemptRecord,
    SimCallService? simCall,
  })  : _simCall = simCall ?? const NoopSimCallService(),
        _submitAttemptRecord = submitAttemptRecord,
        _config = config,
        _location = location,
        _proof = proof,
        _blobUpload = blobUpload ?? const NoopBlobUploadService(),
        _getDraft = getDraft,
        _saveDraft = saveDraft,
        _updateCustomer = updateCustomer,
        _auditLog = auditLog,
        _getLiveLocation = getLiveLocation,
        _startCallUseCase = startCallUseCase,
        _getCallRecordings = getCallRecordings,
        _syncQueue = syncQueue;

  final AttemptFlowConfig flow;
  final String ticketId;
  final Battery battery;
  final String agentId;

  /// Display name of the recovering agent (from the ticket detail screen's
  /// "Assigned To"). Sent as `agentName` on the attempt submission.
  final String agentName;

  /// Live battery telemetry from `battery.getBatteryDetails`, fetched once on
  /// the BP detail screen and handed down through [TicketActionsHub]. Null
  /// until/unless that call returns a telemetry row. Supplies the Visit BP
  /// Location section's "Last Known Location" and "Last TIU" readouts and the
  /// coordinates its "View on Map" button navigates to — see
  /// [navigationTarget] and [lastTiuDisplay].
  final BatteryDetail? batteryDetail;
  final SubmitAttemptRecordUseCase? _submitAttemptRecord;
  final ConfigService _config;
  final LocationService _location;
  final ProofService _proof;
  final BlobUploadService _blobUpload;
  final GetDraftUseCase _getDraft;
  final SaveDraftUseCase _saveDraft;
  final UpdateCustomerUseCase _updateCustomer;
  final AuditLogService _auditLog;
  final GetLiveLocationUseCase _getLiveLocation;
  final StartCallUseCase _startCallUseCase;
  final GetCallRecordingsUseCase _getCallRecordings;
  final SyncQueueService _syncQueue;
  final SimCallService _simCall;

  final Map<String, dynamic> _values = {};
  final Map<String, Proof> _proofs = {};
  bool _submitting = false;
  bool _loading = true;

  /// When the agent opened the Update Status screen — captured on first entry
  /// and sent as `attemptedAt` on the submission.
  DateTime? _updateStatusOpenedAt;

  /// When the agent opened each visit section's screen, keyed by section id —
  /// captured on first entry and sent as `attemptedAt` on that section's
  /// attempt submission (`completedAt` is stamped when they tap Save). Keyed
  /// per section so Visit BP Location and Visit Customer Address time
  /// themselves independently of each other and of [_updateStatusOpenedAt].
  final Map<String, DateTime> _sectionOpenedAt = {};

  /// In-flight blob uploads, keyed by the field id that captured the proof.
  /// [_proofUrlsForSection] awaits the relevant ones so a Save that lands
  /// seconds after a photo capture still carries its `proofUrls`.
  final Map<String, Future<void>> _uploadTasks = {};
  GeoPoint? _arrivalGps;
  GeoPoint? _liveLocation;
  bool _fetchingLiveLocation = false;
  bool _callInProgress = false;
  List<CallRecording> _recordings = const [];

  /// --- In-app SIM call (Android) ---
  /// Live state of the call placed by [startSimCall], null when none is up.
  SimCallState? _simCallState;
  StreamSubscription<SimCallEvent>? _simCallSub;

  /// When the current SIM call was placed — drives the on-screen elapsed timer.
  DateTime? _simCallPlacedAt;

  /// True when the platform is reporting this call's state, so its duration is
  /// recorded automatically. False when READ_PHONE_STATE was refused and the
  /// UI has to fall back to its own stopwatch.
  bool _simCallTracked = false;

  /// `callId` of the last SIM call already written to [_recordings], so an
  /// `ended` event and a [reconcileSimCall] catch-up can't log it twice.
  String? _recordedCallId;

  /// Id of the call in flight, kept so [reconcileSimCall] knows which
  /// `lastCallResult` belongs to it.
  String? _activeCallId;

  bool get loading => _loading;
  bool get submitting => _submitting;
  GeoPoint? get liveLocation => _liveLocation;
  bool get fetchingLiveLocation => _fetchingLiveLocation;
  bool get callInProgress => _callInProgress;
  List<CallRecording> get recordings => _recordings;
  SimCallState? get simCallState => _simCallState;
  DateTime? get simCallPlacedAt => _simCallPlacedAt;
  bool get simCallTracked => _simCallTracked;

  StepConfig get outcomeSection =>
      flow.steps.firstWhere((s) => s.id == 'outcome');
  List<StepConfig> get actionSections =>
      flow.steps.where((s) => s.id != 'outcome').toList();

  dynamic value(String id) => _values[id];
  Proof? proofFor(String id) => _proofs[id];

  void setValue(String id, dynamic value) {
    _values[id] = value;
    notifyListeners();
  }

  /// Capture arrival GPS + load any saved draft. Call once after construction.
  Future<void> init() async {
    _arrivalGps = await _location.currentLocation();
    final result = await _getDraft(battery.bpId);
    final draft = result.valueOrNull;
    if (draft != null) {
      _values.addAll(draft.values);
      _proofs.addAll(draft.proofs);
    }
    _loading = false;
    notifyListeners();
  }

  // --- Visibility & requirement rules ----------------------------------------

  bool fieldExists(FormFieldConfig f) {
    if (f.featureFlag != null && !_config.flag(f.featureFlag!, fallback: true)) {
      return false;
    }
    return true;
  }

  bool isVisible(FormFieldConfig f) {
    if (!fieldExists(f)) return false;
    final rule = f.visibleWhen;
    if (rule == null) return true;
    final dependent = _values[rule['field'] as String?];
    if (rule.containsKey('equals')) return dependent == rule['equals'];
    if (rule.containsKey('in')) {
      final allowed = (rule['in'] as List).map((e) => e.toString()).toSet();
      return dependent != null && allowed.contains(dependent.toString());
    }
    return true;
  }

  bool isRequired(FormFieldConfig f) {
    if (f.required) return true;
    if (f.requiredFlag != null) return _config.flag(f.requiredFlag!);
    return false;
  }

  List<FormFieldConfig> visibleFields(StepConfig section) =>
      section.fields.where(isVisible).toList();

  /// Derived display text for readonly fields.
  String readonlyValue(FormFieldConfig f) {
    switch (f.sourceField) {
      case 'lastKnownLatLong':
        return navigationTarget.display;
      case 'customerSummary':
        final c = battery.customer;
        return '${c.name} · ${c.mobile}\n${c.address}';
      default:
        return '';
    }
  }

  /// Status chip shown on the hub card for [section].
  SectionStatus sectionStatus(StepConfig section) {
    final required =
        visibleFields(section).where(isRequired).map((f) => f.id).toList();
    if (required.isEmpty) {
      final anyFilled = visibleFields(section)
          .any((f) => Validators.isNotEmpty(_values[f.id]) || _proofs[f.id] != null);
      return anyFilled ? SectionStatus.done : SectionStatus.empty;
    }
    final filledCount = required
        .where((id) => Validators.isNotEmpty(_values[id]) || _proofs[id] != null)
        .length;
    if (filledCount == 0) return SectionStatus.empty;
    if (filledCount == required.length) return SectionStatus.done;
    return SectionStatus.partial;
  }

  // --- Proof capture (geo-tagged, geo-fence validated) -----------------------

  Future<Proof> captureProof(FormFieldConfig f) async {
    final kind = proofKindFromString(f.proofKind);
    final captured = await _proof.capture(kind);
    _proofs[f.id] = captured;
    notifyListeners();
    // Push the image to blob storage in the background so the capture UX is
    // never blocked on the network. The resulting URL is logged (and recorded
    // on the Proof) when the upload lands; failures are logged and the local
    // proof is kept. Drives the FIR-document upload (Outcome = FIR) today and
    // works the same for every other proof kind.
    // The future is retained (not just unawaited) so a Save that happens while
    // the upload is still in flight can await it — see [_proofUrlsForSection].
    _uploadTasks[f.id] = _uploadProof(f.id, captured);
    return captured;
  }

  /// Uploads [proof]'s image to blob storage and, on success, records the
  /// returned URL on the stored [Proof]. Skips when storage isn't configured or
  /// the proof has no real local file (e.g. the stub proof service). For now the
  /// URL is only logged; once the submit payload carries it, `remoteUrl` is
  /// already populated here.
  Future<void> _uploadProof(String fieldId, Proof proof) async {
    if (!_blobUpload.isConfigured) return;
    final local = proof.localPath;
    if (local.isEmpty || local.startsWith('mock://')) return;
    try {
      final url = await _blobUpload.upload(File(local), blobName: _blobName(proof));
      developer.log('Proof uploaded [$fieldId]: $url', name: 'BlobUpload');
      // A re-capture may have replaced this proof while the upload was in
      // flight — only annotate if it's still the same one.
      if (identical(_proofs[fieldId], proof)) {
        _proofs[fieldId] = proof.copyWith(remoteUrl: url, uploaded: true);
        notifyListeners();
      }
    } catch (e, st) {
      developer.log('Proof upload failed [$fieldId]',
          name: 'BlobUpload', error: e, stackTrace: st,);
    }
  }

  /// Deterministic blob path for a captured proof:
  /// `proofs/<ticket>/<bp>/<kind>_<timestamp>.<ext>`.
  String _blobName(Proof proof) {
    final ts = proof.capturedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final ext = proof.localPath.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    return 'proofs/$ticketId/${battery.bpId}/${proof.kind.name}_$ts.$ext';
  }

  /// Geo-fence check for recovery proof (PRD §4.3). Returns true if compliant
  /// or enforcement disabled.
  bool isProofWithinGeofence(Proof proof) {
    if (!_config.enforceGeofence) return true;
    return _location.isWithinGeofence(
      proof.location,
      battery.lastKnownLocation,
      _config.geofenceRadiusMeters,
    );
  }

  // --- BP live location (Rule 8b) ---------------------------------------------

  /// Refreshes [liveLocation] from the BP Live API — may differ from the
  /// cached [Battery.lastKnownLocation] shown until this is called.
  Future<void> fetchLiveLocation() async {
    _fetchingLiveLocation = true;
    notifyListeners();
    final result = await _getLiveLocation(battery.bpId);
    _liveLocation = result.valueOrNull ?? _liveLocation;
    _fetchingLiveLocation = false;
    notifyListeners();
  }

  /// The point to navigate to / display — Battery Master telemetry's last
  /// lat/long wins (same precedence the BP detail screen's "Last Seen" uses),
  /// then a freshly-fetched live location, then the cached last known one.
  /// Feeds the "Last Known Location" readonly field and the coordinates handed
  /// to [MapScreen] by "View on Map".
  GeoPoint get navigationTarget =>
      batteryDetail?.location ?? _liveLocation ?? battery.lastKnownLocation;

  /// "Last TIU" for the Visit BP Location section — the telemetry timestamp
  /// from `battery.getBatteryDetails`, falling back to the base battery's
  /// pre-formatted string.
  String get lastTiuDisplay {
    final tiu = batteryDetail?.lastTiuTimestamp;
    if (tiu != null) return Formatters.dateTime(tiu);
    return battery.lastTiuTime.isEmpty ? '—' : battery.lastTiuTime;
  }

  // --- In-app calling (Ozonetel — Rule 8a) ------------------------------------

  Future<void> loadCallRecordings() async {
    final result = await _getCallRecordings(battery.bpId);
    _recordings = result.valueOrNull ?? const [];
    notifyListeners();
  }

  /// Places an in-app call via the configured provider (Ozonetel) and waits
  /// for the resulting recording. The real integration proxies + records the
  /// call server-side; this stub simulates that round trip.
  Future<void> startCall() async {
    _callInProgress = true;
    notifyListeners();
    try {
      final result = await _startCallUseCase(
        StartCallParams(battery.bpId, battery.customer.mobile),
      );
      final recording = result.valueOrNull;
      if (recording != null) {
        _recordings = [recording, ..._recordings];
        unawaited(_auditLog.log(
          agentId: agentId,
          action: 'call_recorded',
          entityType: 'battery',
          entityId: battery.bpId,
          metadata: {'durationSeconds': recording.durationSeconds},
        ),);
      }
    } finally {
      _callInProgress = false;
      notifyListeners();
    }
  }

  // --- In-app SIM call (Rule 8a, Android) -------------------------------------

  /// TEMPORARY: every in-app SIM call is placed to this test line instead of
  /// the customer's own number, so the flow can be exercised against a phone
  /// the team controls. Clear it to `''` to dial `battery.customer.mobile` —
  /// the only change needed to go live.
  static const String simCallOverrideNumber = '+917349577447';

  /// The number [startSimCall] will actually dial. Displayed on the Start Call
  /// button too, so the screen never claims to be calling a number it isn't.
  String get simCallTargetNumber => simCallOverrideNumber.isEmpty
      ? battery.customer.mobile
      : simCallOverrideNumber;

  /// True when this device can place the call on its own SIM from inside the
  /// app. Resolved by [loadSimCallSupport] when the Call Customer screen opens;
  /// false on iOS/desktop/emulators, where the UI times the call itself.
  bool get simCallSupported => _simCallSupported;
  bool _simCallSupported = false;

  Future<void> loadSimCallSupport() async {
    final supported = await _simCall.isSupported();
    if (supported == _simCallSupported) return;
    _simCallSupported = supported;
    notifyListeners();
  }

  /// Dials the customer on the device SIM without leaving the app.
  ///
  /// Returns null on success, or a localization key describing why it could
  /// not dial. On success the platform is watched for the call's real duration,
  /// which is logged as a [CallRecording] the moment the agent hangs up — no
  /// in-app stopwatch involved. When READ_PHONE_STATE is refused the call is
  /// still placed but [simCallTracked] comes back false, and the caller is
  /// expected to time the call itself and hand the seconds to
  /// [saveCallRecording].
  Future<String?> startSimCall() async {
    final number = SimCallService.sanitize(simCallTargetNumber);
    if (number.isEmpty) return 'call.noNumber';
    if (_callInProgress) return null;

    var perms = await _simCall.permissions();
    if (!perms.canCall || !perms.canReadState) {
      perms = await _simCall.requestPermissions();
    }
    // CALL_PHONE is the hard requirement; READ_PHONE_STATE only buys automatic
    // duration capture, so a refusal there still lets the call go through.
    if (!perms.canCall) return 'call.permissionDenied';

    final SimCallStart start;
    try {
      start = await _simCall.placeCall(number);
    } on SimCallException catch (e) {
      return e.messageKey;
    }

    _activeCallId = start.callId;
    _simCallTracked = start.stateTracked;
    _simCallState = SimCallState.dialing;
    _simCallPlacedAt = DateTime.now();
    _callInProgress = true;
    unawaited(_auditLog.log(
      agentId: agentId,
      action: 'call_started',
      entityType: 'battery',
      entityId: battery.bpId,
      metadata: {'ticketId': ticketId, 'stateTracked': start.stateTracked},
    ),);
    if (start.stateTracked) _listenToSimCall();
    notifyListeners();
    return null;
  }

  void _listenToSimCall() {
    _simCallSub?.cancel();
    _simCallSub = _simCall.events.listen((event) {
      // Events for a call we are no longer showing (a stale `ended` from a
      // previous attempt) must not reopen the in-progress state.
      if (_activeCallId != null &&
          event.callId.isNotEmpty &&
          event.callId != _activeCallId) {
        return;
      }
      switch (event.state) {
        case SimCallState.dialing:
        case SimCallState.active:
          _simCallState = event.state;
          _callInProgress = true;
          notifyListeners();
        case SimCallState.ended:
          _finishSimCall(event);
      }
    });
  }

  /// Closes out the tracked call: logs it as a recording (when it actually
  /// connected) and clears the in-progress state.
  void _finishSimCall(SimCallEvent event) {
    _simCallSub?.cancel();
    _simCallSub = null;
    _simCallState = SimCallState.ended;
    _callInProgress = false;
    _simCallPlacedAt = null;
    _activeCallId = null;
    if (event.callId.isNotEmpty && event.callId == _recordedCallId) {
      notifyListeners();
      return;
    }
    _recordedCallId = event.callId;
    if (event.durationSeconds > 0) {
      // Logs the recording and notifies for us.
      unawaited(saveCallRecording(event.durationSeconds));
    } else {
      // Dialed but never connected — nothing worth logging as a call record.
      notifyListeners();
    }
  }

  /// Picks up an `ended` event the app may have missed while backgrounded
  /// behind the OS in-call screen. Called when the Call Customer screen
  /// resumes; a no-op when there is nothing outstanding.
  Future<void> reconcileSimCall() async {
    if (!_callInProgress || !_simCallTracked) return;
    final last = await _simCall.lastCallResult();
    if (last == null) return;
    if (last.callId.isNotEmpty && last.callId != _activeCallId) return;
    _finishSimCall(last);
  }

  /// Abandons platform tracking of the call in flight — used when the UI timed
  /// the call itself (untracked calls) or the agent dismissed the in-progress
  /// banner.
  Future<void> endSimCall() async {
    await _simCallSub?.cancel();
    _simCallSub = null;
    _callInProgress = false;
    _simCallState = null;
    _simCallPlacedAt = null;
    _activeCallId = null;
    notifyListeners();
    await _simCall.stopTracking();
  }

  /// Records a completed in-app call using the duration measured by the
  /// on-going-call dialog's timer, prepending it to the recordings list so
  /// the field agent immediately sees the call they just made.
  Future<void> saveCallRecording(int durationSeconds) async {
    final now = DateTime.now();
    final recording = CallRecording(
      id: 'call-${now.millisecondsSinceEpoch}',
      bpId: battery.bpId,
      startedAt: now.subtract(Duration(seconds: durationSeconds)),
      durationSeconds: durationSeconds,
    );
    _recordings = [recording, ..._recordings];
    unawaited(_auditLog.log(
      agentId: agentId,
      action: 'call_recorded',
      entityType: 'battery',
      entityId: battery.bpId,
      metadata: {'durationSeconds': durationSeconds},
    ),);
    notifyListeners();
  }

  // --- Validation -------------------------------------------------------------

  /// Validates one section's visible fields; returns a localized error or
  /// null when valid.
  String? validateSection(StepConfig section, Translate t) {
    for (final f in visibleFields(section)) {
      if (f.type == 'proof') {
        final p = _proofs[f.id];
        if (isRequired(f) && p == null) return t('validation.proofRequired');
        if (p != null && f.proofKind == 'recovery' && !isProofWithinGeofence(p)) {
          return t('validation.geofence');
        }
        continue;
      }
      if (f.type == 'otp') {
        final v = _values[f.id] as String?;
        if (isRequired(f) && !Validators.isValidOtp(v)) {
          return t('validation.otpRequired');
        }
        continue;
      }
      if (f.type == 'phone') {
        final v = _values[f.id] as String?;
        if ((isRequired(f) || (v != null && v.isNotEmpty)) &&
            !Validators.isValidMobile(v)) {
          return t('validation.invalidMobile');
        }
        continue;
      }
      if (isRequired(f) && !Validators.isNotEmpty(_values[f.id])) {
        if (f.id == 'outcome') return t('validation.outcomeRequired');
        return t('validation.required');
      }
    }
    return null;
  }

  // --- Save one action section (item 4/13) ------------------------------------

  /// Validates + persists [section] as a draft. Any BP action can be saved
  /// independently, in any order, without touching the others.
  Future<String?> saveSection(StepConfig section, Translate t) async {
    final error = validateSection(section, t);
    if (error != null) return error;

    if (section.id == 'call') await _maybeUpdateMobile();
    if (section.id == 'home_visit') await _maybeUpdateAddress();

    // The visit sections record their own attempt against the attempts
    // service. Same not-fatal contract as the Outcome submission: a rejection
    // or an unreachable service is logged and the local draft still saves, so
    // the agent never loses what they entered. Check
    // [lastSectionSubmittedToService] afterwards to tell the agent whether it
    // reached the server. Runs after the customer mobile/address writes above
    // so an updated address is already reflected in the submission.
    if (recordsOwnAttempt(section.id)) {
      _submitting = true;
      notifyListeners();
      try {
        lastSectionSubmittedToService = await _submitSectionAttempt(section);
      } finally {
        _submitting = false;
        notifyListeners();
      }
    }

    await _persistDraft();
    unawaited(_auditLog.log(
      agentId: agentId,
      action: 'attempt_section_saved',
      entityType: 'battery',
      entityId: battery.bpId,
      metadata: {'section': section.id},
    ),);
    return null;
  }

  Future<void> _maybeUpdateMobile() async {
    final mobile = (_values['newCustomerMobile'] as String?)?.trim();
    if (mobile == null || mobile.isEmpty || mobile == battery.customer.mobile) return;
    await _updateCustomerField(battery.customer.copyWith(mobile: mobile), 'mobile');
  }

  Future<void> _maybeUpdateAddress() async {
    final address = (_values['newCustomerAddress'] as String?)?.trim();
    if (address == null || address.isEmpty || address == battery.customer.address) return;
    await _updateCustomerField(battery.customer.copyWith(address: address), 'address');
  }

  /// Applies the edit locally right away (offline-first UX — the agent's
  /// input is never silently lost) and either confirms it against the
  /// server immediately or, on failure (CC-04), queues it for retry.
  Future<void> _updateCustomerField(Customer updated, String field) async {
    battery.customer = updated;
    final result = await _updateCustomer(UpdateCustomerParams(battery.bpId, updated));
    if (result.isErr) {
      await _syncQueue.enqueue('update_customer', {
        'bpId': battery.bpId,
        'customer': updated.toJson(),
      });
    }
    unawaited(_auditLog.log(
      agentId: agentId,
      action: 'customer_updated',
      entityType: 'battery',
      entityId: battery.bpId,
      metadata: {'field': field, 'queued': result.isErr},
    ),);
  }

  Future<void> _persistDraft() => _saveDraft(SaveDraftParams(
        battery.bpId,
        DraftAttempt(values: Map.of(_values), proofs: Map.of(_proofs)),
      ),);

  // --- Outcome: build & submit -------------------------------------------------

  String get selectedOutcome => (_values['outcome'] as String?) ?? '';

  String get resolution {
    final opt = _config.optionByValue('outcome', selectedOutcome);
    return opt?.stringExtra('resolution') ?? '';
  }

  bool get requiresApproval {
    final opt = _config.optionByValue('outcome', selectedOutcome);
    return opt?.boolExtra('requiresApproval') ?? false;
  }

  String _buildRemark() {
    final parts = <String>[];
    final calling = (_values['callingRemark'] as String?)?.trim();
    if (calling != null && calling.isNotEmpty) parts.add(calling);
    final locationRemark = (_values['locationRemark'] as String?)?.trim();
    if (locationRemark != null && locationRemark.isNotEmpty) parts.add(locationRemark);
    final customerVisitRemark = (_values['customerVisitRemark'] as String?)?.trim();
    if (customerVisitRemark != null && customerVisitRemark.isNotEmpty) {
      parts.add(customerVisitRemark);
    }
    final batteryNote = (_values['batteryRemarkNote'] as String?)?.trim();
    final batteryReason = _values['batteryRemarkReason'] as String?;
    if (batteryReason != null || (batteryNote?.isNotEmpty ?? false)) {
      final label = batteryReason == null
          ? ''
          : (_config.optionByValue('batteryRemarkReason', batteryReason)?.labelKey ?? batteryReason);
      parts.add('Battery: $label${batteryNote?.isNotEmpty ?? false ? ' — $batteryNote' : ''}');
    }
    final customerNote = (_values['customerRemarkNote'] as String?)?.trim();
    final customerReason = _values['customerRemarkReason'] as String?;
    if (customerReason != null || (customerNote?.isNotEmpty ?? false)) {
      final label = customerReason == null
          ? ''
          : (_config.optionByValue('customerRemarkReason', customerReason)?.labelKey ?? customerReason);
      parts.add('Customer: $label${customerNote?.isNotEmpty ?? false ? ' — $customerNote' : ''}');
    }
    return parts.join(' | ');
  }

  Attempt buildAttempt() {
    final gps = _arrivalGps ??
        (_proofs.values.isNotEmpty ? _proofs.values.first.location : battery.lastKnownLocation);
    return Attempt(
      id: 'pending',
      bpId: battery.bpId,
      sequence: battery.attemptCount + 1,
      createdAt: DateTime.now(),
      gps: gps,
      outcome: selectedOutcome,
      resolution: resolution,
      values: Map<String, dynamic>.from(_values),
      proofs: _proofs.values.toList(),
      remark: _buildRemark(),
    );
  }

  // --- Attempt submission (POST /api/v1/attempts) ------------------------------

  /// Attempt channel for the Update Status flow.
  static const _submissionAttemptType = 'field_visit';

  /// Records when the agent first entered the Update Status screen (idempotent
  /// — later re-entries don't reset it). Drives `attemptedAt`.
  void markUpdateStatusOpened() => _updateStatusOpenedAt ??= DateTime.now();

  /// A random UUID v4 for the attempt `id` (no uuid package in this project).
  String _generateAttemptId() {
    final rng = Random();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Blob URLs of proofs captured on this attempt that have finished uploading.
  List<String> _proofUrls() =>
      _proofs.values.map((p) => p.remoteUrl).whereType<String>().toList();

  /// Blob URLs of the proofs belonging to [section] only — used when a single
  /// section POSTs its own attempt and must not carry another section's photos.
  ///
  /// Awaits that section's still-running uploads first: capture fires the
  /// upload in the background, so without this a quick Save would send an empty
  /// `proofUrls` even though the photo uploads fine a moment later. Failed
  /// uploads leave `remoteUrl` null and are simply omitted (never block Save).
  Future<List<String>> _proofUrlsForSection(StepConfig section) async {
    final ids = section.fields
        .where((f) => f.type == 'proof')
        .map((f) => f.id)
        .toList();
    final pending = ids.map((id) => _uploadTasks[id]).whereType<Future<void>>();
    if (pending.isNotEmpty) await Future.wait(pending);
    return ids
        .map((id) => _proofs[id]?.remoteUrl)
        .whereType<String>()
        .toList();
  }

  /// Every Update Status field value not mapped to a first-class column — sent
  /// as `metadata` so nothing the agent entered is dropped.
  Map<String, dynamic> _submissionMetadata() => {
        for (final f in outcomeSection.fields)
          if (f.id != 'outcome' && _values[f.id] != null) f.id: _values[f.id],
      };

  /// Builds the [AttemptSubmission] from the Update Status screen state.
  /// [completedAt]/[gps] are captured at Submit time by the caller.
  AttemptSubmission buildAttemptSubmission({
    required DateTime completedAt,
    required GeoPoint gps,
  }) =>
      AttemptSubmission(
        id: _generateAttemptId(),
        ticketId: ticketId,
        batteryId: battery.bpId,
        // The signed-in agent's id — the `commonLogin` partnerId carried into
        // the session on login (see `PersistedSession.apiAgentId`), passed down
        // from the ticket screen. Never a hard-coded id: after a logout the next
        // sign-in submits attempts under ITS own agent.
        agentId: agentId,
        agentName: agentName,
        attemptType: _submissionAttemptType,
        // The app's snake_case outcome vocabulary (dropdowns.json `outcome`)
        // already matches the attempts service's allowed enum values verbatim
        // (recovered, fir, not_found_refused, customer_not_cooperating), so we
        // send it raw. The service 422s "Invalid outcome" on anything else.
        outcome: selectedOutcome,
        attemptedAt: _updateStatusOpenedAt ?? DateTime.now(),
        completedAt: completedAt,
        latitude: gps.lat,
        longitude: gps.lng,
        // No customer-presence signal is captured on this screen; always false.
        customerPresent: false,
        notes: _buildRemark(),
        proofUrls: _proofUrls(),
        metadata: _submissionMetadata(),
      );

  // --- Visit sections: each records its own attempt POST ----------------------

  /// Which `_values` keys a visit section maps onto the submission's `outcome`
  /// and `notes`, and the `attemptType` it reports.
  ///
  /// NOTE on `attemptType`: the service enum-validates this and 422s
  /// "Invalid attemptType — Must be one of: call, field_visit, home_visit,
  /// recovery." on anything else, so these are wire values, NOT screen labels.
  /// Both visit sections deliberately report `field_visit` — the service does
  /// also accept `home_visit`, but keeping one value means the two sections
  /// aren't told apart by `attemptType`; `metadata` carries the section's own
  /// fields (e.g. `homeVisitStatus` vs `visitStatus`) if they need separating.
  static const _sectionAttempts = <String, _SectionAttemptSpec>{
    'call': _SectionAttemptSpec(
      attemptType: 'call',
      // "Call Status" (callStatus) — the dropdown's value goes out as `outcome`.
      outcomeField: 'callStatus',
      // "What did the customer say?" — the agent's free-text account of the call.
      notesField: 'callingRemark',
    ),
    'location_visit': _SectionAttemptSpec(
      attemptType: 'field_visit',
      // "What happened at the location" (bpLocationStatus).
      outcomeField: 'visitStatus',
      notesField: 'locationRemark',
    ),
    'home_visit': _SectionAttemptSpec(
      attemptType: 'field_visit',
      // "Battery status at location" (homeVisitStatus).
      outcomeField: 'homeVisitStatus',
      notesField: 'customerVisitRemark',
    ),
  };

  /// True when [sectionId] POSTs its own attempt record on Save.
  bool recordsOwnAttempt(String sectionId) =>
      _sectionAttempts.containsKey(sectionId);

  /// Records when the agent first entered [sectionId]'s screen (idempotent —
  /// re-entering doesn't reset it). Drives `attemptedAt`; `completedAt` is
  /// stamped at Save.
  void markSectionOpened(String sectionId) =>
      _sectionOpenedAt.putIfAbsent(sectionId, DateTime.now);

  /// App-value → service-value translation for a visit `outcome`.
  ///
  /// The visit dropdowns (`bpLocationStatus`, `homeVisitStatus`) are worded for
  /// the agent, not for the wire, and the attempts service enum-validates
  /// `outcome` — it 422s "Invalid outcome" on anything outside its list. Values
  /// absent from this map are sent verbatim, so only the values whose app
  /// spelling differs from the service member need an entry here.
  ///
  /// `bpLocationStatus` (`battery_found`, `battery_not_found`,
  /// `location_inaccessible`, `other`) is deliberately absent: the service is
  /// adding those members under the same names, so all four go out verbatim.
  ///
  /// `callStatus` (`connected`, `not_responding`, `call_disconnected`,
  /// `switched_off`, `wrong_number`, `error`) is absent for the same reason —
  /// the Call Customer dropdown value is sent exactly as configured. If the
  /// service hasn't added these members yet it will 422 "Invalid outcome"; map
  /// the app value to whatever it does accept here rather than editing
  /// `dropdowns.json`, which is what the agent sees.
  static const Map<String, String> _visitOutcomeWireValues = {
    // homeVisitStatus — the service spells these two differently from the app.
    // "Yes, I saw a customer" and "Customer Not Available"; the third option,
    // `address_not_found`, already matches its member and passes through.
    'visit_done': 'customer_seen',
    'not_available': 'customer_not_available',
  };

  /// Everything the agent entered on [section], plus the customer's name, sent
  /// as `metadata` so nothing is dropped. Picks up the section's own text
  /// fields automatically — e.g. Visit Customer Address's "Updated Customer
  /// Address" (`newCustomerAddress`).
  Map<String, dynamic> _sectionMetadata(StepConfig section) => {
        'customerName': battery.customer.name,
        for (final f in section.fields)
          if (f.type != 'proof' && _values[f.id] != null) f.id: _values[f.id],
      };

  /// Builds the [AttemptSubmission] for a visit [section].
  ///
  /// [gps] is sent as top-level `latitude`/`longitude`; the service derives and
  /// stores the `location` JSON string from them (see [AttemptSubmission] — a
  /// `location` sent in the request body is ignored and persists null).
  AttemptSubmission buildSectionAttemptSubmission({
    required StepConfig section,
    required DateTime completedAt,
    required GeoPoint gps,
    required List<String> proofUrls,
  }) {
    final spec = _sectionAttempts[section.id]!;
    final selected = (_values[spec.outcomeField] as String?) ?? '';
    return AttemptSubmission(
      id: _generateAttemptId(),
      // Human identifiers, as the service requires — the ticket number shown
      // as "Case ID" on the ticket detail screen and the BP id, both handed
      // down from that screen through TicketActionsHub.
      ticketId: ticketId,
      batteryId: battery.bpId,
      agentId: agentId,
      agentName: agentName,
      attemptType: spec.attemptType,
      outcome: _visitOutcomeWireValues[selected] ?? selected,
      attemptedAt: _sectionOpenedAt[section.id] ?? DateTime.now(),
      completedAt: completedAt,
      latitude: gps.lat,
      longitude: gps.lng,
      // Neither visit section captures an explicit customer-presence signal —
      // "Battery status at location" is about the battery, not who answered.
      customerPresent: false,
      notes: (_values[spec.notesField] as String?)?.trim() ?? '',
      proofUrls: proofUrls,
      metadata: _sectionMetadata(section),
    );
  }

  /// True when the last visit-section save got a 2xx from the attempts service.
  /// False when it was rejected, unreachable, or not wired at all — the draft
  /// is saved locally either way.
  bool lastSectionSubmittedToService = false;

  /// POSTs [section]'s attempt. Mirrors [_submitAttemptToService]: the use case
  /// wraps errors in a [Result] so this never throws, and a failure is logged
  /// rather than blocking the agent's local save.
  Future<bool> _submitSectionAttempt(StepConfig section) async {
    final submit = _submitAttemptRecord;
    if (submit == null) return false; // not wired (e.g. unit tests) — skip.
    // Await this section's photo uploads before stamping completedAt, so the
    // timestamp reflects when the record was actually sent.
    final proofUrls = await _proofUrlsForSection(section);
    // The geo-tag on the section's proof is the evidence that the agent stood
    // at the place they're reporting on; fall back to a fresh device fix when
    // no photo was captured (the proof is optional unless its
    // `proof.mandatoryFor*` flag is set).
    final proofFieldId = section.fields
        .where((f) => f.type == 'proof')
        .map((f) => f.id)
        .firstOrNull;
    final proofGps =
        proofFieldId == null ? null : _proofs[proofFieldId]?.location;
    final gps = proofGps ?? await _location.currentLocation();
    final submission = buildSectionAttemptSubmission(
      section: section,
      completedAt: DateTime.now(),
      gps: gps,
      proofUrls: proofUrls,
    );
    final result = await submit(submission);
    if (result.isErr) {
      developer.log(
        '${section.id} attempt submission failed: '
        '${result.failureOrNull?.message}',
        name: 'AttemptController',
      );
      return false;
    }
    return true;
  }

  /// True when the last [submitOutcome] call queued the write for later sync
  /// (CC-04 — offline/unreachable) instead of confirming it immediately.
  bool lastOutcomeWasQueued = false;

  /// True when the last [submitOutcome] call got a 2xx back from the attempts
  /// service (POST /attempts). The status IS recorded server-side in that case,
  /// so the UI confirms it outright — even if the ticket-side write behind
  /// [lastOutcomeWasQueued] had to be queued.
  bool lastOutcomeSubmittedToService = false;

  /// Validates + submits the Outcome action, finalizing the attempt and
  /// clearing the draft. Returns a localized error, or null on success (check
  /// [lastOutcomeSubmittedToService]/[requiresApproval]/[lastOutcomeWasQueued]
  /// afterwards to pick the right success message).
  Future<String?> submitOutcome(TicketProvider tickets, Translate t) async {
    final error = validateSection(outcomeSection, t);
    if (error != null) return error;

    _submitting = true;
    notifyListeners();
    try {
      // POST the attempt to the standalone attempts service. Timestamped at
      // the moment of submit and geo-tagged with the agent's current location.
      // A failure here is logged, not fatal — the local attempt flow below
      // still records the outcome (and queues offline via [tickets]).
      lastOutcomeSubmittedToService = await _submitAttemptToService();

      await tickets.submitAttempt(ticketId, battery, buildAttempt());
      lastOutcomeWasQueued = tickets.lastSubmitWasQueued;
      await _saveDraft(SaveDraftParams(battery.bpId, const DraftAttempt()));
      unawaited(_auditLog.log(
        agentId: agentId,
        action: 'outcome_submitted',
        entityType: 'battery',
        entityId: battery.bpId,
        metadata: {'outcome': selectedOutcome, 'resolution': resolution},
      ),);
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Builds and POSTs the [AttemptSubmission] to the attempts service. The
  /// use case wraps errors in a [Result], so this never throws; a non-2xx or
  /// network failure is logged and the outcome flow proceeds regardless.
  /// Returns true only when the service accepted the attempt.
  Future<bool> _submitAttemptToService() async {
    final submit = _submitAttemptRecord;
    if (submit == null) return false; // not wired (e.g. unit tests) — skip.
    final completedAt = DateTime.now();
    final gps = await _location.currentLocation();
    final submission =
        buildAttemptSubmission(completedAt: completedAt, gps: gps);
    final result = await submit(submission);
    if (result.isErr) {
      developer.log(
        'attempt submission failed: ${result.failureOrNull?.message}',
        name: 'AttemptController',
      );
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    // Leaving the Call Customer screen mid-call must not leave a platform
    // listener attached to a dead controller.
    _simCallSub?.cancel();
    _simCallSub = null;
    super.dispose();
  }
}
