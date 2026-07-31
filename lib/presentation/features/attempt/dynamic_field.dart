import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/form_field_config.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/proof_capture_field.dart';
import 'package:asset_recovery_app/presentation/state/attempt_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Renders ONE wizard field based on its [FormFieldConfig.type]. This is the
/// generic engine that makes the attempt flow fully config-driven.
class DynamicField extends StatelessWidget {
  const DynamicField({super.key, required this.field});

  final FormFieldConfig field;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AttemptController>();
    final palette = context.read<AppPalette>();
    final l = AppLocalizations.of(context);
    final label = l.t(field.labelKey);
    final required = controller.isRequired(field);

    switch (field.type) {
      case 'readonly':
        return _readonly(context, controller, palette, label);
      case 'dropdown':
        return _dropdown(context, controller, palette, label, required);
      case 'proof':
        return ProofCaptureField(
          label: label,
          required: required,
          captured: controller.proofFor(field.id) != null,
          palette: palette,
          hint: field.hintKey == null ? null : l.t(field.hintKey!),
          onTap: () => controller.captureProof(field),
        );
      case 'otp':
        return _text(context, controller, label, required,
            keyboard: TextInputType.number, maxLength: 6, digitsOnly: true,);
      case 'number':
        return _text(context, controller, label, required,
            keyboard: TextInputType.number,
            maxLength: field.maxLength,
            digitsOnly: field.digitsOnly,
            prefix: field.prefix,
            hint: field.hintKey == null ? null : l.t(field.hintKey!),);
      case 'phone':
        return _text(context, controller, label, required,
            keyboard: TextInputType.phone, maxLength: 10, digitsOnly: true,);
      case 'textarea':
        return _text(context, controller, label, required,
            maxLines: field.maxLines,
            hint: field.hintKey == null ? null : l.t(field.hintKey!),);
      case 'text':
      default:
        return _text(context, controller, label, required,
            maxLength: field.maxLength,
            hint: field.hintKey == null ? null : l.t(field.hintKey!),);
    }
  }

  Widget _label(String label, bool required, AppPalette palette) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 13, color: palette.muted),
            children: [
              if (required)
                TextSpan(text: ' *', style: TextStyle(color: palette.danger)),
            ],
          ),
        ),
      );

  Widget _readonly(BuildContext context, AttemptController c,
      AppPalette palette, String label,) {
    final value = c.readonlyValue(field);
    final secondary = c.readonlySecondary(field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                field.iconKey == 'home' ? Icons.home_outlined : Icons.location_pin,
                size: 18,
                color: palette.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            TextStyle(fontSize: 12, color: palette.muted),),
                    const SizedBox(height: 2),
                    Text(value,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),),
                    if (secondary != null && secondary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 14, color: palette.muted,),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(secondary,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600,),),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dropdown(BuildContext context, AttemptController c, AppPalette palette,
      String label, bool required,) {
    final l = AppLocalizations.of(context);
    final config = context.read<AppServices>().config;
    final options = config.options(field.optionsRef ?? '');
    final current = c.value(field.id) as String?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, required, palette),
        DropdownButtonFormField<String>(
          initialValue: current,
          isExpanded: true,
          decoration: InputDecoration(errorText: c.fieldError(field.id)),
          hint: Text(l.t('field.selectHint')),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o.value, child: Text(l.t(o.labelKey))),
          ],
          onChanged: (v) => c.setValue(field.id, v),
        ),
      ],
    );
  }

  Widget _text(
    BuildContext context,
    AttemptController c,
    String label,
    bool required, {
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
    bool digitsOnly = false,
    String? prefix,
    String? hint,
  }) {
    final palette = context.read<AppPalette>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label, required, palette),
        TextFormField(
          initialValue: c.value(field.id) as String?,
          keyboardType: keyboard,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters:
              digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          decoration: InputDecoration(
            counterText: '',
            // Set on Save by the controller's validation and cleared the
            // moment the agent edits the field; Material turns the outline red
            // and prints the message beneath it.
            errorText: c.fieldError(field.id),
            hintText: hint,
            // A notch below the field label (13) and in the same muted tone, so
            // the placeholder reads as guidance rather than entered text.
            hintStyle: TextStyle(fontSize: 12, color: palette.muted),
            prefixText: prefix,
          ),
          onChanged: (v) => c.setValue(field.id, v),
        ),
      ],
    );
  }
}
