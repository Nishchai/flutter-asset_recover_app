import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/entities/draft_attempt.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';
import 'package:asset_recovery_app/domain/usecases/usecase.dart';

/// Loads any partially-completed attempt data for a BP (item 13 — free-choice
/// actions persist across app sessions until the Outcome action is submitted).
class GetDraftUseCase implements UseCase<DraftAttempt?, String> {
  GetDraftUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<DraftAttempt?>> call(String bpId) =>
      Result.guard(() => _repo.getDraft(bpId));
}

class SaveDraftParams {
  const SaveDraftParams(this.bpId, this.draft);
  final String bpId;
  final DraftAttempt draft;
}

class SaveDraftUseCase implements UseCase<bool, SaveDraftParams> {
  SaveDraftUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(SaveDraftParams params) => Result.guard(() async {
        await _repo.saveDraft(params.bpId, params.draft);
        return true;
      });
}
