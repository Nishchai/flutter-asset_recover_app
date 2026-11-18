import 'dart:math';

import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_request.dart';
import 'package:asset_recovery_app/domain/entities/battery_suggestion.dart';
import 'package:asset_recovery_app/domain/repositories/battery_movement_repository.dart';

/// Seeded in-memory report for mock mode and tests. 131 completed queries
/// (the size of the staging report this feature was modelled on), newest first,
/// plus [inProgress] running ones. [requestData] adds a new running query.
class MockBatteryMovementRepository implements BatteryMovementRepository {
  MockBatteryMovementRepository({
    int seed = 5,
    this.latency = const Duration(milliseconds: 300),
    int inProgress = 1,
    int rows = 131,
  })  : _rows = _seed(Random(seed), rows),
        _running = [
          for (var i = 0; i < inProgress; i++) _runningQuery('seed-$i'),
        ];

  final Duration latency;
  final List<BatteryMovementQuery> _rows;
  final List<BatteryMovementQuery> _running;

  static const _serials = [
    'INSMOMAH1007L14B4213',
    'INSMOMAH5110C17ED713',
    'INSMOMAH1108A25F1013',
    'INSMOMAH2204B33C9A21',
    'INSMOMAH3309D41E7B55',
  ];

  static final _now = DateTime.utc(2026, 11, 11, 10);

  static BatteryMovementQuery _runningQuery(
    String id, {
    String serial = 'INSMOMAH1108A25F1013',
    DateTime? start,
    DateTime? end,
  }) {
    final created = _now.add(const Duration(minutes: 5));
    return BatteryMovementQuery(
      id: id,
      category: 'Wheelers',
      serialNumber: serial,
      startTime: start ?? _now.subtract(const Duration(days: 2)),
      endTime: end ?? _now,
      estimatedTime: '00:10:00',
      createdAt: created,
      updatedAt: created,
      statusCode: BatteryMovementQuery.statusInProgress,
    );
  }

  static List<BatteryMovementQuery> _seed(Random rng, int count) {
    return List.generate(count, (i) {
      final end = _now.subtract(Duration(hours: i * 7 + rng.nextInt(5)));
      final span = Duration(hours: 4 + rng.nextInt(60));
      final took = Duration(seconds: 30 + rng.nextInt(900));
      final created = end.add(Duration(minutes: 1 + rng.nextInt(30)));
      final serial = _serials[rng.nextInt(_serials.length)];
      // Mostly successes; a few failures and no-data results, as in real use.
      final roll = rng.nextInt(12);
      final status = roll == 0
          ? BatteryMovementQuery.statusFailed
          : (roll == 1
              ? BatteryMovementQuery.statusNoData
              : BatteryMovementQuery.statusSuccess);
      return BatteryMovementQuery(
        id: 'mock-${i + 1}',
        category: 'Wheelers',
        serialNumber: serial,
        startTime: end.subtract(span),
        endTime: end,
        timeTaken: _hms(took),
        createdAt: created,
        updatedAt: created.add(const Duration(minutes: 2)),
        statusCode: status,
        remarks: switch (status) {
          BatteryMovementQuery.statusFailed =>
            'Report generation failed: No live data rows with a valid GPS position',
          BatteryMovementQuery.statusNoData =>
            'No BP live data for $serial in the requested window, so no report was created.',
          _ => 'Success',
        },
        reportUrl: status == BatteryMovementQuery.statusSuccess
            ? 'https://example.test/reports/mock-${i + 1}.html'
            : null,
      );
    });
  }

  static String _hms(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    await Future<void>.delayed(latency);
    final needle = serialNumber?.trim().toLowerCase() ?? '';
    final matches = needle.isEmpty
        ? _rows
        : _rows
            .where((r) => r.serialNumber.toLowerCase().contains(needle))
            .toList();
    final start = pageNumber * pageSize;
    final items = start >= matches.length
        ? const <BatteryMovementQuery>[]
        : matches.sublist(start, min(start + pageSize, matches.length));
    return BatteryMovementPage(
      items: items,
      total: matches.length,
      pageNumber: pageNumber,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<BatteryMovementQuery>> inProgressQueries() async {
    await Future<void>.delayed(latency);
    return List.of(_running);
  }

  @override
  Future<List<BatteryMovementQuery>> relatedQueries(
    BatteryMovementRequest request,
  ) async {
    await Future<void>.delayed(latency);
    final serial = request.serialNumber.trim().toLowerCase();
    final from = DateTime.fromMillisecondsSinceEpoch(
      request.startEpochSeconds * 1000,
      isUtc: true,
    );
    final to = DateTime.fromMillisecondsSinceEpoch(
      request.endEpochSeconds * 1000,
      isUtc: true,
    );
    // Same battery, and the windows overlap.
    return _rows
        .where(
          (r) =>
              r.serialNumber.toLowerCase() == serial &&
              r.startTime != null &&
              r.endTime != null &&
              !r.startTime!.isAfter(to) &&
              !r.endTime!.isBefore(from),
        )
        .toList();
  }

  @override
  Future<List<BatterySuggestion>> searchBatteries(String text) async {
    await Future<void>.delayed(latency);
    final needle = text.trim().toUpperCase();
    return [
      for (final s in _serials)
        if (s.contains(needle)) BatterySuggestion(serialNumber: s),
    ];
  }

  @override
  Future<void> requestData(BatteryMovementRequest request) async {
    await Future<void>.delayed(latency);
    final start = DateTime.fromMillisecondsSinceEpoch(
      request.startEpochSeconds * 1000,
      isUtc: true,
    );
    final end = DateTime.fromMillisecondsSinceEpoch(
      request.endEpochSeconds * 1000,
      isUtc: true,
    );
    _running.insert(
      0,
      _runningQuery(
        'req-${_running.length + 1}',
        serial: request.serialNumber.trim(),
        start: start,
        end: end,
      ),
    );
  }
}
