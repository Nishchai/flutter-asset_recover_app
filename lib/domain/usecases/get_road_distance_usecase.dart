import '../../core/error/result.dart';
import '../entities/geo_point.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Computes the road distance between two locations via the repository.
class RoadDistanceParams {
  const RoadDistanceParams(this.from, this.to);

  final GeoPoint from;
  final GeoPoint to;
}

class GetRoadDistanceUseCase implements UseCase<double, RoadDistanceParams> {
  GetRoadDistanceUseCase(this._repo);

  final TicketRepository _repo;

  @override
  Future<Result<double>> call(RoadDistanceParams params) =>
      Result.guard(() => _repo.roadDistanceKm(params.from, params.to));
}
