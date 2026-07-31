import 'package:asset_recovery_app/domain/entities/enums.dart';
import 'package:asset_recovery_app/domain/entities/ticket.dart';
import 'package:asset_recovery_app/domain/entities/ticket_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// [TicketPage.hasMore] is what stops the home list from paging forever, so its
/// two modes — an exact `total` from the backend, and the full-window fallback
/// when the envelope omits one — are pinned here.
void main() {
  List<Ticket> tickets(int n) => List.generate(
        n,
        (i) => Ticket(
          ticketId: 'TKT-$i',
          status: TicketStatus.assigned,
          createdAt: DateTime.utc(2026, 7, 27),
          assignedAgentId: 'FA-RM-01',
          cluster: 'Bengaluru South',
          reason: '',
          batteries: const [],
        ),
      );

  group('with a total reported', () {
    test('more pages remain while the window has not reached the total', () {
      final page = TicketPage(
          items: tickets(20), page: 1, pageSize: 20, total: 45,);
      expect(page.hasMore, isTrue);
    });

    test('the last full window that exactly covers the total ends paging', () {
      final page = TicketPage(
          items: tickets(20), page: 2, pageSize: 20, total: 40,);
      expect(page.hasMore, isFalse);
    });

    test('a short final window ends paging', () {
      final page = TicketPage(
          items: tickets(5), page: 3, pageSize: 20, total: 45,);
      expect(page.hasMore, isFalse);
    });
  });

  group('without a total', () {
    test('a full window is assumed to have a successor', () {
      final page = TicketPage(items: tickets(20), page: 1, pageSize: 20);
      expect(page.hasMore, isTrue);
    });

    test('a short window ends paging', () {
      final page = TicketPage(items: tickets(7), page: 2, pageSize: 20);
      expect(page.hasMore, isFalse);
    });
  });

  test('an empty window always ends paging', () {
    expect(
      const TicketPage(items: [], page: 4, pageSize: 20, total: 999).hasMore,
      isFalse,
    );
    expect(TicketPage.empty.hasMore, isFalse);
  });
}
