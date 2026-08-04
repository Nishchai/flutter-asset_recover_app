import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/agent.dart';
import 'package:flutter/material.dart';

/// Dark home header (Figma): greeting + agent, shift toggle, shift-active
/// banner and the three shift stat cards.
class ShiftHeader extends StatelessWidget {
  const ShiftHeader({
    super.key,
    required this.agent,
    required this.palette,
    required this.shiftActive,
    required this.assigned,
    required this.inProgressOrOpen,
    required this.closed,
    required this.onToggleShift,
  });

  final Agent agent;
  final AppPalette palette;
  final bool shiftActive;

  /// Total tickets assigned to the agent, any status.
  final int assigned;

  /// Tickets still live — In Progress plus Open (wire status `assigned`).
  final int inProgressOrOpen;

  /// Tickets the coordinator has closed.
  final int closed;
  final ValueChanged<bool> onToggleShift;

  String _greetingKey() {
    final h = DateTime.now().hour;
    if (h < 12) return 'greeting.morning';
    if (h < 17) return 'greeting.afternoon';
    return 'greeting.evening';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(gradient: palette.heroGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: palette.primary,
                    child: Text(agent.initials,
                        style: TextStyle(
                            color: palette.onPrimary,
                            fontWeight: FontWeight.bold,),),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.t(_greetingKey()),
                            style: TextStyle(
                                fontSize: 12, color: palette.mutedDark,),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${l.t('home.hello')} ',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: palette.onDark,),
                              ),
                              TextSpan(
                                text: agent.name,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: palette.primary,),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: shiftActive,
                    onChanged: onToggleShift,
                    thumbColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? palette.onPrimary
                            : palette.mutedDark,),
                    trackColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected)
                            ? palette.primary
                            : palette.darkSurface,),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: palette.darkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: palette.darkBorder),
                ),
                child: Row(
                  children: [
                    Text(
                      shiftActive ? l.t('shift.active') : l.t('shift.inactive'),
                      style: TextStyle(
                        color: shiftActive ? palette.primary : palette.mutedDark,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(agent.shiftArea,
                          style: TextStyle(
                              color: palette.onDark, fontSize: 13,),
                          overflow: TextOverflow.ellipsis,),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _stat(l.t('stats.assigned'), assigned, highlight: true),
                  const SizedBox(width: 10),
                  _stat(l.t('stats.inProgressOpen'), inProgressOrOpen),
                  const SizedBox(width: 10),
                  _stat(l.t('stats.closed'), closed),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int value, {bool highlight = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: palette.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$value',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: highlight ? palette.primary : palette.onDark,
                ),),
            const SizedBox(height: 2),
            // The label must stay on ONE line — the three cards share a row, so
            // a label that wraps ("PROGRESS/OPEN" is the tightest fit) would
            // make its card taller than the other two. Scaled down to fit
            // rather than wrapped or ellipsised, so it stays fully readable on
            // narrow screens and in the longer translations.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 10.5, color: palette.mutedDark),),
            ),
          ],
        ),
      ),
    );
  }
}
