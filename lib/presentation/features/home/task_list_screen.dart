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
/// assigned tickets (All / Open / In Progress / Pending).
class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  TicketFilter _filter = TicketFilter.allTasks;

  static const _filterOrder = [
    TicketFilter.allTasks,
    TicketFilter.inProgress,
    TicketFilter.completed,
  ];

  static const _filterKey = {
    TicketFilter.allTasks: 'filter.allTasks',
    TicketFilter.inProgress: 'filter.inProgress',
    TicketFilter.completed: 'filter.completed',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tickets = context.read<TicketProvider>();
      final agent = context.read<AuthProvider>().agent;
      if (agent != null && !tickets.hasLoaded && !tickets.loading) {
        tickets.load(agent.id);
      }
    });
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

  Future<void> _onToggleShift(bool turnOn) async {
    final shift = context.read<ShiftProvider>();
    if (turnOn) {
      shift.startShift();
      return;
    }
    // Turning the shift OFF requires the end-of-shift OTP (daily logout flow).
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
            assigned: tickets.assignedCount,
            inProgress: tickets.inProgressCount,
            pending: tickets.pendingCount,
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
                    child: tickets.loading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildList(context, tickets, palette, services),
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
    if (items.isEmpty) {
      return Center(
        child: Text(l.t('home.empty'), style: TextStyle(color: palette.muted)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
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
