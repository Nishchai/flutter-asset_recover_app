import '../../core/error/result.dart';
import '../entities/attempt.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class SubmitAttemptParams {
  const SubmitAttemptParams({
    required this.ticketId,
    required this.bpId,
    required this.attempt,
  });
  final String ticketId;
  final String bpId;
  final Attempt attempt;
}

/// Persists a completed recovery attempt and returns the stored record.
class SubmitAttemptUseCase implements UseCase<Attempt, SubmitAttemptParams> {
  SubmitAttemptUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<Attempt>> call(SubmitAttemptParams params) => Result.guard(
        () => _repo.submitAttempt(params.ticketId, params.bpId, params.attempt),
      );
}
