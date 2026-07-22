import '../../core/error/result.dart';
import '../entities/customer.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class UpdateCustomerParams {
  const UpdateCustomerParams(this.bpId, this.customer);
  final String bpId;
  final Customer customer;
}

/// Updates customer contact/address against a BP (PRD §5.2.2).
/// Returns `true` on success (avoids a `void` result payload).
class UpdateCustomerUseCase implements UseCase<bool, UpdateCustomerParams> {
  UpdateCustomerUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(UpdateCustomerParams params) => Result.guard(() async {
        await _repo.updateCustomer(params.bpId, params.customer);
        return true;
      });
}
