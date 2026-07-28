import '../../core/config/environment.dart';
import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../entities/agent.dart';
import '../entities/partner_login_data.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Step 1 of sign-in. Looks the mobile number up in the SM-Partners directory
/// (`commonLogin`) and sends the OTP ONLY if it is found — an unknown or
/// deactivated number never costs an SMS.
///
/// Returns the agent record the directory holds for that number; the caller
/// carries it into [VerifyLoginOtpUseCase] and, from there, into encrypted
/// storage as the signed-in identity. Failures keep the backend's own `reason`
/// text so the login screen can say why the number was rejected.
class RequestLoginOtpUseCase implements UseCase<PartnerLoginData, String> {
  RequestLoginOtpUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<PartnerLoginData>> call(String mobile) => Result.guard(
        () async {
          // 1) Is this a real partner user? Throws with the server's reason if not.
          final profile = await _repo.commonLogin(mobile);
          if (profile.isActive == false) {
            throw StateError(
                'This account is deactivated. Contact your coordinator.',);
          }
          // 2) Only now spend an SMS.
          await _repo.requestLoginOtp(mobile);
          return profile;
        },
        onError: failureFrom,
      );
}

class VerifyLoginOtpParams {
  const VerifyLoginOtpParams(this.mobile, this.otp, {this.profile});
  final String mobile;
  final String otp;

  /// The record [RequestLoginOtpUseCase] returned for [mobile]. Present for
  /// every real login — it is the agent data that gets persisted.
  final PartnerLoginData? profile;
}

/// A completed login: the authenticated [agent], the access token minted for
/// them, and the full partner [profile] they were resolved from. Returned
/// together so the caller can hand all of it to the `SessionStore` without
/// reaching into [ApiClient] for the token.
class AuthenticatedSession {
  const AuthenticatedSession({
    required this.agent,
    required this.accessToken,
    this.profile,
  });

  final Agent agent;
  final String accessToken;
  final PartnerLoginData? profile;
}

/// Step 2 of sign-in: verifies the login OTP and, on success, immediately mints
/// the backend access token before returning the [AuthenticatedSession].
///
/// The two steps are one atomic login: no other API call may run until the
/// token exists, so the token generation is awaited here rather than left to the
/// caller. If minting fails the whole login fails (an agent with no API token
/// can do nothing). Once minted, [ApiClient] attaches it as `Bearer` on every
/// request; a later 401 re-mints automatically (see ApiClient.onUnauthorized).
///
/// The session's [Agent] is projected from the `commonLogin` profile — the real
/// agent record — and falls back to whatever OTP verification could tell us only
/// when step 1 supplied no profile.
class VerifyLoginOtpUseCase
    implements UseCase<AuthenticatedSession, VerifyLoginOtpParams> {
  VerifyLoginOtpUseCase(this._repo, this._auth);
  final TicketRepository _repo;
  final AuthTokenConfig _auth;

  @override
  Future<Result<AuthenticatedSession>> call(VerifyLoginOtpParams params) =>
      Result.guard(
        () async {
          // 1) Verify the OTP (Gupshup). Only a success proceeds to step 2.
          final verified = await _repo.verifyLoginOtp(params.mobile, params.otp);
          // 2) Mint the OAuth2 client-credentials token now, before any other API.
          final token = await _repo.generateAuthToken(
            url: _auth.url,
            clientId: _auth.clientId,
            resource: _auth.resource,
            clientSecret: _auth.clientSecret,
            grantType: _auth.grantType,
          );
          return AuthenticatedSession(
            // Identity from the partner directory; cluster/zone/counters from
            // whatever the recovery backend could tell us.
            agent: params.profile?.toAgent(base: verified) ?? verified,
            accessToken: token.accessToken,
            profile: params.profile,
          );
        },
        onError: failureFrom,
      );
}
