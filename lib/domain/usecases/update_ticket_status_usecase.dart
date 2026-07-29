import '../../core/error/result.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class UpdateTicketStatusParams {
  const UpdateTicketStatusParams(this.ticketId, this.status);

  /// The human ticket number shown as "Case ID" on the ticket detail screen
  /// (e.g. `TKT-2026-00026`) — what the endpoint's `ticketId` field expects.
  final String ticketId;

  /// Backend status vocabulary, sent verbatim (e.g. `inProgress`).
  final String status;
}

/// Pushes a ticket status transition to the backend (`tickets.status` —
/// `PATCH /tickets/status`). Called from either recovery CTA on the ticket
/// detail screen (Scan QR, Ticket Actions) — both mean the Field Agent has
/// started working the case, which moves it to `inProgress`.
class UpdateTicketStatusUseCase
    implements UseCase<void, UpdateTicketStatusParams> {
  UpdateTicketStatusUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<void>> call(UpdateTicketStatusParams params) =>
      Result.guard(() => _repo.updateTicketStatus(params.ticketId, params.status));
}
