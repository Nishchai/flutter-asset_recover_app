import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_query.dart';
import 'package:asset_recovery_app/domain/entities/battery_movement_request.dart';
import 'package:asset_recovery_app/domain/entities/battery_suggestion.dart';
import 'package:asset_recovery_app/presentation/features/battery_movement/movement_format.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/battery_movement_provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// "Add new query": asks the service to generate a movement report for one
/// battery over a date range (max 10 days). On Submit the app first checks for
/// related queries; if there are any they are listed for the agent to confirm
/// (Proceed / Cancel), then the query is created and the report reloads.
///
/// [provider] is passed in because a modal sheet is built outside the report
/// screen's own provider scope.
Future<void> showRequestDataSheet(
  BuildContext context,
  BatteryMovementProvider provider,
) {
  final palette = context.read<AppPalette>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RequestDataSheet(provider: provider),
  );
}

class _RequestDataSheet extends StatefulWidget {
  const _RequestDataSheet({required this.provider});
  final BatteryMovementProvider provider;

  @override
  State<_RequestDataSheet> createState() => _RequestDataSheetState();
}

class _RequestDataSheetState extends State<_RequestDataSheet> {
  final _serial = TextEditingController();
  final _serialFocus = FocusNode();
  DateTimeRange? _range;
  BatteryMovementRequestError? _fieldError;
  String? _formError;
  bool _busy = false;

  /// The battery chosen from the type-ahead. As on the BDD tool, a request is
  /// only for a battery picked from the list, never for free-typed text.
  BatterySuggestion? _picked;
  bool _pickError = false;

  /// Shown under the serial field: the lookup failed, or it found nothing.
  String? _searchNote;

  /// Identifies the latest keystroke, so a slow earlier lookup is discarded.
  int _searchToken = 0;

  /// Wait after the last keystroke before asking the service.
  static const _debounce = Duration(milliseconds: 400);

