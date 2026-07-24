import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// A captured proof artifact (image/screenshot/document) with embedded GPS and
/// timestamp. Mandatory-proof enforcement (PRD §4.3) is validated in the
/// attempt provider before submission.
class Proof {
  const Proof({
    required this.kind,
    required this.localPath,
    required this.capturedAt,
    required this.location,
    this.remoteUrl,
    this.uploaded = false,
  });

  final ProofKind kind;
  final String localPath;
  final DateTime capturedAt;
  final GeoPoint location;
  final String? remoteUrl;
  final bool uploaded;

  bool get hasValidGeoTag =>
      location.lat != 0 && location.lng != 0 && capturedAt.year > 2000;

  /// Returns a copy with the remote-upload fields set — used once the image has
  /// been uploaded to blob storage to record its [remoteUrl].
  Proof copyWith({String? remoteUrl, bool? uploaded}) => Proof(
        kind: kind,
        localPath: localPath,
        capturedAt: capturedAt,
        location: location,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        uploaded: uploaded ?? this.uploaded,
      );

  factory Proof.fromJson(Map<String, dynamic> json) => Proof(
        kind: proofKindFromString(json['kind'] as String?),
        localPath: json['localPath'] as String? ?? '',
        capturedAt: DateTime.parse(json['capturedAt'] as String),
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        remoteUrl: json['remoteUrl'] as String?,
        uploaded: json['uploaded'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'localPath': localPath,
        'capturedAt': capturedAt.toIso8601String(),
        'location': location.toJson(),
        if (remoteUrl != null) 'remoteUrl': remoteUrl,
        'uploaded': uploaded,
      };
}
