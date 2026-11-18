import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_request.dart';
import 'package:asset_recovery_app/domain/entities/battery_suggestion.dart';
import 'package:asset_recovery_app/domain/repositories/battery_movement_repository.dart';

/// Battery Movement Report from the backend, on the app's existing
/// `apiBaseUrl` (endpoints in `api_endpoints.json` under `batteryMovement` and
/// `programType`; see the BDD-BMR Postman collection).
///
/// Landing on the report fires three calls together:
///   1. `GET /BatteryMovementReport/GetTotalCount?batteryType=&queryStatus=` — the "of N" total
///   2. `GET /ProgramType` — code → name (17 = "Wheelers"), the Category column
///   3. `GET /BatteryMovementReport?batteryType=&queryStatus=&pageSize=&pageNumber=` — the rows
/// ProgramType is cached after the first success, so paging does not repeat it.
///
/// Searching by serial uses a different endpoint (no total comes back):
///   `GET /BatteryMovementReport/SearchBattery?batteryType=&text=&queryStatus=3,4&pageSize=&pageNumber=`
///
/// The in-progress counter is the list call with `queryStatus=1`.
///
/// Responses come wrapped as `{version, statusCode, message, isError, result}`.
/// A report row looks like:
/// ```
/// { "id": 313, "batterySerialNumber": "INSMOMAHA306G2708511",
///   "tiuSerialNumber": "0035624991", "startTime": 1696271400,   // epoch s
///   "endTime": 1696357800, "taktTime": 322,                     // seconds
///   "totalRecords": 0, "dataUrl": [], "queryStatus": 3,
///   "queryType": "Live", "batteryTypeId": 17,
///   "createdDate": 1696333111, "modifiedDate": 1696333433 }
/// ```
/// Two columns are derived: **Category** from `batteryTypeId` via ProgramType,
/// and **Remarks** from `queryStatus` (3 = Success).
class ApiBatteryMovementRepository implements BatteryMovementRepository {
  ApiBatteryMovementRepository(
    this._api, {
    required this.batteryType,
    this.fallbackCategory = 'Wheelers',
    this.completedStatuses = '3,4,5',
  });

  final ApiClient _api;

  /// `batteryType` query value — the ProgramType code (17 = "Wheelers").
  final int batteryType;

  /// Name shown for [batteryType] when the ProgramType call fails or does not
  /// list it, so the Category column is never blank because of that.
  final String fallbackCategory;

  /// `queryStatus` value(s) that count as "completed", comma-separated. The BDD
  /// tool and its Postman collection use `3,4,5` for the list and the count.
  final String completedStatuses;

  static const _queryType = 'Live';
  static const _inProgressStatus = '1';

  /// The search endpoint's own status filter (from the Postman collection).
  static const _searchStatuses = '3,4';

  Future<Map<int, String>>? _programTypes;

  @override
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    final serial = serialNumber?.trim() ?? '';
    final paging = {'pageSize': '$pageSize', 'pageNumber': '$pageNumber'};

    if (serial.isNotEmpty) {
      final r = await Future.wait<Object?>([
        _api.call(
          'batteryMovement.search',
          query: {
            'batteryType': '$batteryType',
            'text': serial,
            'queryStatus': _searchStatuses,
            ...paging,
          },
        ),
        _loadProgramTypes(),
      ]);
      _log('search', r[0]);
      final types = r[1]! as Map<int, String>;
      final items =
          _rows(_unwrap(r[0])).map((j) => _fromJson(j, types)).toList();
      return BatteryMovementPage(
        items: items,
        // The search endpoint reports no total — only what has been seen.
        total: pageNumber * pageSize + items.length,
        totalKnown: false,
        pageNumber: pageNumber,
        pageSize: pageSize,
      );
    }

    final filter = {
      'batteryType': '$batteryType',
      'queryType': _queryType,
      'queryStatus': completedStatuses,
    };
    final r = await Future.wait<Object?>([
      _api.call('batteryMovement.count', query: filter), // 1. GetTotalCount
      _loadProgramTypes(), //                                 2. ProgramType
      _api.call('batteryMovement.list', query: {...filter, ...paging}), // 3.
    ]);
    _log('count', r[0]);
    _log('list', r[2]);

