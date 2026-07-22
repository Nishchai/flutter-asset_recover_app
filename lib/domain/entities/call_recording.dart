/// A recorded in-app call (Rule 8a — Ozonetel click-to-call). The real
/// integration proxies the call through Ozonetel's cloud, which records and
/// hosts the audio; this app only stores the resulting metadata + URL.
class CallRecording {
  const CallRecording({
    required this.id,
    required this.bpId,
    required this.startedAt,
    required this.durationSeconds,
    this.recordingUrl,
  });

  final String id;
  final String bpId;
  final DateTime startedAt;
  final int durationSeconds;
  final String? recordingUrl;

  factory CallRecording.fromJson(Map<String, dynamic> json) => CallRecording(
        id: json['id'] as String,
        bpId: json['bpId'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        recordingUrl: json['recordingUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bpId': bpId,
        'startedAt': startedAt.toIso8601String(),
        'durationSeconds': durationSeconds,
        if (recordingUrl != null) 'recordingUrl': recordingUrl,
      };
}
