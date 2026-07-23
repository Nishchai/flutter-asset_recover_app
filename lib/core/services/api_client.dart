import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:http/http.dart' as http;

/// Bodies smaller than this aren't worth the gzip overhead (header bytes +
/// CPU) — most GET-driven reads and small POSTs stay uncompressed; the
/// payloads that actually matter here are attempt/draft submissions carrying
/// embedded proof images.
const _gzipThresholdBytes = 2 * 1024;

/// Every backend request is scoped to a staking agent. Hard-coded for now until
/// the value is sourced from the authenticated session / agent profile.
// TODO: replace with the real staking agent id once available from the session.
const _stakingAgentId = 'FA-RM-01';

/// Thin HTTP wrapper that resolves endpoint strings from `api_endpoints.json`
/// (format: `"METHOD /path/with/{param}"`) against the active environment's
/// base URL. Handles auth headers, timeouts and JSON decoding in one place.
class ApiClient {
  ApiClient(this._config, {http.Client? client})
      : _client = client ?? http.Client();

  final ConfigService _config;
  final http.Client _client;
  String? _authToken;

  set authToken(String? token) => _authToken = token;

  /// Calls the endpoint registered under [endpointPath] (dotted path into
  /// api_endpoints.json, e.g. `tickets.assigned`), filling `{param}` segments
  /// from [pathParams].
  Future<dynamic> call(
    String endpointPath, {
    Map<String, String> pathParams = const {},
    Map<String, String>? query,
    Object? body,
  }) async {
    final spec = _resolve(endpointPath);
    final method = spec.$1;
    var path = spec.$2;
    pathParams.forEach((k, v) => path = path.replaceAll('{$k}', v));

    // Attach the staking agent id to every request. Existing query params win
    // if a caller ever passes an explicit `stakingAgentId`.
    final mergedQuery = <String, String>{
      'stakingAgentId': _stakingAgentId,
      ...?query,
    };

    final uri = Uri.parse('${_config.env.apiBaseUrl}$path')
        .replace(queryParameters: mergedQuery);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
    };

    if (_config.env.enableNetworkLogging) {
      developer.log(
        'REQUEST $method $uri\n'
        '  base:     ${_config.env.apiBaseUrl}\n'
        '  endpoint: $endpointPath -> $path',
        name: 'ApiClient',
      );
    }

    final timeout = Duration(seconds: _config.env.apiTimeoutSeconds);
    final Object? encoded = _encodeBody(body, headers);

    late http.Response res;
    try {
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: headers).timeout(timeout);
        case 'POST':
          res = await _client.post(uri, headers: headers, body: encoded).timeout(timeout);
        case 'PUT':
          res = await _client.put(uri, headers: headers, body: encoded).timeout(timeout);
        case 'PATCH':
          res = await _client.patch(uri, headers: headers, body: encoded).timeout(timeout);
        case 'DELETE':
          res = await _client.delete(uri, headers: headers).timeout(timeout);
        default:
          throw ApiException('Unsupported method $method');
      }
    } catch (e, st) {
      // The request never produced a response (connection refused, cleartext
      // blocked, DNS failure, timeout, …). Surface it so failures are visible
      // in the terminal instead of silently swallowed by callers.
      if (_config.env.enableNetworkLogging) {
        developer.log(
          'FAILED $method $uri\n'
          '  base:     ${_config.env.apiBaseUrl}\n'
          '  endpoint: $endpointPath\n'
          '  error:    $e',
          name: 'ApiClient',
          error: e,
          stackTrace: st,
        );
      }
      rethrow;
    }

    if (_config.env.enableNetworkLogging) {
      developer.log(
        'RESPONSE $method $uri\n'
        '  base:     ${_config.env.apiBaseUrl}\n'
        '  endpoint: $endpointPath\n'
        '  status:   ${res.statusCode}\n'
        '  body:     ${res.body}',
        name: 'ApiClient',
      );
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
    throw ApiException(
      'HTTP ${res.statusCode} on $endpointPath',
      statusCode: res.statusCode,
      body: res.body,
    );
  }

  /// `application/x-www-form-urlencoded` POST to an ABSOLUTE [url], returning
  /// the decoded JSON body.
  ///
  /// Unlike [call], this bypasses endpoint resolution: no `apiBaseUrl` prefix
  /// and no `stakingAgentId` query param — token endpoints (e.g. an OAuth2
  /// identity provider) live on their own host and must not carry app-scoped
  /// params. Used by `TicketRepository.generateAuthToken`.
  Future<Map<String, dynamic>> postForm(
    String url,
    Map<String, String> fields,
  ) async {
    final uri = Uri.parse(url);
    final headers = <String, String>{
      'Content-Type': 'application/x-www-form-urlencoded',
    };

    if (_config.env.enableNetworkLogging) {
      // Never log secrets: mask credential-bearing fields.
      final safe = {
        for (final e in fields.entries)
          e.key: _isSecretField(e.key) ? '***' : e.value,
      };
      developer.log('REQUEST POST(form) $uri\n  fields: $safe', name: 'ApiClient');
    }

    final timeout = Duration(seconds: _config.env.apiTimeoutSeconds);
    late http.Response res;
    try {
      // Passing a Map<String,String> as `body` makes package:http form-encode it.
      res = await _client.post(uri, headers: headers, body: fields).timeout(timeout);
    } catch (e, st) {
      if (_config.env.enableNetworkLogging) {
        developer.log('FAILED POST(form) $uri\n  error: $e',
            name: 'ApiClient', error: e, stackTrace: st,);
      }
      rethrow;
    }

    if (_config.env.enableNetworkLogging) {
      developer.log('RESPONSE POST(form) $uri\n  status: ${res.statusCode}',
          name: 'ApiClient',);
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiException('Expected a JSON object from $url', body: res.body);
    }
    throw ApiException(
      'HTTP ${res.statusCode} on token request',
      statusCode: res.statusCode,
      body: res.body,
    );
  }

  static bool _isSecretField(String key) {
    final k = key.toLowerCase();
    return k.contains('secret') || k.contains('password') || k.contains('token');
  }

  /// JSON-encodes [body] and gzips it (mutating [headers] to declare
  /// `Content-Encoding: gzip`) when it's worth the overhead — the API's
  /// request-decompression middleware handles the other end transparently.
  Object? _encodeBody(Object? body, Map<String, String> headers) {
    if (body == null) return null;
    final jsonBytes = utf8.encode(jsonEncode(body));
    if (jsonBytes.length < _gzipThresholdBytes) return jsonBytes;
    headers['Content-Encoding'] = 'gzip';
    return gzip.encode(jsonBytes);
  }

  (String, String) _resolve(String endpointPath) {
    dynamic node = _config.endpoints;
    for (final key in endpointPath.split('.')) {
      node = (node as Map)[key];
      if (node == null) {
        throw ApiException('Endpoint "$endpointPath" not found in config');
      }
    }
    final parts = (node as String).split(' ');
    return (parts.first, parts.sublist(1).join(' '));
  }

  void dispose() => _client.close();
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.body});
  final String message;
  final int? statusCode;
  final String? body;
  @override
  String toString() => 'ApiException($message)';
}
