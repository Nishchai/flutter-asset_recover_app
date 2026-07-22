import 'package:asset_recovery_app/domain/entities/proof.dart';

/// Partially-completed recovery attempt data (item 13 — "partial attempts and
/// details to be saved for future actions"). Since the Ticket Actions hub lets
/// the Field Agent fill Call / Visit BP / Visit Customer / Outcome in any
/// order and across app sessions, whatever has been captured so far is
/// persisted here until the Outcome action is submitted, at which point the
/// draft is cleared and folded into a real [Attempt].
class DraftAttempt {
  const DraftAttempt({this.values = const {}, this.proofs = const {}});

  final Map<String, dynamic> values;
  final Map<String, Proof> proofs;

  factory DraftAttempt.fromJson(Map<String, dynamic> json) => DraftAttempt(
        values: (json['values'] as Map?)?.cast<String, dynamic>() ?? {},
        proofs: (json['proofs'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, Proof.fromJson(v as Map<String, dynamic>)),
            ) ??
            {},
      );

  Map<String, dynamic> toJson() => {
        'values': values,
        'proofs': proofs.map((k, v) => MapEntry(k, v.toJson())),
      };
}