    final types = r[1]! as Map<int, String>;
    final items = _rows(_unwrap(r[2])).map((j) => _fromJson(j, types)).toList();
    final total = _count(_unwrap(r[0]));
    return BatteryMovementPage(
      items: items,
      // Fall back to what we hold when the count call returns nothing usable.
      total: total > 0 ? total : pageNumber * pageSize + items.length,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<BatteryMovementQuery>> inProgressQueries() async {
    // No paging: the service returns every running query at once.
    final r = await Future.wait<Object?>([
      _api.call(
        'batteryMovement.list',
        query: {
          'batteryType': '$batteryType',
          'queryType': _queryType,
          'queryStatus': _inProgressStatus,
        },
      ),
      _loadProgramTypes(),
    ]);
    _log('inProgress', r[0]);
    final types = r[1]! as Map<int, String>;
    return _rows(_unwrap(r[0])).map((j) => _fromJson(j, types)).toList();
  }

  @override
  Future<List<BatteryMovementQuery>> relatedQueries(
    BatteryMovementRequest request,
  ) async {
    // `GET /BatteryMovementReport/BatteryQuery` — the BDD tool's duplicate
    // check, called when a request is submitted.
    final r = await Future.wait<Object?>([
      _api.call(
        'batteryMovement.related',
        query: {
          'serialNumber': request.serialNumber.trim(),
          'startTime': '${request.startEpochSeconds}',
          'endTime': '${request.endEpochSeconds}',
        },
      ),
      _loadProgramTypes(),
    ]);
    _log('related', r[0]);
    final types = r[1]! as Map<int, String>;
    return _rows(_unwrap(r[0])).map((j) => _fromJson(j, types)).toList();
  }

  @override
  Future<void> requestData(BatteryMovementRequest request) async {
    // The same body the BDD tool posts when "Proceed" is pressed. A 200 only
    // means the query was accepted — a rejection (e.g. the daily limit) shows
    // up later as a failed query with its reason in `remark`.
    final res = await _api.call(
      'batteryMovement.create',
      body: {
        'batterySerialNumber': request.serialNumber.trim(),
        'batteryTypeId': batteryType,
        'queryStatus': 1,
        'queryType': _queryType,
        'startTime': request.startEpochSeconds,
        'endTime': request.endEpochSeconds,
        'timeTaken': 0,
        'createdBy': request.requestedBy,
        'modifiedBy': request.requestedBy,
        'mailId': request.email,
      },
    );
    _log('create', res);
    _unwrap(res); // throws when the service answers isError: true
  }

  @override
  Future<List<BatterySuggestion>> searchBatteries(String text) async {
    // Battery Master `SearchBattery?text=` — serials are matched upper-case.
    // Response: {result: [{batterySerialNumber, tiuSerialNumber, …}]}.
    final res = await _api.call(
      'battery.searchBatteries',
      query: {'text': text.trim().toUpperCase()},
    );
    _log('searchBatteries', res);
    return [
      for (final row in _rows(_unwrap(res)))
        if ('${row['batterySerialNumber'] ?? ''}'.isNotEmpty)
          BatterySuggestion(
            serialNumber: '${row['batterySerialNumber']}',
            tiuSerialNumber: '${row['tiuSerialNumber'] ?? ''}',
          ),
    ];
  }

  /// ProgramType `code → description`, fetched once. Never throws: a failure
  /// yields an empty map (the caller falls back to [fallbackCategory]) and is
  /// retried on the next load.
  Future<Map<int, String>> _loadProgramTypes() =>
      _programTypes ??= _api.call('programType.list').then((res) {
        _log('programType', res);
        return {
          for (final row in _rows(_unwrap(res)))
            if (row['code'] is num && '${row['description'] ?? ''}'.isNotEmpty)
              (row['code'] as num).toInt(): '${row['description']}',
        };
      }).catchError((Object e) {
        _programTypes = null;
        _log('programType failed', e);
        return <int, String>{};
      });

  void _log(String what, Object? res) =>
      developer.log('[$what] $res', name: 'ApiBatteryMovementRepository');

  // --- parsing -----------------------------------------------------------------

  /// Returns the envelope's `result`, and turns `isError: true` into an
  /// exception. Any other shape passes through untouched.
  static Object? _unwrap(Object? res) {
    if (res is Map && res.containsKey('isError')) {
      if (res['isError'] == true) {
        throw ApiException(
          '${res['message'] ?? 'Battery movement report failed'}',
          statusCode: (res['statusCode'] as num?)?.toInt(),
        );
      }
      if (res.containsKey('result')) return res['result'];
    }
    return res;
  }

  /// Epoch numbers (seconds, as the BDD API sends them — or milliseconds), or
  /// ISO-8601 text.
  static DateTime? _parseDate(Object? v) {
    if (v == null) return null;
    num? n = v is num ? v : null;
    if (v is String) n = num.tryParse(v.trim());
    if (n != null) {
      final ms = n.abs() < 100000000000 ? n * 1000 : n; // seconds vs millis
      return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true);
    }
    return v is String ? DateTime.tryParse(v) : null;
  }

