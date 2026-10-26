import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Dashed proof-capture tile used by every proof step in the wizard.
/// Mirrors the Figma "Capture screenshot / Screenshot captured" component.
class ProofCaptureField extends StatelessWidget {
  const ProofCaptureField({
    super.key,
    required this.label,
    required this.captured,
    required this.onTap,
    required this.palette,
    this.required = false,
    this.hint,
    this.icon,
    this.actionLabelKey,
    this.doneLabelKey,
  });

  final String label;
  final bool captured;
  final VoidCallback onTap;
  final AppPalette palette;
  final bool required;
  final String? hint;

  /// Overrides the "not captured yet" icon (default: a camera) — e.g. a
  /// gallery or attach-file glyph for a field that doesn't use the camera.
  /// The "captured" checkmark is always shown once a file is picked.
  final IconData? icon;

  /// Overrides `proof.capture`/`proof.captured` ("Take Photo"/"Photo
  /// captured") for a field that doesn't take a photo — e.g. "Attach File".
  final String? actionLabelKey;
  final String? doneLabelKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = captured ? palette.success : palette.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: palette.muted)),
            if (required)
              Text(' *', style: TextStyle(color: palette.danger, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22),
            decoration: BoxDecoration(
              color: captured
                  ? palette.success.withValues(alpha: 0.08)
                  : palette.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Icon(
                  captured
                      ? Icons.check_circle_outline
                      : (icon ?? Icons.photo_camera_outlined),
                  color: color,
                ),
                const SizedBox(height: 6),
                Text(
                  captured
                      ? l.t(doneLabelKey ?? 'proof.captured')
                      : l.t(actionLabelKey ?? 'proof.capture'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: captured ? palette.success : palette.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint ?? l.t('field.proof_hint'),
                  style: TextStyle(fontSize: 11, color: palette.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
