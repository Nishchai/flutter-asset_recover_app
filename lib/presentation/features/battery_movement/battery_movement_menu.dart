import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/features/battery_movement/battery_movement_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The home screen's info (ⓘ) menu: a bottom sheet of quick links. Today it
/// holds one — the Battery Movement Report.
Future<void> showBatteryMovementMenu(BuildContext context) {
  final palette = context.read<AppPalette>();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: palette.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      final l = AppLocalizations.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.t('movement.sheetTitle'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: palette.chipBg,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BatteryMovementScreen(),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: palette.primary,
                          foregroundColor: palette.onPrimary,
                          child: const Icon(Icons.swap_horiz),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.t('movement.option.title'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: palette.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l.t('movement.option.subtitle'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: palette.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
