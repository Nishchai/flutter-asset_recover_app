import 'dart:convert';
import 'dart:io';

import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/data/repositories/api_battery_movement_repository.dart';
import 'package:asset_recovery_app/data/repositories/mock_battery_movement_repository.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_request.dart';
import 'package:asset_recovery_app/domain/entities/battery_suggestion.dart';
import 'package:asset_recovery_app/domain/repositories/battery_movement_repository.dart';
import 'package:asset_recovery_app/domain/usecases/battery_movement_usecases.dart';
import 'package:asset_recovery_app/presentation/state/battery_movement_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Real `api_endpoints.json`, stub env — so the configured paths are what gets
/// asserted against the captured BDD-tool calls.
Future<ConfigService> _config() async {
  final endpoints =
      await File('assets/config/api_endpoints.json').readAsString();
  const env = {
    'environment': 'bmtest',
    'label': 'BM Test',
    'useMockData': false,
    'apiBaseUrl': 'https://recovery.example.test/api/v1/',
    'apiTimeoutSeconds': 5,
    'enableNetworkLogging': false,
  };
  return ConfigService.load(
    environment: 'bmtest',
    reader: (path) async {
      if (path.contains('environments/')) return jsonEncode(env);
      if (path.contains('api_endpoints')) return endpoints;
      return '{}';
    },
  );
}

BatteryMovementProvider _provider(
  BatteryMovementRepository repo, {
  int pageSize = 20,
}) =>
    BatteryMovementProvider(
      getQueries: GetBatteryMovementQueriesUseCase(repo),
      getInProgress: GetInProgressMovementQueriesUseCase(repo),
      getRelated: GetRelatedMovementQueriesUseCase(repo),
      requestData: RequestBatteryMovementDataUseCase(repo),
      searchBatteries: SearchBatteriesUseCase(repo),
      pageSize: pageSize,
    );

/// A repository stub for tests that only care about completed queries. The
/// request-flow methods are unused there.
abstract class _ReportOnlyRepo implements BatteryMovementRepository {
  @override
  Future<List<BatterySuggestion>> searchBatteries(String text) async =>
      const [];

  @override
  Future<List<BatteryMovementQuery>> inProgressQueries() async => const [];

  @override
  Future<List<BatteryMovementQuery>> relatedQueries(
    BatteryMovementRequest request,
  ) async =>
      const [];

  @override
  Future<void> requestData(BatteryMovementRequest request) async {}
}

class _FailingRepo extends _ReportOnlyRepo {
  _FailingRepo(this.inner);
  final BatteryMovementRepository inner;
  bool fail = false;

  @override
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    if (fail) throw const SocketException('offline');
    return inner.completedQueries(
      serialNumber: serialNumber,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<BatteryMovementQuery>> inProgressQueries() =>
      inner.inProgressQueries();
}

/// Records every type-ahead lookup the provider actually sends.
class _CountingSearchRepo extends _ReportOnlyRepo {
  _CountingSearchRepo({this.fail = false});
  final bool fail;
  final searches = <String>[];

  @override
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  }) async =>
      BatteryMovementPage.empty(pageSize: pageSize);

  @override
  Future<List<BatterySuggestion>> searchBatteries(String text) async {
    searches.add(text);
    if (fail) throw const SocketException('offline');
    return const [BatterySuggestion(serialNumber: 'INSMOMAH1007L04A2F13')];
  }
}

/// A source whose create call is rejected.
class _ThrowingRequestRepo extends MockBatteryMovementRepository {
  _ThrowingRequestRepo() : super(latency: Duration.zero);

  @override
  Future<void> requestData(BatteryMovementRequest request) async =>
      throw StateError('Daily limit reached');
}

/// A source that, like the search endpoint, reports no total.
class _NoTotalRepo extends _ReportOnlyRepo {
  _NoTotalRepo({required this.rows});
  final int rows;

  @override
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    final start = pageNumber * pageSize;
    final count = (rows - start).clamp(0, pageSize);
    return BatteryMovementPage(
      items: [
        for (var i = 0; i < count; i++)
          BatteryMovementQuery(
            id: '${start + i}',
            category: 'Wheelers',
            serialNumber: 'S${start + i}',
          ),
      ],
      total: start + count,
      totalKnown: false,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }
}

