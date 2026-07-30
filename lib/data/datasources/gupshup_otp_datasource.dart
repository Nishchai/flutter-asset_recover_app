import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/config/environment.dart';
import 'package:asset_recovery_app/core/services/api_client.dart' show ApiException;
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

/// GCM IV length in bytes (Java `GCM_IV_LENGTH`).
const _gcmIvLength = 12;

/// GCM auth-tag length in bytes (Java `GCM_TAG_LENGTH`); 128-bit tag.
const _gcmTagLength = 16;

/// Remote data source for the SMS Gupshup Enterprise "TWO_FACTOR_AUTH" OTP
/// service. Called DIRECTLY from the client (no intermediary backend), porting
/// the legacy Java Rider App's `generateOTP()` / `verifyOtp()`. Gupshup itself
/// both sends and validates the code, so it never returns an app session/agent
/// (see [ApiTicketRepository.verifyLoginOtp] for how the agent is resolved
/// after a successful verify).
///
/// Both calls share [GupshupConfig.baseUrl]; the sensitive query string is
/// AES/GCM encrypted into a single `encrdata` param (`useEncryptedData: true`,
/// the production path) or sent in plaintext. The gateway replies as
/// pipe-delimited text, e.g. `success | 91XXXXXXXXXX | 12345` or
/// `error | 102 | Wrong userid/password`.
class GupshupOtpDataSource {
  GupshupOtpDataSource(this._config, {http.Client? client, Random? random})
      : _client = client ?? http.Client(),
        _random = random ?? Random.secure();

  final ConfigService _config;
  final http.Client _client;
  final Random _random;

  GupshupConfig get _cfg => _config.env.gupshup;

  /// Sends an OTP to [mobile]. Throws [ApiException] if the gateway
  /// rejects the request (bad credentials, throttling, invalid number, …).
  ///
  /// [codeLength] overrides how many digits the gateway generates; it defaults
  /// to [GupshupConfig.otpCodeLength] (the login flow's length). Callers whose
  /// UI asks for a different number of digits MUST pass it, or the code that
  /// arrives by SMS can never fill their input.
  ///
  /// Mirrors the Java `generateOTP()` param string exactly (order matters — the
  /// encrypted blob must decrypt to the same string the gateway expects).
  Future<void> sendOtp(String mobile, {int? codeLength}) async {
    final uri = _buildUri({
      'password': _cfg.password,
      'method': 'TWO_FACTOR_AUTH',
      'v': '1.1',
      'phone_no': mobile,
      'msg': _cfg.otpMessageTemplate, // must contain the literal %code%
      'format': 'text',
      'otpCodeLength': '${codeLength ?? _cfg.otpCodeLength}',
      'otpCodeType': _cfg.otpCodeType,
    });
    await _get(uri, isSend: true);
  }

  /// Verifies [otp] against the code Gupshup sent to [mobile]. Returns true on
  /// a match, false on mismatch/expiry. Throws [ApiException] only for gateway
  /// errors unrelated to the code itself.
  ///
  /// Mirrors the Java `verifyOtp()` — note it sends no `format` param.
  Future<bool> verifyOtp(String mobile, String otp) async {
    final uri = _buildUri({
      'password': _cfg.password,
      'method': 'TWO_FACTOR_AUTH',
      'v': '1.1',
      'phone_no': mobile,
      'otp_code': otp,
    });
    final body = await _get(uri, isSend: false);
    // Java `verifyOtpResponse`: split on '|', a leading `success` token means
    // the code matched. A wrong/expired code returns `error | .. | ..` — that's
    // a normal negative result, not an exception.
    return _isSuccess(body);
  }

  // --- Request building -------------------------------------------------------

