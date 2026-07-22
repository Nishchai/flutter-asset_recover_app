import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:flutter/material.dart';

/// Distance pill shown on BP cards (PRD §4.8 — road distance, nearest-first).
class DistanceChip extends StatelessWidget {
  const DistanceChip({super.key, required this.km, required this.palette});

  final double? km;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.navigation_outlined, size: 13, color: palette.primary),
          const SizedBox(width: 4),
          Text(
            Formatters.distanceKm(km),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}
