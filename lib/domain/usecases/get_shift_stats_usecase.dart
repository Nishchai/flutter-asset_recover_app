import '../../core/error/result.dart';
import '../entities/shift_stats.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Loads the aggregate shift counters for the home header.
class GetShiftStatsUseCase implements UseCase<ShiftStats, String> {
  GetShiftStatsUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<ShiftStats>> call(String agentId) => Result.guard(() async {
        final map = await _repo.shiftStats(agentId);
        return ShiftStats.fromMap(map);
      });
}
