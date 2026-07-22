import '../../core/error/result.dart';
import '../repositories/ticket_repository.dart';
import 'usecase.dart';

class ValidateScanParams {
  const ValidateScanParams({
    required this.ticketId,
    required this.bpId,
    required this.scannedSerial,
  });
  final String ticketId;
  final String bpId;
  final String scannedSerial;
}

/// Validates a scanned BP serial against the assigned ticket (PRD §4.9 / QR).
class ValidateBatteryScanUseCase implements UseCase<bool, ValidateScanParams> {
  ValidateBatteryScanUseCase(this._repo);
  final TicketRepository _repo;

  @override
  Future<Result<bool>> call(ValidateScanParams params) => Result.guard(
        () => _repo.validateScan(
            params.ticketId, params.bpId, params.scannedSerial,),
      );
}