  static final _dateFormat = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    // Editing the text after picking a battery un-picks it.
    _serial.addListener(() {
      final picked = _picked;
      if (picked != null &&
          _serial.text.trim().toUpperCase() !=
              picked.serialNumber.toUpperCase()) {
        setState(() => _picked = null);
      }
    });
  }

  @override
  void dispose() {
    _serial.dispose();
    _serialFocus.dispose();
    super.dispose();
  }

  /// Type-ahead options for [value]: nothing below 4 characters, otherwise a
  /// debounced Battery Master lookup.
  Future<Iterable<BatterySuggestion>> _options(TextEditingValue value) async {
    final text = value.text.trim();
    final token = ++_searchToken;
    if (!BatteryMovementProvider.isValidSearch(text)) {
      if (_searchNote != null && mounted) setState(() => _searchNote = null);
      return const [];
    }
    await Future<void>.delayed(_debounce);
    if (token != _searchToken || !mounted) return const [];

    final l = AppLocalizations.of(context);
    final result = await widget.provider.findBatteries(text);
    if (token != _searchToken || !mounted) return const [];
    setState(() {
      _searchNote = result.error != null
          ? l.t('movement.request.searchFailed')
          : (result.items.isEmpty ? l.t('movement.request.noMatches') : null);
    });
    return result.items;
  }

  /// Today's date in India, as a plain date.
  static DateTime _todayIst() {
    final now =
        DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickRange() async {
    final today = _todayIst();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(
        today.year,
        today.month - BatteryMovementRequest.maxStartAgeMonths,
        today.day,
      ),
      lastDate: today,
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = picked;
      _fieldError = null;
    });
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    FocusScope.of(context).unfocus();

    final picked = _picked;
    final error = BatteryMovementRequest.validate(
      serialNumber: picked?.serialNumber ?? _serial.text,
      startDate: _range?.start,
      endDate: _range?.end,
      today: _todayIst(),
    );
    if (error != null || picked == null) {
      setState(() {
        _fieldError = error;
        _pickError = picked == null;
        _formError = null;
      });
      return;
    }

    final email = auth.profile?.emailId.trim() ?? '';
    if (email.isEmpty) {
      setState(() {
        _fieldError = null;
        _formError = l.t('movement.request.noEmail');
      });
      return;
    }
    final name = (auth.profile?.userName.trim().isNotEmpty ?? false)
        ? auth.profile!.userName.trim()
        : (auth.agent?.name ?? '');
    final request = BatteryMovementRequest(
      serialNumber: picked.serialNumber.trim().toUpperCase(),
      startDate: _range!.start,
      endDate: _range!.end,
      requestedBy: name,
      email: email,
    );

    setState(() {
      _busy = true;
      _fieldError = null;
      _pickError = false;
      _formError = null;
    });

    // 1) Duplicate check — show what already exists for this battery/window.
    final check = await widget.provider.checkRelated(request);
    if (!mounted) return;
    if (check.error != null) {
      setState(() {
        _busy = false;
        _formError = l.t('movement.request.checkFailed');
      });
      return;
    }
    if (check.related.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => RelatedQueriesDialog(related: check.related),
      );
      if (!mounted) return;
      if (proceed != true) {
        setState(() => _busy = false);
        return;
      }
    }

    // 2) Create it, then the provider reloads the report.
    final failure = await widget.provider.submitRequest(request);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _busy = false;
        _formError = failure;
      });
      return;
    }
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(l.t('movement.request.submitted'))),
    );
  }

  String? _errorText(AppLocalizations l, bool forSerial) {
    final e = _fieldError;
    if (e == null) return null;
    final isSerial = e == BatteryMovementRequestError.serialTooShort;
    if (isSerial != forSerial) return null;
    return switch (e) {
      BatteryMovementRequestError.serialTooShort =>
        l.t('movement.request.err.serial'),
      BatteryMovementRequestError.datesMissing =>
        l.t('movement.request.err.dates'),
      BatteryMovementRequestError.endBeforeStart =>
        l.t('movement.request.err.endBefore'),
      BatteryMovementRequestError.rangeTooLong =>
        l.t('movement.request.err.range'),
      BatteryMovementRequestError.startTooOld =>
        l.t('movement.request.err.tooOld'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final category = sl<ConfigService>().stringValue(
      'business.batteryMovementCategory',
      fallback: 'Wheelers',
    );
    final rangeText = _range == null
        ? null
        : '${_dateFormat.format(_range!.start)} – ${_dateFormat.format(_range!.end)}';
    final dateError = _errorText(l, false);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t('movement.request.title'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: palette.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            _label(palette, l.t('movement.request.batteryType')),
            TextFormField(
              initialValue: category,
              readOnly: true,
              enabled: false,
              style: TextStyle(color: palette.onSurface),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: palette.chipBg,
                border: border(palette.border),
                disabledBorder: border(palette.border),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
            ),
            const SizedBox(height: 14),
            _label(palette, l.t('movement.request.serial'), required: true),
            LayoutBuilder(
              builder: (context, constraints) =>
                  RawAutocomplete<BatterySuggestion>(
                textEditingController: _serial,
                focusNode: _serialFocus,
                optionsBuilder: _options,
                displayStringForOption: (s) => s.serialNumber,
                onSelected: (s) => setState(() {
                  _picked = s;
                  _pickError = false;
                  _searchNote = null;
                }),
                fieldViewBuilder: (context, controller, focusNode, _) =>
                    TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(color: palette.onSurface),
                  decoration: InputDecoration(
                    hintText: l.t('movement.searchHint'),
                    errorText: _errorText(l, true) ??
                        (_pickError
                            ? l.t('movement.request.err.pickBattery')
                            : null),
                    isDense: true,
                    filled: true,
                    fillColor: palette.surface,
                    suffixIcon: _picked == null
                        ? null
                        : Icon(Icons.check_circle, color: palette.success),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    border: border(palette.border),
                    enabledBorder: border(palette.border),
                    focusedBorder: border(palette.primaryDark, 1.6),
                  ),
                ),
                optionsViewBuilder: (context, onSelected, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    color: palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: 220,
                        maxWidth: constraints.maxWidth,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (_, i) {
                          final s = options.elementAt(i);
                          return InkWell(
                            onTap: () => onSelected(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Text(
                                l.t('movement.request.batteryOption', {
                                  'serial': s.serialNumber,
                                }),
                                style: TextStyle(color: palette.onSurface),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_searchNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _searchNote!,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ),
            const SizedBox(height: 14),
            _label(palette, l.t('movement.request.dateRange'), required: true),
            Text(
              l.t('movement.request.maxRange'),
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy ? null : _pickRange,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  errorText: dateError,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: border(palette.border),
                  enabledBorder: border(palette.border),
                  suffixIcon: const Icon(Icons.date_range_outlined),
                ),
                child: Text(
                  rangeText ?? l.t('movement.request.dateHint'),
                  style: TextStyle(
                    color:
                        rangeText == null ? palette.muted : palette.onSurface,
                  ),
                ),
              ),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(
                _formError!,
                style: TextStyle(color: palette.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l.t('common.cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: palette.primary,
                      foregroundColor: palette.onPrimary,
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: palette.onPrimary,
                            ),
                          )
                        : Text(l.t('movement.request.submit')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(AppPalette palette, String text, {bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(
          TextSpan(
            text: text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.onSurface,
            ),
            children: [
              if (required)
                TextSpan(text: ' *', style: TextStyle(color: palette.danger)),
            ],
          ),
        ),
      );
}

/// "Related queries": what already exists for this battery and period.
class RelatedQueriesDialog extends StatelessWidget {
  const RelatedQueriesDialog({super.key, required this.related});
  final List<BatteryMovementQuery> related;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    return AlertDialog(
      title: Text(l.t('movement.related.title')),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.t('movement.related.note'),
              style: TextStyle(fontSize: 13, color: palette.muted),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: related.length,
                separatorBuilder: (_, __) => Divider(color: palette.border),
                itemBuilder: (_, i) {
                  final q = related[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.serialNumber,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: palette.onSurface,
                        ),
                      ),
                      if (q.category.isNotEmpty)
                        Text(
                          q.category,
                          style: TextStyle(fontSize: 12, color: palette.muted),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${l.t('movement.startTime')}: ${movementStamp(q.startTime)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.onSurface,
                        ),
                      ),
                      Text(
                        '${l.t('movement.endTime')}: ${movementStamp(q.endTime)}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: palette.onSurface,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: palette.onSurface),
          child: Text(l.t('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: palette.primary,
            foregroundColor: palette.onPrimary,
          ),
          child: Text(l.t('movement.related.proceed')),
        ),
      ],
    );
  }
}
