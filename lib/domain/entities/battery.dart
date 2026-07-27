import 'package:asset_recovery_app/domain/entities/attempt.dart';
import 'package:asset_recovery_app/domain/entities/customer.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// A battery pack (BP) under recovery. One BP maps to exactly one active ticket
/// (PRD §4.1). Carries all attributes shown in the BP detail view (§5.2.2).
class Battery {
  Battery({
    required this.bpId,
    required this.caseType,
    required this.customer,
    required this.lastKnownLocation,
    required this.zoneStatus,
    required this.bpState,
    this.dealerName = '',
    this.dealerContact = '',
    this.vehicleType = '',
    this.vehicleRegNo = '',
    this.bpType = '',
    this.vehicleId = '',
    this.tiuStatus = '',
    this.soc,
    this.homeAddress = '',
    this.distanceKm,
    this.vin = '',
    this.lastSwap,
    this.lastStation = '',
    this.lastTiuTime = '',
    this.inactiveDays,
    this.riskScore,
    this.riskCategory,
    this.zone = '',
    this.subzone = '',
    List<Attempt>? attempts,
  }) : attempts = attempts ?? [];

  final String bpId;

  /// Theft / At-Risk / Impound / AMD / Manual.
  final String caseType;

  Customer customer;
  GeoPoint lastKnownLocation;
  ZoneStatus zoneStatus;
  BpState bpState;
  String dealerName;
  String dealerContact;
  String vehicleType;
  String vehicleRegNo;

  /// Battery pack type/model as classified by the backend (e.g. pack chemistry
  /// or SKU). Empty when the backend hasn't populated it.
  String bpType;

  /// Internal fleet vehicle identifier — distinct from [vehicleRegNo] (the
  /// number plate) and [vin]. Empty when this case's vehicle isn't part of
  /// the managed fleet (e.g. a customer-owned vehicle).
  String vehicleId;
  String tiuStatus;
  int? soc;
  String homeAddress;

  /// Case-level geography (independent of the assigned agent's own
  /// operating zone/cluster).
  String zone;
  String subzone;

  /// Vehicle Identification Number shown in the BP detail header.
  String vin;
  DateTime? lastSwap;
  String lastStation;
  String lastTiuTime;

  /// Days the BP/vehicle has been inactive (Figma "Inactive 30days").
  int? inactiveDays;

  /// ML-computed return-risk score (0-100) and category ("low"/"medium"/
  /// "high"), read-only per PRD M2-03 — the app only ever displays these,
  /// never computes or edits them. Null when the backend hasn't scored this
  /// BP yet. Visibility is gated by `features.riskVisibility` in the UI.
  double? riskScore;
  String? riskCategory;

  /// Last computed road distance from the agent, in km. Refreshable (§4.8).
  double? distanceKm;

  final List<Attempt> attempts;

  int get attemptCount => attempts.length;
  Attempt? get latestAttempt => attempts.isEmpty ? null : attempts.last;
  bool get isResolved =>
      latestAttempt != null && latestAttempt!.resolution.isNotEmpty &&
      _terminalResolutions.contains(latestAttempt!.resolution);

  static const _terminalResolutions = {
    'Swap (Organic)',
    'Swap (Assisted)',
    'Recovered',
    'FIR',
    'Customer Not Cooperating',
    'Auto-expired',
  };

  factory Battery.fromJson(Map<String, dynamic> json) => Battery(
        bpId: json['bpId'] as String,
        caseType: json['caseType'] as String? ?? 'Manual',
        customer: Customer.fromJson(json['customer'] as Map<String, dynamic>),
        lastKnownLocation:
            GeoPoint.fromJson(json['lastKnownLocation'] as Map<String, dynamic>),
        zoneStatus: zoneFromString(json['zoneStatus'] as String?),
        bpState: bpStateFromString(json['bpState'] as String?),
        dealerName: json['dealerName'] as String? ?? '',
        dealerContact: json['dealerContact'] as String? ?? '',
        vehicleType: json['vehicleType'] as String? ?? '',
        vehicleRegNo: json['vehicleRegNo'] as String? ?? '',
        bpType: json['bpType'] as String? ?? '',
        vehicleId: json['vehicleId'] as String? ?? '',
        tiuStatus: json['tiuStatus'] as String? ?? '',
        soc: (json['soc'] as num?)?.toInt(),
        homeAddress: json['homeAddress'] as String? ?? '',
        distanceKm: (json['distanceKm'] as num?)?.toDouble(),
        vin: json['vin'] as String? ?? '',
        lastSwap: json['lastSwap'] == null
            ? null
            : DateTime.tryParse(json['lastSwap'] as String),
        lastStation: json['lastStation'] as String? ?? '',
        lastTiuTime: json['lastTiuTime'] as String? ?? '',
        inactiveDays: (json['inactiveDays'] as num?)?.toInt(),
        riskScore: (json['riskScore'] as num?)?.toDouble(),
        riskCategory: json['riskCategory'] as String?,
        zone: json['zone'] as String? ?? '',
        subzone: json['subzone'] as String? ?? '',
        attempts: (json['attempts'] as List?)
            ?.map((e) => Attempt.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'bpId': bpId,
        'caseType': caseType,
        'customer': customer.toJson(),
        'lastKnownLocation': lastKnownLocation.toJson(),
        'zoneStatus': zoneStatus.name,
        'bpState': bpState.name,
        'dealerName': dealerName,
        'dealerContact': dealerContact,
        'vehicleType': vehicleType,
        'vehicleRegNo': vehicleRegNo,
        'bpType': bpType,
        'vehicleId': vehicleId,
        'tiuStatus': tiuStatus,
        'soc': soc,
        'homeAddress': homeAddress,
        'distanceKm': distanceKm,
        'vin': vin,
        'lastSwap': lastSwap?.toIso8601String(),
        'lastStation': lastStation,
        'lastTiuTime': lastTiuTime,
        'inactiveDays': inactiveDays,
        'riskScore': riskScore,
        'riskCategory': riskCategory,
        'zone': zone,
        'subzone': subzone,
        'attempts': attempts.map((a) => a.toJson()).toList(),
      };
}
