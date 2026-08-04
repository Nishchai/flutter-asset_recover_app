import 'dart:async';

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/features/home/widgets/end_shift_sheet.dart';
import 'package:asset_recovery_app/presentation/features/home/widgets/shift_header.dart';
import 'package:asset_recovery_app/presentation/features/home/widgets/ticket_card.dart';
import 'package:asset_recovery_app/presentation/features/ticket_detail/ticket_detail_screen.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:asset_recovery_app/presentation/state/ticket_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Home screen (Figma): dark shift header + stats, then a filterable list of
/// assigned tickets (All Tasks / In Progress-Open / Completed).
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  TicketFilter _filter = TicketFilter.allTasks;

  /// Drives the scroll paging: the next page is requested once the agent is
  /// within this many pixels of the end of the loaded tickets, so the following
  /// batch is usually already in place by the time the last card is reached.
  static const double _loadMoreThresholdPx = 320;

  final ScrollController _scroll = ScrollController();

  static const _filterOrder = [
    TicketFilter.allTasks,
    TicketFilter.inProgress,
    TicketFilter.completed,
  ];

  static const _filterKey = {
    TicketFilter.allTasks: 'filter.allTasks',
    TicketFilter.inProgress: 'filter.inProgressOpen',
    TicketFilter.completed: 'filter.completed',
  };

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tickets = context.read<TicketProvider>();
      final agent = context.read<AuthProvider>().agent;
      // Reload when the list has never been loaded OR belongs to a different
      // agent — the provider survives a logout, so a fresh sign-in must not
      // keep showing (and refreshing) the previous agent's tickets.
      final staleForThisAgent =
          tickets.hasLoaded && tickets.loadedAgentId != agent?.id;
      if (agent != null &&
          (!tickets.hasLoaded || staleForThisAgent) &&
          !tickets.loading) {
        tickets.load(agent.id);
      }
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Requests the next page once the agent scrolls within
  /// [_loadMoreThresholdPx] of the end of the loaded tickets. The provider
  /// itself ignores the call when a page is already in flight or the server has
  /// no more, so this can fire on every scroll notification safely.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThresholdPx) {
      return;
    }
    unawaited(context.read<TicketProvider>().loadMore());
  }

  /// A filtered tab can show only a handful of the tickets loaded so far (two
  /// Completed out of a page of twenty, say), leaving the list too short to
  /// scroll — and with nothing to scroll there is no gesture to trigger the
  /// next page, so the tab would dead-end. Top it up until the list can scroll
  /// or the server runs out of pages.
  void _topUpIfNotScrollable() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent > 0) return;
    unawaited(context.read<TicketProvider>().loadMore());
  }

  static const _sortLabelKeys = {
    'distance': 'opt.sort.distance',
    'pendingDuration': 'opt.sort.pendingDuration',
    'slaRemaining': 'opt.sort.slaRemaining',
  };

  Future<void> _showSortSheet(
      BuildContext context, TicketProvider tickets, AppPalette palette,) {
    final l = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(l.t('sort.title'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,),),
            ),
            for (final sort in tickets.availableSorts)
              ListTile(
                title: Text(l.t(_sortLabelKeys[sort] ?? sort)),
                trailing:
                    sort == tickets.sort ? Icon(Icons.check, color: palette.primary) : null,
                onTap: () {
                  tickets.setSort(sort);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Pull-to-refresh on the My Tickets list — re-runs the tickets API for the
  /// signed-in agent. The provider swaps in whatever came back (list, header
  /// counts and filter tabs all rebuild off it); a failed call keeps the
  /// current list and is surfaced as a snack bar.
  Future<void> _onRefreshTickets() async {
    final tickets = context.read<TicketProvider>();
    final agent = context.read<AuthProvider>().agent;
    if (agent == null) return;
    await tickets.refresh(agent.id);
    if (!mounted) return;
    final error = tickets.error;
    if (error != null) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.isEmpty ? l.t('common.error') : error)),
      );
    }
  }

  Future<void> _onToggleShift(bool turnOn) async {
    final shift = context.read<ShiftProvider>();
    if (turnOn) {
      shift.startShift();
      return;
    }
    // Turning the shift OFF requires the end-of-shift OTP (daily logout flow).
    // Flipping the toggle only OPENS the sheet — it never calls the SMS gateway.
    // The sheet requests the code itself once it is on screen, so a flip the
    // agent immediately backs out of costs nothing.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const EndShiftSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final services = context.read<AppServices>();
    final agent = context.read<AuthProvider>().agent!;
    final tickets = context.watch<TicketProvider>();
    final shift = context.watch<ShiftProvider>();

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          ShiftHeader(
            agent: agent,
            palette: palette,
            shiftActive: shift.active,
            assigned: tickets.totalCount,
            inProgressOrOpen: tickets.inProgressOrOpenCount,
            closed: tickets.closedCount,
            onToggleShift: _onToggleShift,
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                    child: Row(
                      children: [
                        Text(l.t('home.myTickets'),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold,),),
                        const Spacer(),
                        InkWell(
                          onTap: () => _showSortSheet(context, tickets, palette),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.filter_list, color: palette.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _FilterBar(
                    order: _filterOrder,
                    selected: _filter,
                    labelOf: (f) => l.t(_filterKey[f]!),
                    palette: palette,
                    onSelect: (f) => setState(() => _filter = f),
                  ),
                  Expanded(
                    // Pull-to-refresh starts at the top of the My Tickets list
                    // (just under the header + filter tabs) and re-calls the
                    // tickets API.
                    child: tickets.loading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                            onRefresh: _onRefreshTickets,
                            color: palette.primary,
                            child:
                                _buildList(context, tickets, palette, services),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, TicketProvider tickets,
      AppPalette palette, AppServices services,) {
    final l = AppLocalizations.of(context);
    final items = tickets.ticketsFor(_filter);

    // Whatever this tab shows, the loaded window may not cover it — check after
    // layout whether more pages are needed to make the list scrollable at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _topUpIfNotScrollable();
    });

    if (items.isEmpty) {
      // Scrollable even when empty, so the empty state can still be pulled
      // down to refresh. Keeps the controller attached so an empty filtered tab
      // (its matches sitting on a page not fetched yet) can still page on.
      return ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 24),
        children: [
          Center(
            child: tickets.loadingMore
                ? CircularProgressIndicator(color: palette.primary)
                : Text(l.t('home.empty'),
                    style: TextStyle(color: palette.muted),),
          ),
        ],
      );
    }

    // One trailing slot for the paging footer, whenever there is a page to
    // fetch, one in flight, or a failed attempt to retry.
    final showFooter = tickets.hasMorePages ||
        tickets.loadingMore ||
        tickets.loadMoreError != null;

    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: items.length + (showFooter ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == items.length) {
          return _PagingFooter(
            loading: tickets.loadingMore,
            error: tickets.loadMoreError,
            palette: palette,
            onRetry: () => unawaited(tickets.loadMore()),
          );
        }
        final t = items[i];
        return TicketCard(
          ticket: t,
          slaDays: services.config.slaDays,
          slaWarnDays: services.config.intValue('business.slaWarnDays', fallback: 7),
          palette: palette,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TicketDetailScreen(ticketId: t.ticketId),
            ),
          ),
        );
      },
    );
  }
}

/// Trailing slot of the paged ticket list: a spinner while the next page loads,
/// a retry row when the last attempt failed, and otherwise just enough height
/// to signal that the list continues.
class _PagingFooter extends StatelessWidget {
  const _PagingFooter({
    required this.loading,
    required this.error,
    required this.palette,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(
              error!.isEmpty ? l.t('home.loadMoreFailed') : error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: onRetry,
              child: Text(l.t('common.retry'),
                  style: TextStyle(color: palette.primary),),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: loading
              ? CircularProgressIndicator(
                  strokeWidth: 2.2, color: palette.primary,)
              : null,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.order,
    required this.selected,
    required this.labelOf,
    required this.palette,
    required this.onSelect,
  });

  final List<TicketFilter> order;
  final TicketFilter selected;
  final String Function(TicketFilter) labelOf;
  final AppPalette palette;
  final ValueChanged<TicketFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          for (final f in order) ...[
            GestureDetector(
              onTap: () => onSelect(f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: f == selected ? palette.pillDark : palette.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: f == selected ? palette.pillDark : palette.border,
                  ),
                ),
                child: Text(
                  labelOf(f),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: f == selected ? Colors.white : palette.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
