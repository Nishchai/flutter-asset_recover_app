import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// The signed-in field agent. [cluster] enforces cluster-based data access
/// (PRD §4.6) — the agent only sees tickets within their cluster. [role] is
/// RBAC groundwork (item 15) — always [AgentRole.fieldAgent] in Phase 1 since
/// this mobile app is field-agent-only; the full permission matrix lives on
/// the coordinator Web App.
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.cluster,
    required this.recoveredCount,
    this.zone = '',
    this.currentLocation,
    this.phone = '',
    this.role = AgentRole.fieldAgent,
  });

  final String id;
  final String name;
  final String cluster;
  final AgentRole role;

  /// Shift sub-zone within the cluster (Figma "Bengaluru South · Zone 4").
  final String zone;
  final int recoveredCount;
  final GeoPoint? currentLocation;
  final String phone;

  /// "Bengaluru South · Zone 4" for the shift banner.
  String get shiftArea => zone.isEmpty ? cluster : '$cluster · $zone';

  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Agent copyWith({GeoPoint? currentLocation}) => Agent(
        id: id,
        name: name,
        cluster: cluster,
        zone: zone,
        recoveredCount: recoveredCount,
        currentLocation: currentLocation ?? this.currentLocation,
        phone: phone,
        role: role,
      );

  factory Agent.fromJson(Map<String, dynamic> json) => Agent(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        cluster: json['cluster'] as String? ?? '',
        zone: json['zone'] as String? ?? '',
        recoveredCount: (json['recoveredCount'] as num?)?.toInt() ?? 0,
        phone: json['phone'] as String? ?? '',
        role: agentRoleFromString(json['role'] as String?),
        currentLocation: json['currentLocation'] == null
            ? null
            : GeoPoint.fromJson(json['currentLocation'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cluster': cluster,
        'zone': zone,
        'recoveredCount': recoveredCount,
        'phone': phone,
        'role': role.name,
        if (currentLocation != null) 'currentLocation': currentLocation!.toJson(),
      };
}
