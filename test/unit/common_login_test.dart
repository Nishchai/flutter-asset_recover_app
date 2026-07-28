import 'dart:convert';
import 'dart:io';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/error/failure.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/data/datasources/gupshup_otp_datasource.dart';
import 'package:asset_recovery_app/data/repositories/api_ticket_repository.dart';
import 'package:asset_recovery_app/data/repositories/mock_ticket_repository.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/partner_login_data.dart';
import 'package:asset_recovery_app/domain/usecases/login_otp_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Loads the REAL `api_endpoints.json` (so the configured commonLogin URL is
/// what gets asserted) with everything else stubbed.
Future<ConfigService> _config() async {
  final endpoints =
      await File('assets/config/api_endpoints.json').readAsString();
  const env = {
    'environment': 'ltest',
    'label': 'Login Test',
    'useMockData': false,
    'apiBaseUrl': 'https://recovery.example.test/api/v1/',
    'apiTimeoutSeconds': 5,
    'enableNetworkLogging': false,
  };
  return ConfigService.load(
    environment: 'ltest',
    reader: (path) async {
      if (path.contains('environments/')) return jsonEncode(env);
      if (path.contains('api_endpoints')) return endpoints;
      return '{}';
    },
  );
}

/// A successful `commonLogin` body, shaped exactly like the backend's
/// `LoginResponse`.
Map<String, dynamic> _successBody(String mobile) => {
      'status': 200,
      'reason': 'SUCCESS',
      'data': {
        'apppartneruserId': 5142,
        'usermobileNumber': mobile,
        'mobileUID': 'a1b2c3',
        'appId': 7,
        'emailId': 'ravi.kumar@sunmobility.com',
        'userId': 'SUNMU00002340',
        'isLoggedIn': true,
        'partnerId': 'SUNMU0000234',
        'isActive': true,
        'lastloginDate': '2026-07-27T18:31:02',
        'appVersion': '1.0.0',
        'deviceToken': 'fcm-token-xyz',
        'createdDate': '2024-01-09T10:00:00',
        'createdUser': 'admin',
        'lastModifiedDate': '2026-07-27T18:31:02',
        'lastUpdatedUser': 'admin',
        'lowBalanceThreshold': '500',
        'latestAppVersion': '1.0.0',
        'userName': 'Ravi Kumar',
        'userRole': 'field_agent',
        'enableCustomNotification': false,
      },
    };

Future<ApiTicketRepository> _repo(
  ConfigService cfg,
  http.Client client,
) async =>
    ApiTicketRepository(
      ApiClient(cfg, client: client),
      GupshupOtpDataSource(cfg, client: client),
    );

/// Directory miss: `commonLogin` rejects the number. Inherits the rest of the
/// mock backend and records whether an OTP was (wrongly) sent.
class _RejectingRepo extends MockTicketRepository {
  _RejectingRepo() : super(seed: 42, latency: Duration.zero);

  bool otpSent = false;

  @override
  Future<PartnerLoginData> commonLogin(String mobile) async =>
      throw ApiException('Mobile number not registered');

  @override
  Future<void> requestLoginOtp(String mobile) async => otpSent = true;
}

/// Found, but the agent has been deactivated.
class _DeactivatedRepo extends MockTicketRepository {
  _DeactivatedRepo() : super(seed: 42, latency: Duration.zero);

  bool otpSent = false;

  @override
  Future<PartnerLoginData> commonLogin(String mobile) async =>
      PartnerLoginData(
        usermobileNumber: mobile,
        userId: 'SUNMU00002340',
        isActive: false,
      );

  @override
  Future<void> requestLoginOtp(String mobile) async => otpSent = true;
}

