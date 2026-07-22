import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';

/// A recovery case. One ticket contains exactly one BP in Phase 1 (PRD §4.1),
/// but the model holds a list to stay forward-compatible with multi-BP cases.
class Ticket {
  Ticket({
    required this.ticketId,
    required this.status,
    required this.createdAt,
    required this.assignedAgentId,
    required this.batteries,
    this.cluster = '',
    this.reason = '',
    this.closedAt,
    this.reassignmentCount = 0,
    this.caseId = '',
    this.caseSource = '',
  });

  final String ticketId;
  TicketStatus status;
  final DateTime createdAt;
  String assignedAgentId;
  final List<Battery> batteries;
  String cluster;
  String reason;
  DateTime? closedAt;
  int reassignmentCount;

  /// Case reference from the upstream system that raised this ticket (e.g.
  /// theft dashboard, TIU inactivity alert) — distinct from [ticketId], which
  /// is this app's own recovery-workflow identifier.
  String caseId;

  /// Where the case originated, e.g. "Theft Dashboard", "TIU Alert", "Manual".
  String caseSource;

  Battery get primaryBp => batteries.first;
  int get bpCount => batteries.length;

  int get totalAttempts =>
      batteries.fold(0, (sum, b) => sum + b.attemptCount);

  /// Days remaining before SLA breach, given the configured SLA window.
  int slaDaysLeft(int slaDays, DateTime now) {
    final deadline = createdAt.add(Duration(days: slaDays));
    return deadline.difference(now).inDays;
  }

  /// Age of the ticket in hours (used for "38h" style labels).
  int ageHours(DateTime now) => now.difference(createdAt).inHours;

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        ticketId: json['ticketId'] as String,
        status: TicketStatus.fromString(json['status'] as String?),
        createdAt: DateTime.parse(json['createdAt'] as String),
        assignedAgentId: json['assignedAgentId'] as String? ?? '',
        cluster: json['cluster'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        closedAt: json['closedAt'] == null
            ? null
            : DateTime.tryParse(json['closedAt'] as String),
        reassignmentCount: (json['reassignmentCount'] as num?)?.toInt() ?? 0,
        caseId: json['caseId'] as String? ?? '',
        caseSource: json['caseSource'] as String? ?? '',
        batteries: (json['batteries'] as List)
            .map((e) => Battery.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'ticketId': ticketId,
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
        'assignedAgentId': assignedAgentId,
        'cluster': cluster,
        'reason': reason,
        'closedAt': closedAt?.toIso8601String(),
        'reassignmentCount': reassignmentCount,
        'caseId': caseId,
        'caseSource': caseSource,
        'batteries': batteries.map((b) => b.toJson()).toList(),
      };
}
