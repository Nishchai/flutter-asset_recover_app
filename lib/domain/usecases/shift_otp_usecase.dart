import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class RequestShiftEndOtpParams {
  const RequestShiftEndOtpParams(this.mobile, {required this.codeLength});

  /// The agent's registered mobile — `usermobileNumber` from the `commonLogin`
  /// data block held in the persisted session.
  final String mobile;

  /// Digits the gateway must generate, matched to the end-shift sheet's input.
  final int codeLength;
}

/// Sends the end-of-shift OTP to the signed-in agent's registered mobile
/// (Figma "Daily logout flow"). Returns `true` once the gateway accepts it.
///
/// A session with no mobile number fails here rather than silently sending
/// nothing — the agent would otherwise sit in front of a sheet waiting for an
/// SMS that was never requested.
class RequestShiftEndOtpUseCase
    implements UseCase<bool, RequestShiftEndOtpParams> {
  RequestShiftEndOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(RequestShiftEndOtpParams params) => Result.guard(
        () async {
          final mobile = params.mobile.trim();
          if (mobile.isEmpty) {
            throw StateError(
              'No registered mobile number on this session. Sign in again to '
              'end your shift.',
            );
          }
          await _repo.requestShiftEndOtp(mobile, codeLength: params.codeLength);
          return true;
        },
        onError: failureFrom,
      );
}

class VerifyShiftEndOtpParams {
  const VerifyShiftEndOtpParams(this.mobile, this.otp);
  final String mobile;
  final String otp;
}

/// Verifies the end-of-shift OTP. `Ok(false)` is a wrong or expired code — a
/// normal negative result, not a failure; `Err` means the gateway itself could
/// not be reached, and its message is shown to the agent.
class VerifyShiftEndOtpUseCase
    implements UseCase<bool, VerifyShiftEndOtpParams> {
  VerifyShiftEndOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(VerifyShiftEndOtpParams params) => Result.guard(
        () => _repo.verifyShiftEndOtp(params.mobile.trim(), params.otp.trim()),
        onError: failureFrom,
      );
}