  /// The rows: a bare array, or one under a common envelope key.
  static List<Map<String, dynamic>> _rows(Object? res) {
    Iterable<dynamic> list = const [];
    if (res is List) {
      list = res;
    } else if (res is Map) {
      for (final key in const ['items', 'data', 'result', 'results']) {
        final v = res[key];
        if (v is List) {
          list = v;
          break;
        }
      }
    }
    return list
        .whereType<Map<dynamic, dynamic>>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// A count that may arrive as a number, a numeric string, or inside an object.
  static int _count(Object? res) {
    if (res is num) return res.toInt();
    if (res is String) return int.tryParse(res.trim()) ?? 0;
    if (res is Map) {
      for (final key in const [
        'totalCount',
        'count',
        'total',
        'data',
        'result',
      ]) {
        if (res.containsKey(key)) return _count(res[key]);
      }
    }
    return 0;
  }

  BatteryMovementQuery _fromJson(
    Map<String, dynamic> j,
    Map<int, String> types,
  ) {
    String s(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v != null && '$v'.isNotEmpty) return '$v';
      }
      return '';
    }

    final typeId = (j['batteryTypeId'] as num?)?.toInt();
    final status = (j['queryStatus'] as num?)?.toInt();

    return BatteryMovementQuery(
      id: s(const ['id']),
      category: s(const ['category']).isNotEmpty
          ? s(const ['category'])
          : (typeId == null
              ? ''
              : (types[typeId] ??
                  (typeId == batteryType ? fallbackCategory : 'Type $typeId'))),
      serialNumber: s(const ['batterySerialNumber', 'serialNumber']),
      startTime: _parseDate(j['startTime']),
      endTime: _parseDate(j['endTime']),
      // Seconds. (An older shape of the endpoint called this `taktTime`.)
      timeTaken: _timeTaken(j['timeTaken'] ?? j['taktTime']),
      // Seconds the service expects the query to take (shown while running).
      estimatedTime: _timeTaken(j['expectedTime']),
      createdAt: _parseDate(j['createdDate']),
      updatedAt: _parseDate(j['modifiedDate']),
      statusCode: status,
      // `remark` is "Success", or the reason no report was produced.
      remarks: s(const ['remark', 'remarks']),
      reportUrl: _safeReportUrl(j['reportUrl']),
    );
  }

  /// The report link, only when it is an https URL — it is opened in the
  /// device's browser, so nothing else is accepted.
  static String? _safeReportUrl(Object? v) {
    final url = v is String ? v.trim() : '';
    return url.toLowerCase().startsWith('https://') ? url : null;
  }

  /// Seconds as `hh:mm:ss` (hours may exceed 24 — some rows carry a very long
  /// takt time, which the BDD tool shows the same way). Text is kept as is.
  static String _timeTaken(Object? v) {
    if (v == null) return '';
    if (v is num) {
      final d = Duration(seconds: v.round());
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return '$v';
  }
}
