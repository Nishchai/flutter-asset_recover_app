import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/api_client.dart' show ApiException;
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';

/// 16-byte AES key used for the encrypted-path round-trip assertions.
final _keyBytes = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));
final _keyB64 = base64Url.encode(_keyBytes);

/// Builds a [ConfigService] whose active environment carries a known Gupshup
/// config. Every other config asset is stubbed with `{}` — ConfigService just
/// stores those as maps.
Future<ConfigService> _config({required bool encrypted}) {
  final env = {
    'environment': 'gtest',
    'label': 'Gupshup Test',
    'useMockData': false,
    'apiBaseUrl': 'https://example.test/api',
    'apiTimeoutSeconds': 5,
    'mapsApiKey': '',
    'callRecordingProvider': 'none',
    'enableNetworkLogging': false,
    'gupshup': {
      'baseUrl': 'https://enterprise.smsgupshup.com/GatewayAPI/rest',
      'username': 'sunmobility',
      'password': 'p@ss word/1',
      'encryptionKey': _keyB64,
      'otpMessageTemplate': 'Your OTP is %code%',
      'otpCodeLength': 4,
      'otpCodeType': 'NUMERIC',
      'useEncryptedData': encrypted,
    },
  };
  return ConfigService.load(
    environment: 'gtest',
    reader: (path) async =>
        path.contains('environments/') ? jsonEncode(env) : '{}',
  );
}

/// Decrypts an `encrdata` value the way the Gupshup gateway would, to assert
/// the produced ciphertext decrypts back to the exact plaintext query string.
String _decrypt(String encrdata) {
  var s = encrdata.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  final mod = s.length % 4;
  if (mod != 0) s += '=' * (4 - mod);
  final all = base64Url.decode(s);
  final iv = all.sublist(0, 12);
  final ct = all.sublist(12);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(KeyParameter(_keyBytes), 128, iv, Uint8List(0)));
  return utf8.decode(cipher.process(Uint8List.fromList(ct)));
}

void main() {
  group('GupshupOtpDataSource (encrypted / encrdata path)', () {
    test('sendOtp encrypts the exact Java-format query string', () async {
      final cfg = await _config(encrypted: true);
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('success | 919999999999 | 12345', 200);
      });
      final ds = GupshupOtpDataSource(cfg, client: client, random: Random(1));

      await ds.sendOtp('919999999999');

      // userid is plaintext; the rest lives in encrdata.
      expect(captured.queryParameters['userid'], 'sunmobility');
      expect(captured.queryParameters.containsKey('encrdata'), isTrue);
      expect(captured.queryParameters.containsKey('password'), isFalse);

      final plain = _decrypt(captured.queryParameters['encrdata']!);
      String e(String s) => Uri.encodeQueryComponent(s);
      expect(
        plain,
        '&password=${e('p@ss word/1')}'
        '&method=TWO_FACTOR_AUTH&v=1.1'
        '&phone_no=919999999999'
        '&msg=${e('Your OTP is %code%')}'
        '&format=text&otpCodeLength=4&otpCodeType=NUMERIC',
      );
      // The message token survives the round-trip intact.
      expect(plain.contains(e('%code%')), isTrue);
    });

    test('verifyOtp sends otp_code + no format, and reads the success token',
        () async {
      final cfg = await _config(encrypted: true);
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('success | 919999999999 | OTP Matched', 200);
      });
      final ds = GupshupOtpDataSource(cfg, client: client, random: Random(2));

      final ok = await ds.verifyOtp('919999999999', '4321');
      expect(ok, isTrue);

      final plain = _decrypt(captured.queryParameters['encrdata']!);
      expect(plain.contains('&otp_code=4321'), isTrue);
      expect(plain.contains('format='), isFalse); // verify omits format
    });

    test('verifyOtp returns false on a gateway error/mismatch response',
        () async {
      final cfg = await _config(encrypted: true);
      final client = MockClient(
        (_) async => http.Response('error | 305 | OTP Mismatch', 200),
      );
      final ds = GupshupOtpDataSource(cfg, client: client, random: Random(3));

      expect(await ds.verifyOtp('919999999999', '0000'), isFalse);
    });

    test('sendOtp throws when the gateway rejects the request', () async {
      final cfg = await _config(encrypted: true);
      final client = MockClient(
        (_) async => http.Response('error | 102 | Wrong userid/password', 200),
      );
      final ds = GupshupOtpDataSource(cfg, client: client, random: Random(4));

      expect(() => ds.sendOtp('919999999999'), throwsA(isA<ApiException>()));
    });
  });

  group('GupshupOtpDataSource (plaintext path)', () {
    test('sends all params in the clear when useEncryptedData is false',
        () async {
      final cfg = await _config(encrypted: false);
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response('success | 91 | 1', 200);
      });
      final ds = GupshupOtpDataSource(cfg, client: client);

      await ds.sendOtp('919999999999');

      expect(captured.queryParameters['userid'], 'sunmobility');
      expect(captured.queryParameters['password'], 'p@ss word/1');
      expect(captured.queryParameters['method'], 'TWO_FACTOR_AUTH');
      expect(captured.queryParameters['phone_no'], '919999999999');
      expect(captured.queryParameters['otpCodeLength'], '4');
      expect(captured.queryParameters.containsKey('encrdata'), isFalse);
    });
  });
}
