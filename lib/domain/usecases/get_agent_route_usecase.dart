import '../../core/error/result.dart';
import '../entities/agent_route.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Fetches the agent's server-planned route (`agent.route` —
/// `GET /agents/{agentId}/route`) by [params] = `agentId`. Drives the Map tab:
/// its stops are plotted in the backend's own sequence and joined into a single
/// drive from the agent's current position.
class GetAgentRouteUseCase implements UseCase<AgentRoute, String> {
  GetAgentRouteUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<AgentRoute>> call(String agentId) =>
      Result.guard(() => _repo.agentRoute(agentId));
}
