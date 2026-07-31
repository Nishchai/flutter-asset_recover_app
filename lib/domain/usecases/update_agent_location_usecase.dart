import '../../core/error/result.dart';
import '../entities/geo_point.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class UpdateAgentLocationParams {
  const UpdateAgentLocationParams(this.agentId, this.position);
  final String agentId;
  final GeoPoint position;
}

/// Reports where the agent's device currently is (`agent.location`). Fired
/// every time the agent lands on the home screen.
/// Returns `true` on success (avoids a `void` result payload).
class UpdateAgentLocationUseCase
    implements UseCase<bool, UpdateAgentLocationParams> {
  UpdateAgentLocationUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(UpdateAgentLocationParams params) =>
      Result.guard(() async {
        await _repo.updateAgentLocation(params.agentId, params.position);
        return true;
      });
}
