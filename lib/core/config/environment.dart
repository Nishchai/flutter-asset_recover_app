/// Environment-specific configuration (dev / test / prod).
///
/// Loaded from `assets/config/environments/<env>.json`. Holds the API base URL,
/// mock-data toggle, maps key and other deployment-specific values. Nothing in
/// the UI references these directly — everything flows through [ConfigService].
class EnvironmentConfig {
  const EnvironmentConfig({
    required this.environment,
    required this.label,
    required this.useMockData,
    required this.apiBaseUrl,
    required this.apiTimeoutSeconds,
    required this.mapsApiKey,
    required this.callRecordingProvider,
    required this.enableNetworkLogging,
    required this.gupshup,
    required this.authToken,
    required this.blobStorage,
    this.deterministicSeed,
  });

  final String environment;
  final String label;
  final bool useMockData;
  final String apiBaseUrl;
  final int apiTimeoutSeconds;
  final String mapsApiKey;
  final String callRecordingProvider;
  final bool enableNetworkLogging;

  /// SMS Gupshup credentials + OTP settings for login OTP send/verify.
  final GupshupConfig gupshup;

  /// OAuth2 client-credentials for the backend access token, minted right after
  /// a successful login OTP (see [TicketRepository.generateAuthToken]).
  final AuthTokenConfig authToken;

  /// Azure Blob Storage credentials for uploading captured proof images.
  final BlobStorageConfig blobStorage;

  /// When set (test env only) the mock backend seeds with a fixed RNG so
  /// widget/integration tests are reproducible.
  final int? deterministicSeed;

  factory EnvironmentConfig.fromJson(Map<String, dynamic> json) {
    return EnvironmentConfig(
      environment: json['environment'] as String? ?? 'dev',
      label: json['label'] as String? ?? 'Development',
      useMockData: json['useMockData'] as bool? ?? true,
      apiBaseUrl: json['apiBaseUrl'] as String? ?? '',
      apiTimeoutSeconds: (json['apiTimeoutSeconds'] as num?)?.toInt() ?? 30,
      mapsApiKey: json['mapsApiKey'] as String? ?? '',
      callRecordingProvider: json['callRecordingProvider'] as String? ?? 'none',
      enableNetworkLogging: json['enableNetworkLogging'] as bool? ?? true,
      gupshup: GupshupConfig.fromJson(
        (json['gupshup'] as Map<String, dynamic>?) ?? const {},
      ),
      authToken: AuthTokenConfig.fromJson(
        (json['authToken'] as Map<String, dynamic>?) ?? const {},
      ),
      blobStorage: BlobStorageConfig.fromJson(
        (json['blobStorage'] as Map<String, dynamic>?) ?? const {},
      ),
      deterministicSeed: (json['deterministicSeed'] as num?)?.toInt(),
    );
  }
}

