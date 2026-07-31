import 'ticket.dart';

/// One page of the assigned-tickets list (`GET /tickets?page=&pageSize=`).
///
/// The home list pages as the agent scrolls, so the presentation layer needs
/// more than the tickets themselves — it needs to know whether another request
/// is worth making. That is what this carries alongside [items].
class TicketPage {
  const TicketPage({
    required this.items,
    required this.page,
    required this.pageSize,
    this.total,
  });

  /// No tickets and nothing further to fetch — the state before a first load.
  static const empty = TicketPage(items: [], page: 0, pageSize: 0, total: 0);

  /// The tickets in this window, in the order the backend returned them.
  final List<Ticket> items;

  /// 1-based index of the window this is.
  final int page;

  /// Window size that was requested.
  final int pageSize;

  /// Total matching tickets server-side, when the envelope reported it. Null
  /// when it did not — [hasMore] then falls back to a full-page heuristic.
  final int? total;

  /// Whether another page is worth fetching.
  ///
  /// With a [total] the answer is exact. Without one, a window that came back
  /// full is assumed to have a successor: paging then ends on the first
  /// short (or empty) page, at the cost of one wasted request when the last
  /// page happens to be exactly [pageSize] long.
  bool get hasMore {
    if (items.isEmpty || pageSize <= 0) return false;
    final t = total;
    if (t != null) return page * pageSize < t;
    return items.length >= pageSize;
  }
}