void main() {
  group('commonLogin request', () {
    test('hits the SM-Partners host with appName + userMobilenumber', () async {
      final cfg = await _config();
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_successBody('9876543210')), 200);
      });

      await (await _repo(cfg, client)).commonLogin('9876543210');

      expect(captured.method, 'GET');
      expect(captured.url.origin, 'https://sm-partners-api.azurewebsites.net');
      expect(captured.url.path, '/api/v1/commonLogin');
      expect(captured.url.queryParameters, {
        'appName': 'INDOFAST_PARTNER',
        'userMobilenumber': '9876543210',
      });
      // Absolute endpoint URLs must not pick up apiBaseUrl or the app-scoped
      // agentId param.
      expect(captured.url.queryParameters.containsKey('agentId'), isFalse);
    });

    test('no Bearer header before a token exists', () async {
      final cfg = await _config();
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_successBody('9876543210')), 200);
      });

      await (await _repo(cfg, client)).commonLogin('9876543210');

      expect(captured.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('commonLogin response', () {
    test('maps the data block onto PartnerLoginData', () async {
      final cfg = await _config();
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_successBody('9876543210')), 200),
      );

      final data = await (await _repo(cfg, client)).commonLogin('9876543210');

      expect(data.userId, 'SUNMU00002340');
      expect(data.usermobileNumber, '9876543210');
      expect(data.userName, 'Ravi Kumar');
      expect(data.partnerId, 'SUNMU0000234');
      expect(data.apppartneruserId, 5142);
      expect(data.emailId, 'ravi.kumar@sunmobility.com');
      expect(data.isActive, isTrue);
      expect(data.userRole, 'field_agent');
      expect(data.lowBalanceThreshold, '500');
    });

    test('projects onto the app Agent used across the session', () async {
      final cfg = await _config();
      final client = MockClient(
        (_) async => http.Response(jsonEncode(_successBody('9876543210')), 200),
      );

      final agent =
          (await (await _repo(cfg, client)).commonLogin('9876543210')).toAgent();

      expect(agent.id, 'SUNMU0000234',
          reason: 'partnerId is THE agent id — query param and path segment',);
      expect(agent.name, 'Ravi Kumar');
      expect(agent.phone, '9876543210');
      expect(agent.role, AgentRole.fieldAgent);
    });

    test('the agent id falls back to userId when partnerId is absent', () async {
      final data = PartnerLoginData.fromJson({
        'usermobileNumber': '9876543210',
        'userId': 'SUNMU00002340',
        'userName': 'Ravi Kumar',
      });

      expect(data.toAgent().id, 'SUNMU00002340');
    });

    test('keeps recovery-domain fields the partner directory does not carry',
        () async {
      final data = PartnerLoginData.fromJson(
        _successBody('9876543210')['data']! as Map<String, dynamic>,
      );
      const fromRecoveryBackend = Agent(
        id: 'ignored',
        name: 'ignored',
        cluster: 'Bengaluru South',
        zone: 'Zone 4',
        recoveredCount: 47,
      );

      final agent = data.toAgent(base: fromRecoveryBackend);

      expect(agent.id, 'SUNMU0000234', reason: 'identity wins from commonLogin');
      expect(agent.name, 'Ravi Kumar');
      expect(agent.cluster, 'Bengaluru South');
      expect(agent.zone, 'Zone 4');
      expect(agent.recoveredCount, 47);
    });

    test('survives the secure-storage round trip', () async {
      final original = PartnerLoginData.fromJson(
        _successBody('9876543210')['data']! as Map<String, dynamic>,
      );

      final restored = PartnerLoginData.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.toJson(), original.toJson());
    });

    test('a non-success envelope throws with the backend reason', () async {
      final cfg = await _config();
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'status': 400,
            'reason': 'Mobile number not registered',
            'data': null,
          }),
          200, // the API reports failures inside a 200 envelope
        ),
      );

      expect(
        () => (_repo(cfg, client)).then((r) => r.commonLogin('9000000000')),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'Mobile number not registered',),),
      );
    });

    test('a 200 with no data block is still a failure', () async {
      final cfg = await _config();
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'status': 200, 'reason': 'SUCCESS'}),
          200,
        ),
      );

      expect(
        () => (_repo(cfg, client)).then((r) => r.commonLogin('9000000000')),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('RequestLoginOtpUseCase gating', () {
    test('an unknown number sends NO OTP and surfaces the server reason',
        () async {
      final repo = _RejectingRepo();

      final result = await RequestLoginOtpUseCase(repo)('9000000000');

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.message, 'Mobile number not registered',
          reason: 'the raw ApiException(...) wrapper must not reach the UI',);
      expect(repo.otpSent, isFalse, reason: 'no SMS for an unknown number');
    });

    test('a deactivated agent sends NO OTP', () async {
      final repo = _DeactivatedRepo();

      final result = await RequestLoginOtpUseCase(repo)('9876543210');

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.message, contains('deactivated'));
      expect(repo.otpSent, isFalse);
    });

    test('a found agent gets an OTP and the profile is returned', () async {
      final repo = MockTicketRepository(seed: 42, latency: Duration.zero);

      final result = await RequestLoginOtpUseCase(repo)('9876543210');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.usermobileNumber, '9876543210');
      // The mock keys every seeded ticket off this one id, so the directory
      // record must resolve to it.
      expect(result.valueOrNull!.toAgent().id, 'FA-RM-01');
    });
  });

  group('agentId request scoping', () {
    test('relative endpoints carry the session agentId', () async {
      final cfg = await _config();
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
      });
      final api = ApiClient(cfg, client: client)
        // What SessionStore.onAgentIdChanged pushes: the commonLogin partnerId.
        ..agentId = 'SUNMU0000234';

      await api.call('tickets.assigned', query: {'page': '1'});

      expect(captured.queryParameters['agentId'], 'SUNMU0000234');
      expect(captured.queryParameters['page'], '1');
    });

    test('the param is omitted entirely when there is no session', () async {
      final cfg = await _config();
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
      });

      await ApiClient(cfg, client: client).call('tickets.assigned');

      expect(captured.queryParameters.containsKey('agentId'), isFalse,
          reason: 'an empty agentId= is worse than none',);
      expect(captured.hasQuery, isFalse);
    });

    test('an explicit caller-supplied agentId still wins', () async {
      final cfg = await _config();
      late Uri captured;
      final client = MockClient((req) async {
        captured = req.url;
        return http.Response(jsonEncode({'items': <dynamic>[]}), 200);
      });
      final api = ApiClient(cfg, client: client)..agentId = 'SUNMU0000234';

      await api.call('tickets.assigned', query: {'agentId': 'OVERRIDE'});

      expect(captured.queryParameters['agentId'], 'OVERRIDE');
    });
  });

  group('failureFrom', () {
    test('unwraps Type(...) and Type: ... exception text', () {
      expect(failureFrom(ApiException('Mobile number not registered')).message,
          'Mobile number not registered',);
      expect(failureFrom(Exception('boom')).message, 'boom');
      expect(failureFrom(StateError('deactivated')).message, 'deactivated');
      expect(failureFrom(const FormatException('Invalid OTP')).message,
          'Invalid OTP',);
    });
  });
}
