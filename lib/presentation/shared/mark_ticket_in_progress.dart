import 'dart:developer' as developer;

import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/domain/usecases/update_ticket_status_usecase.dart';

/// Status the ticket moves to the moment the agent starts working the case.
/// The backend's own camelCase vocabulary, sent verbatim — not
/// [TicketStatus.wire]'s snake_case.
const _inProgressStatus = 'inProgress';

/// Ticket numbers with an in-flight `tickets.status` request — guards against a
/// second PATCH from a double tap on Save. Deliberately in-flight only, NOT a
/// once-per-ticket memo: every "agent started working" signal should reach the
/// backend, and the PATCH is idempotent.
final _statusUpdatesInFlight = <String>{};

/// Moves [ticketId] to `inProgress` on the backend (`tickets.status` —
/// `PATCH /tickets/status`, body `{ticketId, status}`).
///
/// Fired only after the Field Agent successfully submits an attempt from one of
/// the action screens — Call Customer, Visit BP Location or Visit Customer
/// Address. Not fired for Update Status, which closes the case rather than
/// starting it.
///
/// [ticketId] is the ticket number shown as "Case ID" on the detail screen.
///
/// Fire-and-forget: navigation must not wait on the network, so a failure is
/// logged rather than surfaced — the attempt submission is what actually
/// records the agent's work.
Future<void> markTicketInProgress(String ticketId) async {
  if (ticketId.isEmpty || _statusUpdatesInFlight.contains(ticketId)) return;
  _statusUpdatesInFlight.add(ticketId);
  try {
    final result = await sl<UpdateTicketStatusUseCase>()(
        UpdateTicketStatusParams(ticketId, _inProgressStatus),);
    if (result.isErr) {
      developer.log(
        'ticket status update failed: ${result.failureOrNull?.message}',
        name: 'MarkTicketInProgress',
      );
    }
  } finally {
    _statusUpdatesInFlight.remove(ticketId);
  }
}
