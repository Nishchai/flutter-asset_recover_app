/// One row of the Battery Movement Report: a completed request for a battery's
/// movement history (the "Completed Queries" table on the BDD tool).
class BatteryMovementQuery {
  const BatteryMovementQuery({
    required this.id,
    required this.category,
    required this.serialNumber,
    this.startTime,
    this.endTime,
    this.timeTaken = '',
    this.estimatedTime = '',
    this.createdAt,
    this.updatedAt,
    this.statusCode,
    this.remarks = '',
    this.reportUrl,
  });

  /// `queryStatus` values the service uses.
  static const int statusInProgress = 1;
  static const int statusSuccess = 3;

  /// The report could not be generated (heavy load, daily limit, no valid GPS…);
  /// [remarks] says why.
  static const int statusFailed = 4;

  /// The battery had no live data in the window, so no report was created.
  static const int statusNoData = 5;

  /// Backend identifier of the query, empty when the service sends none.
  final String id;

  /// Vehicle category the battery belongs to, e.g. `Wheelers`.
  final String category;

  /// Battery serial number the movement history was requested for.
  final String serialNumber;

  /// Window of battery movement that was requested.
  final DateTime? startTime;
  final DateTime? endTime;

  /// How long the query took to run, as `hh:mm:ss`.
  final String timeTaken;

  /// How long the service expects the query to take, as `hh:mm:ss` — shown
  /// while a query is still running.
  final String estimatedTime;

  /// When the query was raised / last changed.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// The service's `queryStatus` code (see the `status…` constants), or null
  /// when it sent none.
  final int? statusCode;

  /// The service's own outcome text: `Success`, or the reason a query did not
  /// produce a report (e.g. "No BP live data for … so no report was created.").
  final String remarks;

  /// Where the generated HTML report can be opened. Null when there is none —
  /// the query failed, had no data, or is still running.
  final String? reportUrl;

  bool get succeeded =>
      statusCode == statusSuccess ||
      (statusCode == null && remarks.trim().toLowerCase() == 'success');

  bool get hasReport => reportUrl != null && reportUrl!.isNotEmpty;
}

/// One page of [BatteryMovementQuery] rows plus the total across all pages.
class BatteryMovementPage {
  const BatteryMovementPage({
    required this.items,
    required this.total,
    required this.pageNumber,
    required this.pageSize,
    this.totalKnown = true,
  });

  const BatteryMovementPage.empty({this.pageSize = 20})
      : items = const [],
        total = 0,
        pageNumber = 0,
        totalKnown = true;

  final List<BatteryMovementQuery> items;

  /// Rows matching the search across every page. When [totalKnown] is false
  /// (the search endpoint reports no count) this is only the rows seen so far.
  final int total;

  /// False when the service gave no total, so "more pages" can only be inferred
  /// from a full page.
  final bool totalKnown;

  /// Zero-based, as the service expects.
  final int pageNumber;
  final int pageSize;
}
