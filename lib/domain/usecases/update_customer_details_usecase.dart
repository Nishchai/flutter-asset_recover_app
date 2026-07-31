import '../../core/error/result.dart';
import '../entities/customer_details_update.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

/// Pushes the customer-detail edits made on the Visit Customer Address screen
/// to the customers service (`customer.updateByPhone`). Called on Save.
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
