import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:asset_recovery_app/domain/repositories/ticket_repository.dart';
import 'package:asset_recovery_app/domain/usecases/usecase.dart';

/// Fetches the BP's latest live location from the BP Live API (Rule 8b),
/// which may differ from the cached [Battery.lastKnownLocation].
class GetLiveLocationUseCase implements UseCase<GeoPoint, String> {
  GetLiveLocationUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<GeoPoint>> call(String bpId) => Result.guard(() => _repo.liveLocation(bpId));
}
