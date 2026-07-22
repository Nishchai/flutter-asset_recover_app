import '../../core/error/result.dart';
import '../entities/ticket.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Loads the tickets assigned to an agent (already cluster-scoped).
class GetAssignedTicketsUseCase implements UseCase<List<Ticket>, String> {
  GetAssignedTicketsUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<List<Ticket>>> call(String agentId) =>
      Result.guard(() => _repo.assignedTickets(agentId));
}
