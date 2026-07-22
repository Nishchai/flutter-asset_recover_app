/// A single audit-log entry (item 15 / PRD §5.1.3, §7.A — status transitions,
/// approvals and other state-changing actions must be logged with a
/// timestamp and user). The full audit dashboard lives on the coordinator Web
/// App; this mobile app is only responsible for emitting these events.
class AuditEvent {
  AuditEvent({
    required this.agentId,
    required this.action,
    required this.timestamp,
    this.entityType,
    this.entityId,
    this.metadata = const {},
  });

  final String agentId;

  /// e.g. `attempt_section_saved`, `outcome_submitted`, `customer_updated`,
  /// `otp_verified`, `login`, `logout`.
  final String action;
  final DateTime timestamp;
  final String? entityType;
  final String? entityId;
  final Map<String, dynamic> metadata;

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        agentId: json['agentId'] as String,
        action: json['action'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        entityType: json['entityType'] as String?,
        entityId: json['entityId'] as String?,
        metadata: json['metadata'] == null
            ? const {}
            : Map<String, dynamic>.from(json['metadata'] as Map),
      );

  Map<String, dynamic> toJson() => {
        'agentId': agentId,
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        if (entityType != null) 'entityType': entityType,
        if (entityId != null) 'entityId': entityId,
        'metadata': metadata,
      };
}
