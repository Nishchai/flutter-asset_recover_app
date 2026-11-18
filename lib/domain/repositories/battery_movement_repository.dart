import '../entities/battery_movement_query.dart';
import '../entities/battery_movement_request.dart';
import '../entities/battery_suggestion.dart';

/// Source of the Battery Movement Report. Implemented by the real backend and
/// by a seeded in-memory mock (used when `useMockData` is on).
abstract class BatteryMovementRepository {
  /// Completed queries, newest first. [serialNumber] filters to one battery
  /// (the caller enforces the 4-character minimum). [pageNumber] is zero-based.
  Future<BatteryMovementPage> completedQueries({
    String? serialNumber,
    int pageNumber = 0,
    int pageSize = 20,
  });

  /// Queries that have been requested but whose report is not ready yet.
  Future<List<BatteryMovementQuery>> inProgressQueries();

  /// Existing queries for the same battery and window as [request]. The BDD
  /// tool shows these before a new query is created, as a duplicate check.
  Future<List<BatteryMovementQuery>> relatedQueries(
    BatteryMovementRequest request,
  );

  /// Raises a new movement-data query. It shows up as in progress until the
  /// service has produced the report.
  Future<void> requestData(BatteryMovementRequest request);

  /// Batteries whose serial matches [text] — the type-ahead on the Request
  /// Data form. The caller enforces the 4-character minimum.
  Future<List<BatterySuggestion>> searchBatteries(String text);
}
