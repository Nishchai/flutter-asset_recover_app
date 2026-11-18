import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_request.dart';
import 'package:asset_recovery_app/domain/entities/battery_suggestion.dart';
import 'package:asset_recovery_app/domain/usecases/battery_movement_usecases.dart';
import 'package:asset_recovery_app/domain/usecases/usecase.dart';
import 'package:flutter/foundation.dart';

/// State for the Battery Movement Report screen: the completed-queries page
/// (with serial search, paging and page size), the running queries, and the
/// "Request Data" flow (related-queries check, then create).
class BatteryMovementProvider extends ChangeNotifier {
  BatteryMovementProvider({
    required GetBatteryMovementQueriesUseCase getQueries,
    required GetInProgressMovementQueriesUseCase getInProgress,
    required GetRelatedMovementQueriesUseCase getRelated,
    required RequestBatteryMovementDataUseCase requestData,
    required SearchBatteriesUseCase searchBatteries,
    int pageSize = 20,
  })  : _getQueries = getQueries,
        _getInProgress = getInProgress,
        _getRelated = getRelated,
        _requestData = requestData,
        _searchBatteries = searchBatteries,
        _pageSize = pageSize,
        _page = BatteryMovementPage.empty(pageSize: pageSize);

  /// A serial search below this length is rejected, as on the BDD tool.
  static const int minSearchLength = 4;

  /// Page sizes offered in the picker.
  static const List<int> pageSizes = [10, 20, 50, 100];

  final GetBatteryMovementQueriesUseCase _getQueries;
  final GetInProgressMovementQueriesUseCase _getInProgress;
  final GetRelatedMovementQueriesUseCase _getRelated;
  final RequestBatteryMovementDataUseCase _requestData;
  final SearchBatteriesUseCase _searchBatteries;

  BatteryMovementPage _page;
  int _pageNumber = 0;
  int _pageSize;
  String _serial = '';
  List<BatteryMovementQuery>? _inProgress;
  bool _loading = false;
  String? _error;

  /// Guards against a slow earlier response overwriting a newer one.
  int _requestId = 0;

  List<BatteryMovementQuery> get items => _page.items;
  int get total => _page.total;
  int get pageNumber => _pageNumber;
  int get pageSize => _pageSize;
  String get serial => _serial;
  bool get isSearching => _serial.isNotEmpty;

  /// Queries still running. Empty until the first load arrives (or when it
  /// failed); see [inProgressLoaded].
  List<BatteryMovementQuery> get inProgress => _inProgress ?? const [];

  /// False until the in-progress list has loaded at least once.
  bool get inProgressLoaded => _inProgress != null;
  int get inProgressCount => inProgress.length;
  bool get loading => _loading;
  String? get error => _error;

  /// 1-based index of the first / last row shown, 0 when the page is empty.
  int get fromIndex => items.isEmpty ? 0 : _pageNumber * _pageSize + 1;
  int get toIndex => items.isEmpty ? 0 : _pageNumber * _pageSize + items.length;

  bool get hasPrevious => _pageNumber > 0;

  /// Whether the service reported a total (search results come without one).
  bool get totalKnown => _page.totalKnown;

  /// With a known total, more rows exist past this page. Without one, a full
  /// page is the only hint there may be another.
  bool get hasNext => _page.totalKnown
      ? (_pageNumber + 1) * _pageSize < _page.total
      : items.length >= _pageSize;

  /// True when [raw] is long enough to search for.
  static bool isValidSearch(String raw) => raw.trim().length >= minSearchLength;

  /// First load, and pull-to-refresh: reloads the current page and the counter.
  Future<void> load() => Future.wait([_loadPage(), _loadInProgress()]);

  /// Runs a serial search from the first page. Returns false — without
  /// searching — when [raw] is too short.
  Future<bool> search(String raw) async {
    if (!isValidSearch(raw)) return false;
    _serial = raw.trim();
    _pageNumber = 0;
    await _loadPage();
    return true;
  }

  Future<void> clearSearch() async {
    if (_serial.isEmpty) return;
    _serial = '';
    _pageNumber = 0;
    await _loadPage();
  }

  Future<void> nextPage() async {
    if (!hasNext || _loading) return;
    _pageNumber++;
    await _loadPage();
  }

  Future<void> previousPage() async {
    if (!hasPrevious || _loading) return;
    _pageNumber--;
    await _loadPage();
  }

  Future<void> setPageSize(int size) async {
    if (size == _pageSize) return;
    _pageSize = size;
    _pageNumber = 0;
    await _loadPage();
  }

  Future<void> _loadPage() async {
    final id = ++_requestId;
    _loading = true;
    _error = null;
    notifyListeners();

    final result = await _getQueries(
      BatteryMovementParams(
        serialNumber: _serial.isEmpty ? null : _serial,
        pageNumber: _pageNumber,
        pageSize: _pageSize,
      ),
    );
    if (id != _requestId) return; // superseded by a newer request

    result.fold(
      (page) => _page = page,
      (failure) {
        _error = failure.message;
        // Keep the rows already on screen rather than blanking them, and put
        // the page counters back to match them.
        _pageNumber = _page.pageNumber;
        _pageSize = _page.pageSize;
      },
    );
    _loading = false;
    notifyListeners();
  }

  Future<void> _loadInProgress() async {
    final result = await _getInProgress(const NoParams());
    // A failed refresh keeps what is already on screen.
    _inProgress = result.valueOrNull ?? _inProgress;
    notifyListeners();
  }

  // --- Request Data ------------------------------------------------------------

  /// The serial-number type-ahead: batteries matching [text]. Nothing is asked
  /// of the service below [minSearchLength] characters. [error] is set when the
  /// lookup itself failed (so the form can say so instead of "no matches").
  Future<({List<BatterySuggestion> items, String? error})> findBatteries(
    String text,
  ) async {
    if (!isValidSearch(text)) {
      return (items: const <BatterySuggestion>[], error: null);
    }
    final result = await _searchBatteries(text);
    return result.fold(
      (items) => (items: items, error: null),
      (failure) => (items: const <BatterySuggestion>[], error: failure.message),
    );
  }

  /// The duplicate check before a request is created: existing queries for the
  /// same battery and window. [error] is set when the check itself failed.
  Future<({List<BatteryMovementQuery> related, String? error})> checkRelated(
    BatteryMovementRequest request,
  ) async {
    final result = await _getRelated(request);
    return result.fold(
      (rows) => (related: rows, error: null),
      (failure) =>
          (related: const <BatteryMovementQuery>[], error: failure.message),
    );
  }

  /// Creates the request, then reloads the report (completed list, in-progress
  /// list and total) so the new query appears as running. Returns the error
  /// message, or null on success.
  Future<String?> submitRequest(BatteryMovementRequest request) async {
    final result = await _requestData(request);
    final failure = result.failureOrNull;
    if (failure != null) return failure.message;
    await load();
    return null;
  }
}
