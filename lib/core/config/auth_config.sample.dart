/// TEMPLATE — copy this file to `auth_config.dart` and fill in real values.
/// `auth_config.dart` is git-ignored so the [clientSecret] never enters source
/// control. This sample IS committed and must contain ONLY placeholders.
///
/// Static credentials for the OAuth2 client-credentials token request
/// (`TicketRepository.generateAuthToken`), mirroring the legacy Java
/// `BuildConfig` constants `AUTH_URL` / `CLIENT_ID`.
class AuthConfig {
  const AuthConfig._();

  /// Azure AD token endpoint.
  static const String authUrl =
      'https://login.microsoftonline.com/REPLACE_TENANT_ID/oauth2/token/';

  /// Application (client) id.
  static const String clientId = 'REPLACE_CLIENT_ID';

  /// The API the token is minted for (Azure AD `resource`).
  static const String resource = 'api://REPLACE_CLIENT_ID';

  /// Client secret — NEVER commit the real value; keep it only in the
  /// git-ignored auth_config.dart.
  static const String clientSecret = 'REPLACE_CLIENT_SECRET';
}
