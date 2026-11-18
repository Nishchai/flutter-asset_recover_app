import '../../core/error/failure.dart';
import '../../core/error/result.dart';
import '../entities/battery_movement_query.dart';
import '../entities/battery_movement_request.dart';
import '../entities/battery_suggestion.dart';
import '../repositories/battery_movement_repository.dart';
import 'usecase.dart';

class BatteryMovementParams {
  const BatteryMovementParams({
    this.serialNumber,
    this.pageNumber = 0,
    this.pageSize = 20,
  });

  final String? serialNumber;
  final int pageNumber;
  final int pageSize;
}

/// Loads one page of completed Battery Movement Report queries.
class GetBatteryMovementQueriesUseCase
    implements UseCase<BatteryMovementPage, BatteryMovementParams> {
  GetBatteryMovementQueriesUseCase(this._repo);
  final BatteryMovementRepository _repo;

  @override
  Future<Result<BatteryMovementPage>> call(BatteryMovementParams params) =>
      Result.guard(
        () => _repo.completedQueries(
          serialNumber: params.serialNumber,
          pageNumber: params.pageNumber,
          pageSize: params.pageSize,
        ),
        onError: failureFrom,
      );
}

/// The report queries that are still running.
class GetInProgressMovementQueriesUseCase
    implements UseCase<List<BatteryMovementQuery>, NoParams> {
  GetInProgressMovementQueriesUseCase(this._repo);
  final BatteryMovementRepository _repo;

  @override
  Future<Result<List<BatteryMovementQuery>>> call(NoParams params) =>
      Result.guard(_repo.inProgressQueries, onError: failureFrom);
}

/// Existing queries for the same battery and window, shown before a new
/// request is created.
class GetRelatedMovementQueriesUseCase
    implements UseCase<List<BatteryMovementQuery>, BatteryMovementRequest> {
  GetRelatedMovementQueriesUseCase(this._repo);
  final BatteryMovementRepository _repo;

  @override
  Future<Result<List<BatteryMovementQuery>>> call(
    BatteryMovementRequest request,
  ) =>
      Result.guard(() => _repo.relatedQueries(request), onError: failureFrom);
}

/// Type-ahead lookup of batteries by serial number.
class SearchBatteriesUseCase
    implements UseCase<List<BatterySuggestion>, String> {
  SearchBatteriesUseCase(this._repo);
  final BatteryMovementRepository _repo;

  @override
  Future<Result<List<BatterySuggestion>>> call(String text) =>
      Result.guard(() => _repo.searchBatteries(text), onError: failureFrom);
}

/// Raises a new movement-data request ("Request Data").
class RequestBatteryMovementDataUseCase
    implements UseCase<void, BatteryMovementRequest> {
  RequestBatteryMovementDataUseCase(this._repo);
  final BatteryMovementRepository _repo;

  @override
  Future<Result<void>> call(BatteryMovementRequest request) =>
      Result.guard(() => _repo.requestData(request), onError: failureFrom);
}
