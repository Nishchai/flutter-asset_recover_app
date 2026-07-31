import '../../core/error/result.dart';
import '../entities/ticket_page.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Which agent, and which window of their list, to fetch.
class AssignedTicketsParams {
  const AssignedTicketsParams(
    this.agentId, {
    this.page = 1,
    this.pageSize = 20,
  });

  final String agentId;

  /// 1-based page index.
  final int page;
  final int pageSize;
}

/// Loads one page of the tickets assigned to an agent (already cluster-scoped).
class GetAssignedTicketsUseCase
    implements UseCase<TicketPage, AssignedTicketsParams> {
  GetAssignedTicketsUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<TicketPage>> call(AssignedTicketsParams params) =>
      Result.guard(() => _repo.assignedTickets(
            params.agentId,
            page: params.page,
            pageSize: params.pageSize,
          ),);
}
