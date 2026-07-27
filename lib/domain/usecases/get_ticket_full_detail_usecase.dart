import '../../core/error/result.dart';
import '../entities/ticket_detail.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Fetches the full, nested ticket detail (`GET /tickets/{UUID}`) by the backend
/// resource UUID ([params] = `Ticket.caseId`). Used on the BP detail screen to
/// enrich the card with the customer's last-seen geo, last-swap date and
/// last-swap station.
class GetTicketFullDetailUseCase implements UseCase<TicketDetail, String> {
  GetTicketFullDetailUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<TicketDetail>> call(String uuid) =>
      Result.guard(() => _repo.ticketFullDetail(uuid));
}
