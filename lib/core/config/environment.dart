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
      enableNetworkLogging: json['enableNetworkLogging'] as bool? ?? false,
      gupshup: GupshupConfig.fromJson(
        (json['gupshup'] as Map<String, dynamic>?) ?? const {},
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