  /// Assembles the gateway URI. `userid` is always sent in the clear (as in the
  /// Java). When [GupshupConfig.useEncryptedData] the remaining [params]
  /// (including `password`) are AES/GCM-encrypted into a single `encrdata`
  /// value; otherwise they are appended as plaintext query params.
  Uri _buildUri(Map<String, String> params) {
    if (!_cfg.useEncryptedData) {
      return Uri.parse(_cfg.baseUrl).replace(queryParameters: {
        'userid': _cfg.username,
        ...params,
      },);
    }

    // Encrypted variant — the Java builds `&k=urlEncode(v)&…` (leading `&`,
    // values URL-encoded) BEFORE encrypting, then appends `?userid=..&encrdata=`.
    final raw = params.entries
        .map((e) => '&${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join();
    final encrdata = _encrypt(raw);
    return Uri.parse(
      '${_cfg.baseUrl}?userid=${Uri.encodeQueryComponent(_cfg.username)}'
      '&encrdata=$encrdata',
    );
  }

  /// AES/GCM-encrypts [plaintext] and Base64-URL encodes `IV || ciphertext ||
  /// tag`, exactly as the legacy Java `encrypt(String)`:
  ///  * key   — Base64-URL-decoded [GupshupConfig.encryptionKey]
  ///  * IV    — 12 random bytes, prepended to the output
  ///  * cipher— AES/GCM/NoPadding, 128-bit tag (appended to the ciphertext)
  String _encrypt(String plaintext) {
    final key = _decodeBase64Url(_cfg.encryptionKey);
    if (key.isEmpty) {
      throw ApiException(
        'Gupshup encryptionKey is empty but useEncryptedData is true — set '
        'gupshup.encryptionKey in the environment config (or disable it).',
      );
    }

    final iv = Uint8List.fromList(
      List<int>.generate(_gcmIvLength, (_) => _random.nextInt(256)),
    );
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          _gcmTagLength * 8,
          iv,
          Uint8List(0),
        ),
      );
    // pointycastle appends the GCM tag to the ciphertext, matching Java's
    // Cipher output (cipherText = actualCipher || tag).
    final cipherText = cipher.process(Uint8List.fromList(utf8.encode(plaintext)));

    final out = Uint8List(iv.length + cipherText.length)
      ..setRange(0, iv.length, iv)
      ..setRange(iv.length, iv.length + cipherText.length, cipherText);
    return base64Url.encode(out);
  }

  /// Tolerant Base64-URL decode (accepts standard `+`/`/`, missing padding) so
  /// the configured key decodes regardless of which Base64 flavour it was
  /// generated with. Mirrors Android `Base64.decode(.., URL_SAFE)` leniency.
  Uint8List _decodeBase64Url(String value) {
    if (value.isEmpty) return Uint8List(0);
    var s = value.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    final mod = s.length % 4;
    if (mod != 0) s += '=' * (4 - mod);
    return base64Url.decode(s);
  }

  // --- Transport + response parsing ------------------------------------------

  Future<String> _get(Uri uri, {required bool isSend}) async {
    final label = isSend ? 'gupshup.sendOtp' : 'gupshup.verifyOtp';
    if (_config.env.enableNetworkLogging) {
      // Redact credentials so tokens never leak into logs.
      developer.log('GET ${_redact(uri)}', name: 'GupshupOtp');
    }
    final timeout = Duration(seconds: _config.env.apiTimeoutSeconds);
    final res = await _client.get(uri).timeout(timeout);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        'HTTP ${res.statusCode} on $label',
        statusCode: res.statusCode,
        body: res.body,
      );
    }
    final body = res.body.trim();
    // A transport-level 200 can still carry a gateway `error | ...` payload;
    // for a send that's a hard failure. (Verify treats `error` as "no match".)
    if (isSend && !_isSuccess(body)) {
      throw ApiException('Gupshup rejected OTP send: $body', body: body);
    }
    return body;
  }

  /// True when the pipe-delimited text response's leading token is `success`
  /// (Java compares `temp[0].trim().equals("success")`).
  bool _isSuccess(String body) =>
      body.split('|').first.trim().toLowerCase() == 'success';

  String _redact(Uri uri) {
    final q = Map<String, String>.from(uri.queryParameters);
    for (final k in ['password', 'encrdata']) {
      if (q.containsKey(k)) q[k] = '***';
    }
    return uri.replace(queryParameters: q).toString();
  }

  void dispose() => _client.close();
}
