import '../../core/error/result.dart';
import '../entities/attempt_submission.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Submits a completed attempt record to the standalone attempts service
/// (`attempts.submit`). Called on Submit Attempt from the Update Status screen.
class SubmitAttemptRecordUseCase implements UseCase<void, AttemptSubmission> {
  SubmitAttemptRecordUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<void>> call(AttemptSubmission params) =>
      Result.guard(() => _repo.submitAttemptRecord(params));
}
