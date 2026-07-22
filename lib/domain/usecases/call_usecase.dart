import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/entities/call_recording.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';
import 'package:asset_recovery_app/domain/usecases/usecase.dart';

class StartCallParams {
  const StartCallParams(this.bpId, this.phoneNumber);
  final String bpId;
  final String phoneNumber;
}

/// Starts an in-app call via the configured telephony provider (Ozonetel —
/// Rule 8a).
class StartCallUseCase implements UseCase<CallRecording, StartCallParams> {
  StartCallUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<CallRecording>> call(StartCallParams params) =>
      Result.guard(() => _repo.startCall(params.bpId, params.phoneNumber));
}

class GetCallRecordingsUseCase implements UseCase<List<CallRecording>, String> {
  GetCallRecordingsUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<List<CallRecording>>> call(String bpId) =>
      Result.guard(() => _repo.callRecordings(bpId));
}
