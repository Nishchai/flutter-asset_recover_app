import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Small rounded chip used across ticket cards and BP detail
/// (distance, days-left, inactivity, vehicle type, status).
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.label,
    required this.palette,
    this.icon,
    this.textColor,
    this.onDark = false,
  });

  final String label;
  final AppPalette palette;
  final IconData? icon;
  final Color? textColor;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? (onDark ? palette.onDark : palette.onSurface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark ? palette.darkSurface : palette.chipBg,
        borderRadius: BorderRadius.circular(8),
        border: onDark ? Border.all(color: palette.darkBorder) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
          ),
        ],
      ),
    );
  }
}
