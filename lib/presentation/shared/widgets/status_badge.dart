import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Small rounded pill used for case types, ticket status and outcomes.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
  });

  final String label;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: filled ? Colors.white : color,
        ),
      ),
    );
  }
}

/// Convenience constructors bound to the configured palette.
class CaseTypeBadge extends StatelessWidget {
  const CaseTypeBadge({super.key, required this.caseType, required this.palette});
  final String caseType;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) =>
      StatusBadge(label: caseType, color: palette.caseTypeColor(caseType));
}
