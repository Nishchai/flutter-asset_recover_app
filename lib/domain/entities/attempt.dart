import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/entities/proof.dart';

/// A single recovery attempt against a BP. Captures the data collected through
/// the config-driven wizard plus the system-recorded metadata (PRD §5.2.4).
///
/// [values] holds the dynamic form field values keyed by field id, so adding a
/// field to `attempt_flow.json` requires no model change.
class Attempt {
  const Attempt({
    required this.id,
    required this.bpId,
    required this.sequence,
    required this.createdAt,
    required this.gps,
    required this.outcome,
    required this.resolution,
    required this.values,
    required this.proofs,
    this.remark = '',
  });

  final String id;
  final String bpId;
  final int sequence;
  final DateTime createdAt;
  final GeoPoint gps;

  /// Outcome option value, e.g. `recovered`, `swap_assisted`, `refused`.
  final String outcome;

  /// Human-readable resolution, e.g. `Swap (Assisted)`. Empty for non-terminal.
  final String resolution;

  /// All dynamic field values from the wizard, keyed by field id.
  final Map<String, dynamic> values;

  final List<Proof> proofs;
  final String remark;

  factory Attempt.fromJson(Map<String, dynamic> json) => Attempt(
        id: json['id'] as String,
        bpId: json['bpId'] as String,
        sequence: (json['sequence'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        gps: GeoPoint.fromJson(json['gps'] as Map<String, dynamic>),
        outcome: json['outcome'] as String? ?? '',
        resolution: json['resolution'] as String? ?? '',
        values: (json['values'] as Map?)?.cast<String, dynamic>() ?? {},
        proofs: (json['proofs'] as List?)
                ?.map((e) => Proof.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        remark: json['remark'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bpId': bpId,
        'sequence': sequence,
        'createdAt': createdAt.toIso8601String(),
        'gps': gps.toJson(),
        'outcome': outcome,
        'resolution': resolution,
        'values': values,
        'proofs': proofs.map((p) => p.toJson()).toList(),
        'remark': remark,
      };
}
