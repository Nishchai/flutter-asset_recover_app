/// OAuth2 client-credentials token response (Azure-AD style), returned by the
/// token endpoint hit in [TicketRepository.generateAuthToken]. Mirrors the Java
/// `LiveTokenModel`: the body is `application/x-www-form-urlencoded` on the way
/// out and JSON on the way back.
class LiveTokenModel {
  const LiveTokenModel({
    required this.accessToken,
    this.tokenType = 'Bearer',
    this.expiresIn,
    this.resource,
    this.scope,
    this.refreshToken,
  });

  /// The bearer token to attach as `Authorization: Bearer <accessToken>`.
  final String accessToken;

  /// Usually `Bearer`.
  final String tokenType;

  /// Lifetime in seconds from issuance, when the provider reports it.
  final int? expiresIn;

  /// The audience/resource the token was minted for (Azure AD `resource`).
  final String? resource;

  final String? scope;

  /// Present only if the provider issues one (client-credentials flows often
  /// don't).
  final String? refreshToken;

  factory LiveTokenModel.fromJson(Map<String, dynamic> json) => LiveTokenModel(
        // Providers vary on casing/naming; accept the common spellings.
        accessToken: (json['access_token'] ?? json['accessToken'] ?? '') as String,
        tokenType: (json['token_type'] ?? json['tokenType'] ?? 'Bearer') as String,
        // Azure AD returns expires_in as a STRING; be tolerant of both.
        expiresIn: _asInt(json['expires_in'] ?? json['expiresIn']),
        resource: json['resource'] as String?,
        scope: json['scope'] as String?,
        refreshToken: (json['refresh_token'] ?? json['refreshToken']) as String?,
      );

  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  bool get isValid => accessToken.isNotEmpty;
}
