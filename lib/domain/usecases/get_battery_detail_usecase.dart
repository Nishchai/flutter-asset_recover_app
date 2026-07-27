import '../../core/error/result.dart';
import '../entities/battery_detail.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Fetches live battery telemetry from the Battery Master API
/// (`battery.getBatteryDetails`) by the ticket's [params] = `bpId`. Used on the
/// BP detail screen to surface the customer card's "Last Seen" (last lat/long)
/// and "Last TIU" (last TIU timestamp). Resolves to null when the service
/// returns no telemetry row.
class GetBatteryDetailUseCase implements UseCase<BatteryDetail?, String> {
  GetBatteryDetailUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<BatteryDetail?>> call(String bpId) =>
      Result.guard(() => _repo.batteryDetail(bpId));
}
