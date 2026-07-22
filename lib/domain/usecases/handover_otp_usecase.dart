import '../../core/error/result.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Requests a store/ESV handover OTP for a physical recovery (PRD §5.1.6).
/// Returns `true` once the request is accepted.
class RequestHandoverOtpUseCase implements UseCase<bool, String> {
  RequestHandoverOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(String bpId) => Result.guard(() async {
        await _repo.requestHandoverOtp(bpId);
        return true;
      });
}

class VerifyHandoverOtpParams {
  const VerifyHandoverOtpParams(this.bpId, this.otp);
  final String bpId;
  final String otp;
}

/// Verifies the store/ESV handover OTP.
class VerifyHandoverOtpUseCase implements UseCase<bool, VerifyHandoverOtpParams> {
  VerifyHandoverOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(VerifyHandoverOtpParams params) =>
      Result.guard(() => _repo.verifyHandoverOtp(params.bpId, params.otp));
}
