import '../../core/error/result.dart';
import '../entities/customer_details_update.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Pushes customer-detail edits to the customers service (`customer.updateById`,
/// falling back to `customer.updateByPhone`). Called on Save from the Visit
/// Customer Address screen (address components + alternate number) and from the
/// Call Customer screen (the updated mobile alone).
/// Returns `true` on success (avoids a `void` result payload).
class UpdateCustomerDetailsUseCase
    implements UseCase<bool, CustomerDetailsUpdate> {
  UpdateCustomerDetailsUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(CustomerDetailsUpdate params) =>
      Result.guard(() async {
        await _repo.updateCustomerByPhone(params);
        return true;
      });
}