/// SMS Gupshup Enterprise gateway configuration.
///
/// Mirrors the credentials the legacy Java Rider App kept in `BuildConfig`
/// (`gupshup_username` / `gupshup_password`) plus the TWO_FACTOR_AUTH OTP
/// parameters. Consumed by the Gupshup OTP data source — nothing else in the
/// app touches these. Secrets belong ONLY in the git-ignored `prod.json`, never
/// in `prod.sample.json`.
class GupshupConfig {
  const GupshupConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.encryptionKey,
    required this.otpMessageTemplate,
    required this.otpCodeLength,
    required this.otpCodeType,
    required this.useEncryptedData,
  });

  /// Gateway REST endpoint (same for send + verify; the `method`/`event` params
  /// differentiate them).
  final String baseUrl;
  final String username;
  final String password;

  /// Base64 (URL-safe) AES key for the `encrdata` payload — the legacy Java's
  /// `BuildConfig.RSA_ENCRYPTION_KEY`. Required only when [useEncryptedData].
  final String encryptionKey;

  /// SMS body sent to the user. MUST contain the literal `%code%` token, which
  /// Gupshup substitutes with the generated OTP.
  final String otpMessageTemplate;

  /// Digits in the generated OTP (Java used 4).
  final int otpCodeLength;

  /// `NUMERIC` / `ALPHANUMERIC` — Gupshup `otpCodeType`.
  final String otpCodeType;

  /// When true the sensitive query string is AES-encrypted and sent as
  /// `encrdata` (as the Java did). When false all params are sent in plaintext
  /// (the standard, equivalent gateway variant). See GupshupOtpDataSource.
  final bool useEncryptedData;

  factory GupshupConfig.fromJson(Map<String, dynamic> json) => GupshupConfig(
        baseUrl: json['baseUrl'] as String? ??
            'https://enterprise.smsgupshup.com/GatewayAPI/rest',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        encryptionKey: json['encryptionKey'] as String? ?? '',
        otpMessageTemplate: json['otpMessageTemplate'] as String? ??
            'The OTP token for your ISEPL Application access request for '
                'Rider App is %code%',
        otpCodeLength: (json['otpCodeLength'] as num?)?.toInt() ?? 4,
        otpCodeType: json['otpCodeType'] as String? ?? 'NUMERIC',
        useEncryptedData: json['useEncryptedData'] as bool? ?? true,
      );
}

/// OAuth2 client-credentials configuration for the backend access token
/// (`TicketRepository.generateAuthToken`).
///
/// Mirrors the legacy Java `BuildConfig` constants `AUTH_URL` / `CLIENT_ID`.
/// Loaded from the env JSON `authToken` block. The [clientSecret] is a secret
/// and belongs ONLY in the git-ignored `prod.json`, never in `prod.sample.json`.
class AuthTokenConfig {
  const AuthTokenConfig({
    required this.url,
    required this.clientId,
    required this.resource,
    required this.clientSecret,
    required this.grantType,
  });

  /// Absolute OAuth2 token endpoint (e.g. Azure AD `.../oauth2/token`). Hit as a
  /// form POST; NOT resolved against `apiBaseUrl`.
  final String url;

  /// Application (client) id.
  final String clientId;

  /// The API the token is minted for (Azure AD `resource`).
  final String resource;

  /// Client secret — keep it only in the git-ignored `prod.json`.
  final String clientSecret;

  /// OAuth2 grant type; `client_credentials` for machine-to-machine auth.
  final String grantType;

  /// True once real credentials are present (empty in mock/test envs).
  bool get isConfigured => url.isNotEmpty && clientId.isNotEmpty;

  factory AuthTokenConfig.fromJson(Map<String, dynamic> json) => AuthTokenConfig(
        url: json['url'] as String? ?? '',
        clientId: json['clientId'] as String? ?? '',
        resource: json['resource'] as String? ?? '',
        clientSecret: json['clientSecret'] as String? ?? '',
        grantType: json['grantType'] as String? ?? 'client_credentials',
      );
}

/// Azure Blob Storage configuration for uploading captured proof images
/// (see `BlobUploadService`).
///
/// The [connectionString] embeds the storage account key, so it is a SECRET:
/// keep the real value ONLY in the git-ignored `prod.json`, never in
/// `prod.sample.json`. Longer term this should be replaced by a backend-issued
/// short-lived SAS so the account key never ships in the client.
class BlobStorageConfig {
  const BlobStorageConfig({
    required this.connectionString,
    required this.containerName,
  });

  /// Full account connection string, e.g.
  /// `DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;EndpointSuffix=core.windows.net`.
  final String connectionString;

  /// Target blob container the proof images are written to (e.g.
  /// `asset-recovery`).
  final String containerName;

  /// True once both a connection string and a container are present. When
  /// false, uploads are skipped (mock/test envs, or before the key is filled).
  bool get isConfigured =>
      connectionString.isNotEmpty && containerName.isNotEmpty;

  factory BlobStorageConfig.fromJson(Map<String, dynamic> json) =>
      BlobStorageConfig(
        connectionString: json['connectionString'] as String? ?? '',
        containerName: json['containerName'] as String? ?? '',
      );
}
