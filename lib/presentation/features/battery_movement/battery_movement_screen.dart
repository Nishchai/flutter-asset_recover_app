import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/presentation/features/battery_movement/movement_format.dart';
import 'package:asset_recovery_app/presentation/features/battery_movement/request_data_sheet.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/status_badge.dart';
import 'package:asset_recovery_app/presentation/state/battery_movement_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Battery Movement Report: completed movement-history queries with serial
/// search, paging and the in-progress counter. Opened from the home screen's
/// info menu ([showBatteryMovementMenu]).
class BatteryMovementScreen extends StatelessWidget {
  const BatteryMovementScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      ChangeNotifierProvider<BatteryMovementProvider>(
        create: (_) => sl<BatteryMovementProvider>()..load(),
        child: const _BatteryMovementView(),
      );
}

class _BatteryMovementView extends StatefulWidget {
  const _BatteryMovementView();

  @override
  State<_BatteryMovementView> createState() => _BatteryMovementViewState();
}

class _BatteryMovementViewState extends State<_BatteryMovementView> {
  final _searchController = TextEditingController();
  bool _tooShort = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _submitSearch() async {
    final provider = context.read<BatteryMovementProvider>();
    FocusScope.of(context).unfocus();
    final started = await provider.search(_searchController.text);
    if (!mounted) return;
    setState(() => _tooShort = !started);
  }

  Future<void> _clearSearch() async {
    _searchController.clear();
    setState(() => _tooShort = false);
    await context.read<BatteryMovementProvider>().clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final provider = context.watch<BatteryMovementProvider>();

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          _Header(title: l.t('movement.title'), palette: palette),
          Expanded(
            child: RefreshIndicator(
              onRefresh: provider.load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _LimitNote(text: l.t('movement.limitNote'), palette: palette),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: () => showRequestDataSheet(context, provider),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primary,
                        foregroundColor: palette.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(l.t('movement.requestData')),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _InProgressSection(
                    provider: provider,
                    palette: palette,
                    l: l,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l.t('movement.completed'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SearchBar(
                    controller: _searchController,
                    palette: palette,
                    label: l.t('movement.searchLabel'),
                    hint: l.t('movement.searchHint'),
                    errorText:
                        _tooShort ? l.t('movement.searchTooShort') : null,
                    clearTooltip: l.t('movement.clearSearch'),
                    showClear: provider.isSearching,
                    onSubmit: _submitSearch,
                    onClear: _clearSearch,
                  ),
                  const SizedBox(height: 14),
                  _Toolbar(provider: provider, palette: palette),
                  const SizedBox(height: 10),
                  if (provider.loading && provider.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: LinearProgressIndicator(
                        color: palette.primary,
                        backgroundColor: palette.chipBg,
                        minHeight: 3,
                      ),
                    ),
                  ..._body(l, palette, provider),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l,
    AppPalette palette,
    BatteryMovementProvider provider,
  ) {
    if (provider.items.isEmpty) {
      if (provider.loading) {
        return [
          const SizedBox(height: 40),
          Center(child: CircularProgressIndicator(color: palette.primaryDark)),
        ];
      }
      if (provider.error != null) {
        return [
          _Message(
            icon: Icons.cloud_off_outlined,
            text: l.t('movement.loadFailed'),
            palette: palette,
            actionLabel: l.t('movement.retry'),
            onAction: provider.load,
          ),
        ];
      }
      return [
        _Message(
          icon: Icons.inbox_outlined,
          text: provider.isSearching
              ? l.t('movement.emptySearch')
              : l.t('movement.empty'),
          palette: palette,
        ),
      ];
    }
    return [
      if (provider.error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            l.t('movement.loadFailed'),
            style: TextStyle(color: palette.danger, fontSize: 12.5),
          ),
        ),
      for (final q in provider.items) ...[
        _QueryCard(query: q, palette: palette, l: l),
        const SizedBox(height: 10),
      ],
    ];
  }
}

/// Dark hero header with a back arrow, matching the home header.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.palette});
  final String title;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: palette.heroGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 20, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: AppLocalizations.of(context).t('common.back'),
                icon: Icon(Icons.arrow_back, color: palette.onDark),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: palette.onDark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LimitNote extends StatelessWidget {
  const _LimitNote({required this.text, required this.palette});
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.info.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: palette.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: palette.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _dash = movementDash;
String _stamp(DateTime? dt) => movementStamp(dt);

/// Two label/value columns side by side; the second may be omitted.
Widget _fieldPair(
  AppPalette palette,
  String k1,
  String v1,
  String? k2,
  String? v2,
) {
  Widget field(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: palette.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: 12.5, color: palette.onSurface),
          ),
        ],
      );
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: field(k1, v1)),
      const SizedBox(width: 12),
      Expanded(
        child: k2 == null ? const SizedBox() : field(k2, v2 ?? _dash),
      ),
    ],
  );
}

