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
    this.priority = 0,
    this.slaDeadline,
    this.overdueDays = 0,
    this.agentName = '',
    this.resolutionType = '',
    this.isEmergency = false,
    this.routeCode = '',
    this.daysSinceLastAttempt = 0,
    this.batteryCount = 0,
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

  /// Backend priority rank (higher = more urgent). Drives list ordering.
  int priority;

  /// Absolute SLA breach timestamp from the backend. Distinct from the
  /// [slaDaysLeft] helper, which estimates a deadline off [createdAt] + a
  /// configured window; when the backend supplies this, prefer it.
  DateTime? slaDeadline;

  /// Days the ticket is past its SLA deadline (0 when still within SLA).
  int overdueDays;

  /// Display name of the currently assigned agent (companion to
  /// [assignedAgentId]).
  String agentName;

  /// How the case was resolved once closed (e.g. "swap", "fir"); empty while
  /// the ticket is still open.
  String resolutionType;

  /// Backend-flagged emergency case, surfaced with priority treatment in the UI.
  bool isEmergency;

  /// Route the case belongs to within the [cluster]/zone (companion to
  /// [Battery.zone]).
  String routeCode;

  /// Days since the last recovery attempt was logged against this ticket.
  int daysSinceLastAttempt;

  /// Battery count as reported by the backend summary. May differ from
  /// [bpCount] (the number of [batteries] actually loaded into this model),
  /// which in Phase 1 is always the single reconstructed BP.
  int batteryCount;

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
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        slaDeadline: json['slaDeadline'] == null
            ? null
            : DateTime.tryParse(json['slaDeadline'] as String),
        overdueDays: (json['overdueDays'] as num?)?.toInt() ?? 0,
        agentName: json['agentName'] as String? ?? '',
        resolutionType: json['resolutionType'] as String? ?? '',
        isEmergency: json['isEmergency'] as bool? ?? false,
        routeCode: json['routeCode'] as String? ?? '',
        daysSinceLastAttempt:
            (json['daysSinceLastAttempt'] as num?)?.toInt() ?? 0,
        batteryCount: (json['batteryCount'] as num?)?.toInt() ?? 0,
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
        'priority': priority,
        'slaDeadline': slaDeadline?.toIso8601String(),
        'overdueDays': overdueDays,
        'agentName': agentName,
        'resolutionType': resolutionType,
        'isEmergency': isEmergency,
        'routeCode': routeCode,
        'daysSinceLastAttempt': daysSinceLastAttempt,
        'batteryCount': batteryCount,
        'batteries': batteries.map((b) => b.toJson()).toList(),
      };
}
