import '../../core/error/result.dart';
import '../entities/geo_point.dart';
import '../entities/ticket.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// M1-02 — location-based pickup: unassigned tickets sitting on the agent's
/// current route that nobody's working yet.
class NearbyUnassignedParams {
  const NearbyUnassignedParams(this.near, this.radiusKm);

  final GeoPoint near;
  final double radiusKm;
}

class GetNearbyUnassignedTicketsUseCase
    implements UseCase<List<Ticket>, NearbyUnassignedParams> {
  GetNearbyUnassignedTicketsUseCase(this._repo);

  final TicketRepository _repo;

  @override
  Future<Result<List<Ticket>>> call(NearbyUnassignedParams params) =>
      Result.guard(() => _repo.nearbyUnassignedTickets(params.near, params.radiusKm));
}

class PickupTicketParams {
  const PickupTicketParams(this.ticketId, this.agentId);

  final String ticketId;
  final String agentId;
}

class PickupTicketUseCase implements UseCase<Ticket, PickupTicketParams> {
  PickupTicketUseCase(this._repo);

  final TicketRepository _repo;

  @override
  Future<Result<Ticket>> call(PickupTicketParams params) =>
      Result.guard(() => _repo.pickupTicket(params.ticketId, params.agentId));
}
