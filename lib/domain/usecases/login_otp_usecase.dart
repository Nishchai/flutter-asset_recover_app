import '../../core/config/environment.dart';
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

/// Verifies the login OTP and, on success, immediately mints the backend access
/// token before returning the authenticated [Agent].
///
/// The two steps are one atomic login: no other API call may run until the
/// token exists, so the token generation is awaited here rather than left to the
/// caller. If minting fails the whole login fails (an agent with no API token
/// can do nothing). Once minted, [ApiClient] attaches it as `Bearer` on every
/// request; a later 401 re-mints automatically (see ApiClient.onUnauthorized).
class VerifyLoginOtpUseCase implements UseCase<Agent, VerifyLoginOtpParams> {
  VerifyLoginOtpUseCase(this._repo, this._auth);
  final TicketRepository _repo;
  final AuthTokenConfig _auth;

  @override
  Future<Result<Agent>> call(VerifyLoginOtpParams params) =>
      Result.guard(() async {
        // 1) Verify the OTP (Gupshup). Only a success proceeds to step 2.
        final agent = await _repo.verifyLoginOtp(params.mobile, params.otp);
        // 2) Mint the OAuth2 client-credentials token now, before any other API.
        await _repo.generateAuthToken(
          url: _auth.url,
          clientId: _auth.clientId,
          resource: _auth.resource,
          clientSecret: _auth.clientSecret,
          grantType: _auth.grantType,
        );
        return agent;
      });
}
