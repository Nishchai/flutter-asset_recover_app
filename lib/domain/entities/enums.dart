/// Ticket lifecycle status. Mirrors PRD §4.2 Recovery Lifecycle and the Figma
/// home filters (Open / In Progress / Pending). `pending` = awaiting coordinator
/// approval (e.g. FIR / physical-recovery validation).
enum TicketStatus {
  assigned,
  inProgress,
  pending,
  closed,
  unrecoverable;

  static TicketStatus fromString(String? v) {
    switch (v) {
      case 'in_progress':
        return TicketStatus.inProgress;
      case 'pending':
        return TicketStatus.pending;
      case 'closed':
        return TicketStatus.closed;
      case 'unrecoverable':
        return TicketStatus.unrecoverable;
      case 'assigned':
      default:
        return TicketStatus.assigned;
    }
  }

  String get wire => switch (this) {
        TicketStatus.assigned => 'assigned',
        TicketStatus.inProgress => 'in_progress',
        TicketStatus.pending => 'pending',
        TicketStatus.closed => 'closed',
        TicketStatus.unrecoverable => 'unrecoverable',
      };
}

/// Zone status of a battery. Drives post-decision system behaviour (PRD §5.1.6).
enum ZoneStatus { field, deployed, fir, store, nonField }

ZoneStatus zoneFromString(String? v) {
  switch (v) {
    case 'deployed':
      return ZoneStatus.deployed;
    case 'fir':
      return ZoneStatus.fir;
    case 'store':
      return ZoneStatus.store;
    case 'non_field':
      return ZoneStatus.nonField;
    case 'field':
    default:
      return ZoneStatus.field;
  }
}

/// Battery state as reported by the TIU.
enum BpState { idle, charge, discharge, unknown }

BpState bpStateFromString(String? v) {
  switch (v) {
    case 'idle':
      return BpState.idle;
    case 'charge':
      return BpState.charge;
    case 'discharge':
      return BpState.discharge;
    default:
      return BpState.unknown;
  }
}

/// The kind of proof attached to an attempt step.
enum ProofKind { call, visit, home, recovery, document }

/// RBAC role (PRD §6/§7 — Web App/coordinator-side dashboard owns the full
/// permission matrix; this mobile app only ever runs as [fieldAgent] in Phase
/// 1). Kept as a forward-compatible schema field on [Agent], not a UI gate.
enum AgentRole { fieldAgent, coordinator, admin }

AgentRole agentRoleFromString(String? v) {
  switch (v) {
    case 'coordinator':
      return AgentRole.coordinator;
    case 'admin':
      return AgentRole.admin;
    case 'field_agent':
    default:
      return AgentRole.fieldAgent;
  }
}

ProofKind proofKindFromString(String? v) {
  switch (v) {
    case 'visit':
      return ProofKind.visit;
    case 'home':
      return ProofKind.home;
    case 'recovery':
      return ProofKind.recovery;
    case 'document':
      return ProofKind.document;
    case 'call':
    default:
      return ProofKind.call;
  }
}
