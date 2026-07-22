import 'dart:async';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/audit_log_service.dart';
import 'package:asset_recovery_app/core/services/location_service.dart';
import 'package:asset_recovery_app/core/services/proof_service.dart';
import 'package:asset_recovery_app/core/services/sync_queue_service.dart';
import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
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
import 'package:asset_recovery_app/domain/usecases/update_customer_usecase.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/foundation.dart';

/// Translator signature so the controller can produce localized errors without
/// depending on BuildContext.
typedef Translate = String Function(String key, [Map<String, Object?> params]);

/// How much of a section's required fields have been filled — drives the
/// status chip on each Ticket Actions hub card.
enum SectionStatus { empty, partial, done }

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
    required GetDraftUseCase getDraft,
    required SaveDraftUseCase saveDraft,
    required UpdateCustomerUseCase updateCustomer,
    required AuditLogService auditLog,
    required GetLiveLocationUseCase getLiveLocation,
    required StartCallUseCase startCallUseCase,
    required GetCallRecordingsUseCase getCallRecordings,
    required SyncQueueService syncQueue,
  })  : _config = config,
        _location = location,
        _proof = proof,
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
  final ConfigService _config;
  final LocationService _location;
  final ProofService _proof;
  final GetDraftUseCase _getDraft;
  final SaveDraftUseCase _saveDraft;
  final UpdateCustomerUseCase _updateCustomer;
  final AuditLogService _auditLog;
  final GetLiveLocationUseCase _getLiveLocation;
  final StartCallUseCase _startCallUseCase;
  final GetCallRecordingsUseCase _getCallRecordings;
  final SyncQueueService _syncQueue;

  final Map<String, dynamic> _values = {};
  final Map<String, Proof> _proofs = {};
  bool _submitting = false;
  bool _loading = true;
  GeoPoint? _arrivalGps;
  GeoPoint? _liveLocation;
  bool _fetchingLiveLocation = false;
  bool _callInProgress = false;
  List<CallRecording> _recordings = const [];

  bool get loading => _loading;
  bool get submitting => _submitting;
  GeoPoint? get liveLocation => _liveLocation;
  bool get fetchingLiveLocation => _fetchingLiveLocation;
  bool get callInProgress => _callInProgress;
  List<CallRecording> get recordings => _recordings;

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
    return captured;
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

  /// The point to navigate to / display — the freshly-fetched live location
  /// once available, falling back to the last known one.
  GeoPoint get navigationTarget => _liveLocation ?? battery.lastKnownLocation;

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

  /// True when the last [submitOutcome] call queued the write for later sync
  /// (CC-04 — offline/unreachable) instead of confirming it immediately.
  bool lastOutcomeWasQueued = false;

  /// Validates + submits the Outcome action, finalizing the attempt and
  /// clearing the draft. Returns a localized error, or null on success (check
  /// [requiresApproval]/[lastOutcomeWasQueued] afterwards to pick the right
  /// success message).
  Future<String?> submitOutcome(TicketProvider tickets, Translate t) async {
    final error = validateSection(outcomeSection, t);
    if (error != null) return error;

    _submitting = true;
    notifyListeners();
    try {
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
}