/// "Queries in progress": a title with the running count, then one card per
/// running query. Each card shows a spinner until its report is ready; the
/// list refreshes when the screen opens, on pull-to-refresh and after a new
/// request is created.
class _InProgressSection extends StatelessWidget {
  const _InProgressSection({
    required this.provider,
    required this.palette,
    required this.l,
  });

  final BatteryMovementProvider provider;
  final AppPalette palette;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final running = provider.inProgress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.t('movement.inProgress'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: palette.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: palette.darkSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.darkBorder),
              ),
              child: Text(
                provider.inProgressLoaded ? '${running.length}' : '–',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: palette.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (running.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              l.t('movement.noneInProgress'),
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
          )
        else
          for (final q in running) ...[
            _RunningCard(query: q, palette: palette, l: l),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({
    required this.query,
    required this.palette,
    required this.l,
  });

  final BatteryMovementQuery query;
  final AppPalette palette;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  query.serialNumber.isEmpty ? _dash : query.serialNumber,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: palette.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Spins until the report is generated.
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: palette.primaryDark,
                ),
              ),
            ],
          ),
          if (query.category.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                query.category,
                style: TextStyle(fontSize: 11.5, color: palette.onSurface),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _fieldPair(
            palette,
            l.t('movement.startTime'),
            _stamp(query.startTime),
            l.t('movement.endTime'),
            _stamp(query.endTime),
          ),
          const SizedBox(height: 10),
          _fieldPair(
            palette,
            l.t('movement.createdDate'),
            _stamp(query.createdAt),
            l.t('movement.estimatedTime'),
            query.estimatedTime.isEmpty ? _dash : query.estimatedTime,
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.palette,
    required this.label,
    required this.hint,
    required this.errorText,
    required this.clearTooltip,
    required this.showClear,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final String label;
  final String hint;
  final String? errorText;
  final String clearTooltip;
  final bool showClear;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSubmit(),
                style: TextStyle(color: palette.onSurface),
                decoration: InputDecoration(
                  hintText: hint,
                  errorText: errorText,
                  isDense: true,
                  filled: true,
                  fillColor: palette.surface,
                  suffixIcon: showClear
                      ? IconButton(
                          tooltip: clearTooltip,
                          onPressed: onClear,
                          icon: const Icon(Icons.close, size: 18),
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: palette.primaryDark, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              width: 48,
              child: FilledButton(
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: palette.primary,
                  foregroundColor: palette.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.search),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Showing 1–20 of 131", page-size picker and previous / next.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.provider, required this.palette});
  final BatteryMovementProvider provider;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.total > 0)
          Text(
            l.t(
                provider.totalKnown
                    ? 'movement.showing'
                    : 'movement.showingNoTotal',
                {
                  'from': provider.fromIndex,
                  'to': provider.toIndex,
                  'total': provider.total,
                }),
            style: TextStyle(fontSize: 12.5, color: palette.muted),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              l.t('movement.pageSize'),
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
            const SizedBox(width: 6),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: BatteryMovementProvider.pageSizes
                        .contains(provider.pageSize)
                    ? provider.pageSize
                    : null,
                isDense: true,
                style: TextStyle(fontSize: 13, color: palette.onSurface),
                items: [
                  for (final s in BatteryMovementProvider.pageSizes)
                    DropdownMenuItem(value: s, child: Text('$s')),
                ],
                onChanged: (v) {
                  if (v != null) provider.setPageSize(v);
                },
              ),
            ),
            IconButton(
              tooltip: l.t('movement.previous'),
              visualDensity: VisualDensity.compact,
              onPressed: provider.hasPrevious && !provider.loading
                  ? provider.previousPage
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: l.t('movement.next'),
              visualDensity: VisualDensity.compact,
              onPressed: provider.hasNext && !provider.loading
                  ? provider.nextPage
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

/// One completed query. The BDD tool shows this as a table row; on a phone it
/// reads better as a card.
class _QueryCard extends StatelessWidget {
  const _QueryCard({
    required this.query,
    required this.palette,
    required this.l,
  });

  final BatteryMovementQuery query;
  final AppPalette palette;
  final AppLocalizations l;

  String _dt(DateTime? dt) => _stamp(dt);

  /// The status badge text, localised from the service's `queryStatus` code.
  String get _statusLabel => switch (query.statusCode) {
        BatteryMovementQuery.statusSuccess => l.t('movement.status.success'),
        BatteryMovementQuery.statusInProgress =>
          l.t('movement.status.inProgress'),
        BatteryMovementQuery.statusFailed => l.t('movement.status.failed'),
        BatteryMovementQuery.statusNoData => l.t('movement.status.noData'),
        null => query.remarks,
        final code => l.t('movement.status.other', {'code': code}),
      };

  Color get _statusColor => switch (query.statusCode) {
        BatteryMovementQuery.statusSuccess => palette.success,
        BatteryMovementQuery.statusInProgress => palette.info,
        BatteryMovementQuery.statusFailed => palette.danger,
        BatteryMovementQuery.statusNoData => palette.warning,
        _ => palette.muted,
      };

  Future<void> _openReport(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = l.t('movement.cantOpenReport');
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(query.reportUrl!),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  query.serialNumber.isEmpty ? _dash : query.serialNumber,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: palette.onSurface,
                  ),
                ),
              ),
              if (statusLabel.isNotEmpty) ...[
                const SizedBox(width: 8),
                StatusBadge(label: statusLabel, color: _statusColor),
              ],
            ],
          ),
          if (query.category.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: palette.chipBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                query.category,
                style: TextStyle(fontSize: 11.5, color: palette.onSurface),
              ),
            ),
          ],
          // Why no report was produced (heavy load, no live data, daily limit…).
          // A success only says "Success", which the badge already shows.
          if (!query.succeeded && query.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              query.remarks,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: palette.onSurface,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _pair(
            l.t('movement.startTime'),
            _dt(query.startTime),
            l.t('movement.endTime'),
            _dt(query.endTime),
          ),
          const SizedBox(height: 10),
          _pair(
            l.t('movement.timeTaken'),
            query.timeTaken.isEmpty ? _dash : query.timeTaken,
            null,
            null,
          ),
          const SizedBox(height: 10),
          _pair(
            l.t('movement.createdDate'),
            _dt(query.createdAt),
            l.t('movement.updatedDate'),
            _dt(query.updatedAt),
          ),
          if (query.hasReport) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _openReport(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: palette.onSurface,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(l.t('movement.viewReport')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pair(String k1, String v1, String? k2, String? v2) =>
      _fieldPair(palette, k1, v1, k2, v2);
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.palette,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final AppPalette palette;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Icon(icon, size: 40, color: palette.muted),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, height: 1.35),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
