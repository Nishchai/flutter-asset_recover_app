import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/ticket_source.dart';
import 'package:flutter/material.dart';

/// The Source sub-filter chip under the home tabs. Shows the number of sources
/// picked; tapping it opens [showSourceFilterSheet].
class SourceFilterChip extends StatelessWidget {
  const SourceFilterChip({
    super.key,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final Set<TicketSource> selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final active = selected.isNotEmpty;
    final label = active
        ? '${l.t('filter.source')} (${selected.length})'
        : l.t('filter.source');
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? palette.pillDark : palette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? palette.pillDark : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : palette.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: active ? Colors.white : palette.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select of ticket sources with a search box and Select all. Resolves to
/// the chosen set on Apply (empty = every source), or null when dismissed.
Future<Set<TicketSource>?> showSourceFilterSheet(
  BuildContext context, {
  required Set<TicketSource> selected,
  required AppPalette palette,
}) {
  return showModalBottomSheet<Set<TicketSource>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SourceSheet(initial: selected, palette: palette),
  );
}

class _SourceSheet extends StatefulWidget {
  const _SourceSheet({required this.initial, required this.palette});

  final Set<TicketSource> initial;
  final AppPalette palette;

  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  late final Set<TicketSource> _picked = {...widget.initial};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = widget.palette;
    final visible = [
      for (final s in TicketSource.values)
        if (l.t(s.labelKey).toLowerCase().contains(_query.toLowerCase())) s,
    ];
    final allVisiblePicked =
        visible.isNotEmpty && visible.every(_picked.contains);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                l.t('filter.source.title'),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v.trim()),
                      decoration: InputDecoration(
                        hintText: l.t('filter.source.search'),
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: visible.isEmpty
                        ? null
                        : () => setState(() {
                              if (allVisiblePicked) {
                                _picked.removeAll(visible);
                              } else {
                                _picked.addAll(visible);
                              }
                            }),
                    child: Text(
                      l.t('filter.source.selectAll'),
                      style: TextStyle(color: palette.primary),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in visible)
                    CheckboxListTile(
                      value: _picked.contains(s),
                      activeColor: palette.primary,
                      checkColor: palette.onPrimary,
                      side: BorderSide(color: palette.onSurface, width: 1.5),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(l.t(s.labelKey)),
                      onChanged: (on) => setState(() {
                        if (on ?? false) {
                          _picked.add(s);
                        } else {
                          _picked.remove(s);
                        }
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(<TicketSource>{}),
                      child: Text(l.t('filter.source.clear')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    // Dark pill, yellow text — the app's primary CTA style.
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_picked),
                      child: Text(l.t('filter.source.apply')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