void main() {
  MockBatteryMovementRepository mock() =>
      MockBatteryMovementRepository(latency: Duration.zero);

  group('MockBatteryMovementRepository', () {
    test('pages through all 131 rows', () async {
      final repo = mock();
      final first = await repo.completedQueries(pageSize: 20);
      expect(first.total, 131);
      expect(first.items, hasLength(20));
      final last = await repo.completedQueries(pageNumber: 6, pageSize: 20);
      expect(last.items, hasLength(11));
      final beyond = await repo.completedQueries(pageNumber: 7, pageSize: 20);
      expect(beyond.items, isEmpty);
    });

    test('filters by serial, case-insensitively', () async {
      final repo = mock();
      final res = await repo.completedQueries(
        serialNumber: 'insmomah1007l14b',
        pageSize: 100,
      );
      expect(res.total, greaterThan(0));
      expect(res.total, lessThan(131));
      expect(
        res.items.every((r) => r.serialNumber.contains('INSMOMAH1007L14B')),
        isTrue,
      );
    });
  });

  group('BatteryMovementProvider', () {
    test('a search under 4 characters is rejected and loads nothing', () async {
      final p = _provider(mock());
      await p.load();
      final before = p.items.length;
      expect(await p.search('abc'), isFalse);
      expect(p.isSearching, isFalse);
      expect(p.items, hasLength(before));
    });

    test('a valid search resets to page one and clearSearch restores',
        () async {
      final p = _provider(mock(), pageSize: 10);
      await p.load();
      await p.nextPage();
      expect(p.pageNumber, 1);

      expect(await p.search('  INSMOMAH1007L14B  '), isTrue);
      expect(p.pageNumber, 0);
      expect(p.serial, 'INSMOMAH1007L14B');
      expect(p.total, lessThan(131));

      await p.clearSearch();
      expect(p.isSearching, isFalse);
      expect(p.total, 131);
    });

    test('paging: indexes, bounds and page size', () async {
      final p = _provider(mock(), pageSize: 50);
      await p.load();
      expect((p.fromIndex, p.toIndex, p.total), (1, 50, 131));
      expect(p.hasPrevious, isFalse);
      expect(p.hasNext, isTrue);

      await p.nextPage();
      await p.nextPage();
      expect((p.fromIndex, p.toIndex), (101, 131));
      expect(p.hasNext, isFalse);

      await p.nextPage(); // no-op past the end
      expect(p.pageNumber, 2);

      await p.setPageSize(100);
      expect(p.pageNumber, 0);
      expect(p.items, hasLength(100));
    });

    test('running queries are loaded alongside the page', () async {
      final p = _provider(mock());
      expect(p.inProgressLoaded, isFalse);
      await p.load();
      expect(p.inProgressLoaded, isTrue);
      expect(p.inProgressCount, 1);
      final q = p.inProgress.single;
      expect(q.statusCode, BatteryMovementQuery.statusInProgress);
      expect(q.estimatedTime, '00:10:00');
      expect(q.hasReport, isFalse, reason: 'no report while it runs');
    });

    BatteryMovementRequest request({
      String serial = 'INSMOMAH1007L04A2F13',
      DateTime? start,
      DateTime? end,
    }) =>
        BatteryMovementRequest(
          serialNumber: serial,
          startDate: start ?? DateTime(2026, 11, 4),
          endDate: end ?? DateTime(2026, 11, 11),
          requestedBy: 'Nishchai GN',
          email: 'nishchai.gn@example.test',
        );

    test('submitting a request adds a running query and reloads the report',
        () async {
      final p = _provider(mock());
      await p.load();
      expect(p.inProgressCount, 1);

      final error = await p.submitRequest(request());
      expect(error, isNull);
      expect(p.inProgressCount, 2);
      expect(p.inProgress.first.serialNumber, 'INSMOMAH1007L04A2F13');
      expect(p.items, isNotEmpty, reason: 'completed list reloaded too');
    });

    test('the type-ahead asks nothing below 4 characters', () async {
      final repo = _CountingSearchRepo();
      final p = _provider(repo);
      for (final short in ['', 'IN', 'INS', '  ab ']) {
        final r = await p.findBatteries(short);
        expect(r.items, isEmpty);
        expect(r.error, isNull);
      }
      expect(repo.searches, isEmpty, reason: 'the service was never asked');

      final r = await p.findBatteries('INSM');
      expect(repo.searches, ['INSM']);
      expect(r.items.map((s) => s.serialNumber), ['INSMOMAH1007L04A2F13']);
    });

    test('a failed type-ahead lookup says so instead of "no matches"',
        () async {
      final p = _provider(_CountingSearchRepo(fail: true));
      final r = await p.findBatteries('INSMOMAH');
      expect(r.items, isEmpty);
      expect(r.error, isNotNull);
    });

    test('the mock type-ahead matches serials case-insensitively', () async {
      final p = _provider(mock());
      final r = await p.findBatteries('insmomah1108');
      expect(r.items.map((s) => s.serialNumber), ['INSMOMAH1108A25F1013']);
    });

    test('a failed submit returns the message and keeps the list', () async {
      final p = _provider(_ThrowingRequestRepo());
      await p.load();
      final error = await p.submitRequest(request());
      expect(error, 'Daily limit reached');
    });

    test('the related-queries check lists overlapping queries only', () async {
      final p = _provider(mock());
      // Same battery, window overlapping the seeded history.
      final hit = await p.checkRelated(
        request(
          serial: 'INSMOMAH1007L14B4213',
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 11, 11),
        ),
      );
      expect(hit.error, isNull);
      expect(hit.related, isNotEmpty);
      expect(
        hit.related.every((q) => q.serialNumber == 'INSMOMAH1007L14B4213'),
        isTrue,
      );

      // A battery the history has never seen.
      final miss = await p.checkRelated(request(serial: 'UNKNOWNSERIAL0001'));
      expect(miss.related, isEmpty);
    });

    test('a failed page load keeps the rows and rewinds the page counter',
        () async {
      final repo = _FailingRepo(mock());
      final p = _provider(repo, pageSize: 10);
      await p.load();
      expect(p.items, hasLength(10));

      repo.fail = true;
      await p.nextPage();
      expect(p.error, isNotNull);
      expect(p.items, hasLength(10), reason: 'rows stay on screen');
      expect(p.pageNumber, 0, reason: 'counter matches what is shown');
      expect(p.loading, isFalse);

      repo.fail = false;
      await p.nextPage();
      expect(p.error, isNull);
      expect(p.pageNumber, 1);
    });

    test('with no total (search), a full page means there may be more',
        () async {
      final p = _provider(_NoTotalRepo(rows: 25), pageSize: 10);
      await p.load();
      expect(p.totalKnown, isFalse);
      expect(p.hasNext, isTrue, reason: 'page is full');

      await p.nextPage();
      expect(p.hasNext, isTrue);
      await p.nextPage(); // 5 rows — a short page ends the list
      expect(p.items, hasLength(5));
      expect(p.hasNext, isFalse);
      expect((p.fromIndex, p.toIndex), (21, 25));
    });
  });

  group('ApiBatteryMovementRepository', () {
    late ConfigService cfg;
    setUp(() async => cfg = await _config());

    http.Response reply(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );

    Map<String, Object> programTypesBody() => {
          'version': '1.0.0.0',
          'statusCode': 200,
          'message': 'Ok',
          'isError': false,
          'result': [
            {'id': 233, 'code': 17, 'description': 'Wheelers'},
            {'id': 232, 'code': 18, 'description': 'Bus'},
          ],
        };

    /// [respond] answers the report calls; ProgramType is answered separately
    /// ([onProgramType], by default the real master's 17 = Wheelers, 18 = Bus).
    ApiBatteryMovementRepository build(
      http.Response Function(Uri) respond,
      List<Uri> calls, {
      http.Response Function(Uri)? onProgramType,
    }) {
      final client = MockClient((req) async {
        calls.add(req.url);
        if (req.url.path.endsWith('/ProgramType')) {
          return (onProgramType ?? (_) => reply(programTypesBody()))(req.url);
        }
        return respond(req.url);
      });
      return ApiBatteryMovementRepository(
        ApiClient(cfg, client: client),
        batteryType: 17,
      );
    }

    bool isReport(Uri u) => u.path.endsWith('/BatteryMovementReport');
    bool isCount(Uri u) => u.path.endsWith('/GetTotalCount');

    test('landing fires GetTotalCount, ProgramType and the list together',
        () async {
      final calls = <Uri>[];
      final repo = build(
        (u) => isCount(u) ? reply(131) : reply(<Object>[]),
        calls,
      );
      await repo.completedQueries(pageNumber: 2, pageSize: 100);

      expect(calls, hasLength(3));
      final list = calls.firstWhere(isReport);
      final count = calls.firstWhere(isCount);
      final types = calls.firstWhere((u) => u.path.endsWith('/ProgramType'));
      expect(list.host, 'recovery.example.test');
      expect(list.path, '/api/v1/BatteryMovementReport');
      expect(count.path, '/api/v1/BatteryMovementReport/GetTotalCount');
      expect(types.path, '/api/v1/ProgramType');
      for (final u in [list, count]) {
        expect(u.queryParameters['batteryType'], '17');
        expect(u.queryParameters['queryType'], 'Live');
        expect(u.queryParameters['queryStatus'], '3,4,5');
      }
      expect(list.queryParameters['pageSize'], '100');
      expect(list.queryParameters['pageNumber'], '2');
    });

    test('ProgramType names the category and is fetched only once', () async {
      final calls = <Uri>[];
      final repo = build(
        (u) => isCount(u)
            ? reply(2)
            : reply([
                {'batterySerialNumber': 'A', 'batteryTypeId': 17},
                {'batterySerialNumber': 'B', 'batteryTypeId': 18},
                {'batterySerialNumber': 'C', 'batteryTypeId': 99},
              ]),
        calls,
      );
      final first = await repo.completedQueries();
      await repo.completedQueries(pageNumber: 1);

      expect(
        first.items.map((q) => q.category).toList(),
        ['Wheelers', 'Bus', 'Type 99'],
      );
      expect(
        calls.where((u) => u.path.endsWith('/ProgramType')),
        hasLength(1),
        reason: 'cached after the first success',
      );
    });

    test('a failing ProgramType call does not break the report', () async {
      final calls = <Uri>[];
      final repo = build(
        (u) => isCount(u)
            ? reply(1)
            : reply([
                {'batterySerialNumber': 'A', 'batteryTypeId': 17},
              ]),
        calls,
        onProgramType: (_) => http.Response('nope', 500),
      );
      final page = await repo.completedQueries();
      expect(
        page.items.single.category,
        'Wheelers',
        reason: 'falls back to the configured name',
      );

      // …and is retried on the next load rather than cached as a failure.
      await repo.completedQueries();
      expect(calls.where((u) => u.path.endsWith('/ProgramType')), hasLength(2));
    });

    test('searching uses SearchBattery with text and no total', () async {
      final calls = <Uri>[];
      final repo = build(
        (u) => reply({
          'isError': false,
          'result': [
            {'batterySerialNumber': 'INSMOMAH0307C1069712', 'queryStatus': 3},
          ],
        }),
        calls,
      );
      final page = await repo.completedQueries(
        serialNumber: ' INSMOMAH0307C1069712 ',
        pageNumber: 1,
        pageSize: 100,
      );

      final search = calls.firstWhere((u) => u.path.endsWith('/SearchBattery'));
      expect(search.path, '/api/v1/BatteryMovementReport/SearchBattery');
      expect(
        search.queryParameters,
        {
          'batteryType': '17',
          'text': 'INSMOMAH0307C1069712',
          'queryStatus': '3,4',
          'pageSize': '100',
          'pageNumber': '1',
        },
      );
      expect(calls.any(isCount), isFalse, reason: 'search has no count call');
      expect(page.totalKnown, isFalse);
      expect(page.items.single.serialNumber, 'INSMOMAH0307C1069712');
    });

    test('maps a real BDD report row onto the screen columns', () async {
      // Row copied from the staging API (id 150), wrapped as the API wraps it.
      const report =
          'https://smprodappsdiag674.blob.core.windows.net/bddv2-data/battery_movement/INSMOMAH1007L14B4213/Battery_Movement_INSMOMAH1007L14B4213_20261001T0000_to_20261001T2359_bmr-150-20261111152002.html';
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply({'isError': false, 'result': 131})
            : reply({
                'version': '1.0.0.0',
                'statusCode': 200,
                'message': 'Ok',
                'isError': false,
                'result': [
                  {
                    'id': 150,
                    'batterySerialNumber': 'INSMOMAH1007L14B4213',
                    'batteryTypeId': 17,
                    'queryStatus': 3,
                    'startTime': 1790793000,
                    'endTime': 1790879399,
                    'timeTaken': 69,
                    'expectedTime': 120,
                    'reportUrl': report,
                    'remark': 'Success',
                    'jobId': 'bmr-150-20261111152002',
                    'attempts': 1,
                    'createdBy': 'Someone',
                    'mailId': 'someone@example.test',
                    'createdDate': 1794390552,
                    'modifiedDate': 1794390672,
                  },
                ],
              }),
        [],
      );
      final page = await repo.completedQueries();
      expect(page.total, 131);
      final q = page.items.single;
      expect(q.id, '150');
      expect(q.serialNumber, 'INSMOMAH1007L14B4213');
      expect(q.category, 'Wheelers', reason: 'from batteryTypeId 17');
      expect(q.statusCode, BatteryMovementQuery.statusSuccess);
      expect(q.remarks, 'Success', reason: 'the service\'s `remark` text');
      expect(q.succeeded, isTrue);
      expect(q.timeTaken, '00:01:09', reason: 'timeTaken 69 s');
      expect(q.reportUrl, report);
      expect(q.hasReport, isTrue);
      DateTime at(int s) =>
          DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true);
      expect(q.startTime, at(1790793000));
      expect(q.endTime, at(1790879399));
      expect(q.createdAt, at(1794390552));
      expect(q.updatedAt, at(1794390672));
    });

    test('failed and no-data queries keep the reason and have no report',
        () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply(3)
            : reply({
                'isError': false,
                'result': [
                  {
                    'id': 137,
                    'batterySerialNumber': 'INSMOMAHA406K17C4711',
                    'batteryTypeId': 17,
                    'queryStatus': 5,
                    'timeTaken': 505,
                    'reportUrl': null,
                    'remark':
                        'No BP live data for INSMOMAHA406K17C4711 between 2026-10-29 00:00:00 and 2026-10-30 23:59:59, so no report was created.',
                  },
                  {
                    'id': 132,
                    'batterySerialNumber': 'INSMOMAH1409C2718313',
                    'batteryTypeId': 17,
                    'queryStatus': 4,
                    'reportUrl': null,
                    'remark':
                        'Report generation failed: No live data rows with a valid GPS position',
                  },
                  {
                    'id': 131,
                    'batterySerialNumber': 'INSMOMAH3309K2786813',
                    'batteryTypeId': 17,
                    'queryStatus': 3,
                    'remark': 'Success',
                  },
                ],
              }),
        [],
      );
      final items = (await repo.completedQueries()).items;

      expect(items[0].statusCode, BatteryMovementQuery.statusNoData);
      expect(items[0].remarks, startsWith('No BP live data for'));
      expect(items[0].succeeded, isFalse);
      expect(items[0].hasReport, isFalse);

      expect(items[1].statusCode, BatteryMovementQuery.statusFailed);
      expect(items[1].remarks, startsWith('Report generation failed'));
      expect(items[1].succeeded, isFalse);

      expect(items[2].succeeded, isTrue);
      expect(items[2].hasReport, isFalse, reason: 'no reportUrl was sent');
    });

    test('only https report links are accepted', () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply(4)
            : reply([
                {
                  'batterySerialNumber': 'A',
                  'reportUrl': 'https://x.test/a.html',
                },
                {
                  'batterySerialNumber': 'B',
                  'reportUrl': 'http://x.test/b.html',
                },
                {
                  'batterySerialNumber': 'C',
                  'reportUrl': 'javascript:alert(1)',
                },
                {'batterySerialNumber': 'D', 'reportUrl': ''},
              ]),
        [],
      );
      final items = (await repo.completedQueries()).items;
      expect(
        items.map((q) => q.reportUrl).toList(),
        ['https://x.test/a.html', null, null, null],
      );
    });

    test('takt time over 24h keeps counting hours, like the BDD tool',
        () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply(1)
            : reply([
                {'batterySerialNumber': 'A', 'taktTime': 7890281},
                {'batterySerialNumber': 'B', 'taktTime': 69},
              ]),
        [],
      );
      final items = (await repo.completedQueries()).items;
      expect(items[0].timeTaken, '2191:44:41');
      expect(items[1].timeTaken, '00:01:09');
    });

    test('status code is kept raw; an unknown type is named, not guessed',
        () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply(3)
            : reply([
                {'batterySerialNumber': 'A', 'queryStatus': 3},
                {'batterySerialNumber': 'B', 'queryStatus': 7},
                {'batterySerialNumber': 'C', 'batteryTypeId': 99},
              ]),
        [],
      );
      final items = (await repo.completedQueries()).items;
      expect(items[0].statusCode, 3);
      expect(items[0].succeeded, isTrue, reason: 'status 3 alone is success');
      expect(items[1].statusCode, 7);
      expect(items[1].succeeded, isFalse);
      expect(items[2].category, 'Type 99');
      expect(items[2].statusCode, isNull);
      expect(items[2].remarks, isEmpty);
    });

    test('an object count is read, and the completed statuses are configurable',
        () async {
      final calls = <Uri>[];
      final client = MockClient((req) async {
        calls.add(req.url);
        return req.url.path.endsWith('GetTotalCount')
            ? reply({'totalCount': 7})
            : reply(<Object>[]);
      });
      final repo = ApiBatteryMovementRepository(
        ApiClient(cfg, client: client),
        batteryType: 17,
        completedStatuses: '3',
      );
      final page = await repo.completedQueries();
      expect(page.total, 7);
      final reportCalls =
          calls.where((u) => u.path.contains('/BatteryMovementReport'));
      expect(reportCalls, hasLength(2));
      expect(
        reportCalls.every((u) => u.queryParameters['queryStatus'] == '3'),
        isTrue,
      );
    });

    test('in-progress asks for status 1, unpaged, and reads the rows',
        () async {
      final calls = <Uri>[];
      final repo = build(
        (_) => reply({
          'isError': false,
          'result': [
            {
              'id': 153,
              'batterySerialNumber': 'INSMOMAH1007L04A2F13',
              'batteryTypeId': 17,
              'queryStatus': 1,
              'startTime': 1793730600,
              'endTime': 1794421799,
              'timeTaken': 0,
              'expectedTime': 600,
              'reportUrl': null,
              'createdDate': 1794421800,
              'modifiedDate': 1794421800,
            },
          ],
        }),
        calls,
      );
      final running = await repo.inProgressQueries();

      final call = calls.firstWhere(isReport);
      expect(call.queryParameters, {
        'batteryType': '17',
        'queryType': 'Live',
        'queryStatus': '1',
      });
      expect(running, hasLength(1));
      expect(running.single.statusCode, BatteryMovementQuery.statusInProgress);
      expect(
        running.single.estimatedTime,
        '00:10:00',
        reason: 'expectedTime 600 s',
      );
      expect(running.single.category, 'Wheelers');
      expect(running.single.hasReport, isFalse);
    });

    test('related queries are looked up by serial and the IST epoch window',
        () async {
      final calls = <Uri>[];
      final repo = build(
        (_) => reply({
          'isError': false,
          'result': [
            {
              'batterySerialNumber': 'INSMOMAH1007L04A2F13',
              'batteryTypeId': 17,
              'startTime': 1793730600,
              'endTime': 1793816999,
            },
          ],
        }),
        calls,
      );
      final related = await repo.relatedQueries(
        BatteryMovementRequest(
          serialNumber: ' INSMOMAH1007L04A2F13 ',
          startDate: DateTime(2026, 11, 4),
          endDate: DateTime(2026, 11, 11),
          requestedBy: 'x',
          email: 'x@example.test',
        ),
      );

      final call = calls.firstWhere((u) => u.path.endsWith('/BatteryQuery'));
      expect(call.path, '/api/v1/BatteryMovementReport/BatteryQuery');
      expect(call.queryParameters, {
        'serialNumber': 'INSMOMAH1007L04A2F13',
        // 4 Nov 00:00:00 IST and 11 Nov 23:59:59 IST — the same window the BDD
        // tool sent (startTime 1793730600, endTime 1794421799).
        'startTime': '1793730600',
        'endTime': '1794421799',
      });
      expect(related.single.serialNumber, 'INSMOMAH1007L04A2F13');
      expect(related.single.category, 'Wheelers');
    });

    test('the type-ahead calls Battery Master with an upper-cased text',
        () async {
      final calls = <Uri>[];
      final repo = build(
        (_) => reply({
          'isError': false,
          'result': [
            {
              'batterySerialNumber': 'INSMOMAH1108A25F1013',
              'tiuSerialNumber': '0035624991',
            },
            {'batterySerialNumber': 'INSMOMAH1108A25F1014'},
            {'tiuSerialNumber': 'no-serial-row'},
          ],
        }),
        calls,
      );
      final found = await repo.searchBatteries(' insmomah1108 ');

      final call = calls.single;
      expect(call.host, 'smartnetwork.azure-api.net');
      expect(
        call.path,
        '/battery-master-api/api/v2/WheelerBattery/SearchBattery',
      );
      expect(
        call.queryParameters,
        {'text': 'INSMOMAH1108'},
        reason: 'upper-cased, trimmed, and no app-scoped agentId param',
      );
      expect(
        found.map((s) => s.serialNumber),
        ['INSMOMAH1108A25F1013', 'INSMOMAH1108A25F1014'],
        reason: 'a row without a serial is dropped',
      );
      expect(found.first.tiuSerialNumber, '0035624991');
    });

    test('creating a request posts the same body as the BDD tool', () async {
      final calls = <http.Request>[];
      final client = MockClient((req) async {
        calls.add(req);
        return reply({'isError': false, 'result': null});
      });
      final repo = ApiBatteryMovementRepository(
        ApiClient(cfg, client: client),
        batteryType: 17,
      );
      await repo.requestData(
        BatteryMovementRequest(
          serialNumber: ' insmomah1007l04a2f13 '.toUpperCase(),
          startDate: DateTime(2026, 11, 4),
          endDate: DateTime(2026, 11, 11),
          requestedBy: 'Nishchai GN',
          email: 'Nishchai.GN@sunmobility.com',
        ),
      );

      final post = calls.single;
      expect(post.method, 'POST');
      expect(post.url.path, '/api/v1/BatteryMovementReport');
      expect(jsonDecode(post.body), {
        'batterySerialNumber': 'INSMOMAH1007L04A2F13',
        'batteryTypeId': 17,
        'queryStatus': 1,
        'queryType': 'Live',
        'startTime': 1793730600,
        'endTime': 1794421799,
        'timeTaken': 0,
        'createdBy': 'Nishchai GN',
        'modifiedBy': 'Nishchai GN',
        'mailId': 'Nishchai.GN@sunmobility.com',
      });
    });

    test('a create call the service flags as an error throws its message',
        () async {
      final repo = build(
        (_) => reply({
          'statusCode': 400,
          'message': 'Invalid date range',
          'isError': true,
          'result': null,
        }),
        [],
      );
      await expectLater(
        repo.requestData(
          BatteryMovementRequest(
            serialNumber: 'INSMOMAH1007L04A2F13',
            startDate: DateTime(2026, 11, 4),
            endDate: DateTime(2026, 11, 11),
            requestedBy: 'x',
            email: 'x@example.test',
          ),
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Invalid date range'),
        ),
      );
    });

    test('reads the BDD {isError, result} wrapper and epoch-second dates',
        () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply({
                'statusCode': 200,
                'message': 'Ok',
                'isError': false,
                'result': 131,
              })
            : reply({
                'statusCode': 200,
                'message': 'Ok',
                'isError': false,
                'result': [
                  {
                    'category': 'Wheelers',
                    'batterySerialNumber': 'INSMOMAH1007L14B4213',
                    'startTime': 1789711265, // seconds
                    'endTime': 1789714865,
                    'createdDate': '1789718465', // numeric text
                    'remarks': 'Success',
                  },
                ],
              }),
        [],
      );
      final page = await repo.completedQueries();
      expect(page.total, 131);
      final q = page.items.single;
      expect(
        q.startTime,
        DateTime.fromMillisecondsSinceEpoch(
          1789711265 * 1000,
          isUtc: true,
        ),
      );
      expect(q.endTime!.difference(q.startTime!), const Duration(hours: 1));
      expect(q.createdAt, isNotNull);
      expect(q.updatedAt, isNull);
    });

    test('millisecond epochs are read as such', () async {
      final repo = build(
        (u) => u.path.endsWith('GetTotalCount')
            ? reply(1)
            : reply([
                {'serialNumber': 'ABCD', 'startTime': 1789711265000},
              ]),
        [],
      );
      final q = (await repo.completedQueries()).items.single;
      expect(q.startTime!.millisecondsSinceEpoch, 1789711265000);
    });

    test('isError: true in the wrapper becomes an exception', () async {
      final repo = build(
        (_) => reply({
          'statusCode': 400,
          'message': 'Date range too long',
          'isError': true,
          'result': null,
        }),
        [],
      );
      await expectLater(
        repo.completedQueries(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Date range too long'),
        ),
      );
    });

    test('a server error surfaces as an exception', () async {
      final repo = build((_) => http.Response('nope', 500), []);
      await expectLater(
        repo.completedQueries(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('BatteryMovementRequest', () {
    final today = DateTime(2026, 11, 12);

    BatteryMovementRequestError? check({
      String serial = 'INSMOMAH1007L04A2F13',
      DateTime? start,
      DateTime? end,
    }) =>
        BatteryMovementRequest.validate(
          serialNumber: serial,
          startDate: start,
          endDate: end,
          today: today,
        );

    test('sends whole IST days as epoch seconds (matches the BDD capture)', () {
      final r = BatteryMovementRequest(
        serialNumber: 'INSMOMAH1007L04A2F13',
        startDate: DateTime(2026, 11, 4),
        endDate: DateTime(2026, 11, 11),
        requestedBy: 'x',
        email: 'x@example.test',
      );
      expect(r.startEpochSeconds, 1793730600); // 4 Nov 2026 00:00:00 IST
      expect(r.endEpochSeconds, 1794421799); // 11 Nov 2026 23:59:59 IST
    });

    test('a valid request passes', () {
      expect(
        check(start: DateTime(2026, 11, 4), end: DateTime(2026, 11, 11)),
        isNull,
      );
    });

    test('the serial needs at least 4 characters', () {
      expect(
        check(
          serial: 'abc',
          start: DateTime(2026, 11, 4),
          end: DateTime(2026, 11, 5),
        ),
        BatteryMovementRequestError.serialTooShort,
      );
      expect(
        check(
          serial: '  ab ',
          start: DateTime(2026, 11, 4),
          end: DateTime(2026, 11, 5),
        ),
        BatteryMovementRequestError.serialTooShort,
      );
      expect(
        check(
          serial: 'abcd',
          start: DateTime(2026, 11, 4),
          end: DateTime(2026, 11, 5),
        ),
        isNull,
      );
    });

    test('both dates are required', () {
      expect(
        check(start: DateTime(2026, 11, 4)),
        BatteryMovementRequestError.datesMissing,
      );
      expect(
        check(end: DateTime(2026, 11, 4)),
        BatteryMovementRequestError.datesMissing,
      );
    });

    test('the end may not be before the start', () {
      expect(
        check(start: DateTime(2026, 11, 8), end: DateTime(2026, 11, 7)),
        BatteryMovementRequestError.endBeforeStart,
      );
    });

    test('10 days (inclusive) is the longest period', () {
      expect(
        check(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 10)),
        isNull,
        reason: '1–10 Nov is 10 days',
      );
      expect(
        check(start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 11)),
        BatteryMovementRequestError.rangeTooLong,
        reason: '1–11 Nov is 11 days',
      );
    });

    test('the start may not be more than 12 months back', () {
      expect(
        check(start: DateTime(2025, 11, 12), end: DateTime(2025, 11, 14)),
        isNull,
        reason: 'exactly 12 months back is allowed',
      );
      expect(
        check(start: DateTime(2025, 11, 11), end: DateTime(2025, 11, 13)),
        BatteryMovementRequestError.startTooOld,
      );
    });
  });
}
