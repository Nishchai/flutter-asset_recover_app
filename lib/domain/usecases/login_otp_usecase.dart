import '../../core/error/result.dart';
import '../entities/agent.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Validates the mobile number server-side and triggers an OTP send —
/// replaces the old agent-id/password login step.
class RequestLoginOtpUseCase implements UseCase<bool, String> {
  RequestLoginOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(String mobile) => Result.guard(() async {
        await _repo.requestLoginOtp(mobile);
        return true;
      });
}

class VerifyLoginOtpParams {
  const VerifyLoginOtpParams(this.mobile, this.otp);
  final String mobile;
  final String otp;
}

/// Verifies the login OTP and returns the authenticated [Agent].
class VerifyLoginOtpUseCase implements UseCase<Agent, VerifyLoginOtpParams> {
  VerifyLoginOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<Agent>> call(VerifyLoginOtpParams params) =>
      Result.guard(() => _repo.verifyLoginOtp(params.mobile, params.otp));
}
