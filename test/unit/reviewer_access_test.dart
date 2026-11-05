import 'dart:convert';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/config/reviewer_access.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:asset_recovery_app/data/repositories/api_ticket_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<ConfigService> _config() {
  final env = {
    'environment': 'rtest',
    'label': 'Reviewer Test',
    'useMockData': false,
    'apiBaseUrl': 'https://example.test/api',
    'apiTimeoutSeconds': 5,
    'mapsApiKey': '',
    'callRecordingProvider': 'none',
    'enableNetworkLogging': false,
    'gupshup': {
      'baseUrl': 'https://enterprise.smsgupshup.com/GatewayAPI/rest',
      'username': 'user',
      'password': 'pw',
      'encryptionKey': '',
      'otpMessageTemplate': 'Your OTP is %code%',
      'otpCodeLength': 4,
      'otpCodeType': 'NUMERIC',
      'useEncryptedData': false,
    },
  };
  return ConfigService.load(
    environment: 'rtest',
    reader: (path) async =>
        path.contains('environments/') ? jsonEncode(env) : '{}',
  );
}

/// Gateway stub that counts calls and always rejects, so any test that reaches
/// Gupshup for a code it should not accept fails loudly.
({ApiTicketRepository repo, List<Uri> calls}) _repo(ConfigService cfg) {
  final calls = <Uri>[];
  final client = MockClient((req) async {
    calls.add(req.url);
    return http.Response('error | 107 | Invalid OTP', 200);
  });
  return (
    repo: ApiTicketRepository(
      ApiClient(cfg, client: client),
      GupshupOtpDataSource(cfg, client: client),
    ),
    calls: calls,
  );
}

void main() {
  late ConfigService cfg;
  setUp(() async => cfg = await _config());

  test('reviewer: no SMS is sent when the OTP is requested', () async {
    final t = _repo(cfg);
    await t.repo.requestLoginOtp(ReviewerAccess.mobile);
    expect(t.calls, isEmpty);
  });

  test('reviewer: fixed OTP signs in without calling Gupshup', () async {
    final t = _repo(cfg);
    final agent =
        await t.repo.verifyLoginOtp(ReviewerAccess.mobile, ReviewerAccess.otp);
    expect(agent.phone, ReviewerAccess.mobile);
    expect(t.calls, isEmpty);
  });

  test('reviewer: any other code still goes to Gupshup and is rejected',
      () async {
    final t = _repo(cfg);
    await expectLater(
      t.repo.verifyLoginOtp(ReviewerAccess.mobile, '9999'),
      throwsA(isA<ApiException>()),
    );
    expect(t.calls, hasLength(1));
  });

  test('other numbers: the fixed OTP is NOT accepted', () async {
    final t = _repo(cfg);
    await expectLater(
      t.repo.verifyLoginOtp('9876543210', ReviewerAccess.otp),
      throwsA(isA<ApiException>()),
    );
    expect(t.calls, hasLength(1));
  });

  test('other numbers: an OTP request still sends an SMS', () async {
    final t = _repo(cfg);
    // The stub gateway rejects, which surfaces as an exception — what matters
    // is that the gateway WAS contacted for a non-reviewer number.
    await expectLater(
      t.repo.requestLoginOtp('9876543210'),
      throwsA(isA<ApiException>()),
    );
    expect(t.calls, hasLength(1));
  });

  test('isReviewer ignores surrounding whitespace only', () {
    expect(ReviewerAccess.isReviewer(' ${ReviewerAccess.mobile} '), isTrue);
    expect(ReviewerAccess.isReviewer('7995213739'), isFalse);
  });
}
