import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// The two CTA styles from the Figma flows:
///  * [PillButton.dark]   — near-black pill, yellow label (primary CTA)
///  * [PillButton.yellow] — acid-yellow pill, dark label (confirm / proceed)
///  * [PillButton.outline]— bordered pill, dark label (secondary)
class PillButton extends StatelessWidget {
  const PillButton._({
    required this.label,
    required this.onPressed,
    required this.bg,
    required this.fg,
    required this.border,
    this.icon,
    this.trailingArrow = false,
  });

  factory PillButton.dark(
    String label, {
    required VoidCallback? onPressed,
    required AppPalette palette,
    IconData? icon,
    bool trailingArrow = false,
  }) =>
      PillButton._(
        label: label,
        onPressed: onPressed,
        bg: palette.pillDark,
        fg: palette.primary,
        border: null,
        icon: icon,
        trailingArrow: trailingArrow,
      );

  factory PillButton.yellow(
    String label, {
    required VoidCallback? onPressed,
    required AppPalette palette,
    IconData? icon,
    bool trailingArrow = false,
  }) =>
      PillButton._(
        label: label,
        onPressed: onPressed,
        bg: palette.primary,
        fg: palette.onPrimary,
        border: null,
        icon: icon,
        trailingArrow: trailingArrow,
      );

  factory PillButton.outline(
    String label, {
    required VoidCallback? onPressed,
    required AppPalette palette,
    IconData? icon,
  }) =>
      PillButton._(
        label: label,
        onPressed: onPressed,
        bg: Colors.transparent,
        fg: palette.onSurface,
        border: palette.border,
        icon: icon,
      );

  final String label;
  final VoidCallback? onPressed;
  final Color bg;
  final Color fg;
  final Color? border;
  final IconData? icon;
  final bool trailingArrow;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: border == null ? BorderSide.none : BorderSide(color: border!),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (trailingArrow) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward, size: 17, color: fg),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
