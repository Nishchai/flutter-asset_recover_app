/// Parsed representation of a field defined in `attempt_flow.json`.
///
/// The wizard renders one widget per [type] and evaluates [visibleWhen] /
/// requirement rules at runtime — so the flow is entirely data-driven.
class FormFieldConfig {
  FormFieldConfig({
    required this.id,
    required this.type,
    required this.labelKey,
    this.hintKey,
    this.optionsRef,
    this.required = false,
    this.requiredFlag,
    this.featureFlag,
    this.visibleWhen,
    this.sourceField,
    this.iconKey,
    this.group,
    this.prefix,
    this.maxLines = 1,
    this.proofKind,
  });

  final String id;
  final String type; // readonly|text|textarea|number|dropdown|phone|proof|otp
  final String labelKey;
  final String? hintKey;
  final String? optionsRef;
  final bool required;

  /// Dotted config path whose boolean value makes this field mandatory.
  final String? requiredFlag;

  /// Dotted config path whose boolean value gates this field's existence.
  final String? featureFlag;

  /// Conditional visibility rule, e.g. {field: outcome, in: [refused]}.
  final Map<String, dynamic>? visibleWhen;

  /// For readonly fields — which derived value to display.
  final String? sourceField;
  final String? iconKey;
  final String? group;
  final String? prefix;
  final int maxLines;
  final String? proofKind;

  factory FormFieldConfig.fromJson(Map<String, dynamic> json) =>
      FormFieldConfig(
        id: json['id'] as String,
        type: json['type'] as String,
        labelKey: json['labelKey'] as String? ?? json['id'] as String,
        hintKey: json['hintKey'] as String?,
        optionsRef: json['optionsRef'] as String?,
        required: json['required'] as bool? ?? false,
        requiredFlag: json['requiredFlag'] as String?,
        featureFlag: json['featureFlag'] as String?,
        visibleWhen: (json['visibleWhen'] as Map?)?.cast<String, dynamic>(),
        sourceField: json['sourceField'] as String?,
        iconKey: json['iconKey'] as String?,
        group: json['group'] as String?,
        prefix: json['prefix'] as String?,
        maxLines: (json['maxLines'] as num?)?.toInt() ?? 1,
        proofKind: json['proofKind'] as String?,
      );
}

/// A wizard step (Call, Location, Home, Outcome, Review).
class StepConfig {
  StepConfig({
    required this.id,
    required this.icon,
    required this.titleKey,
    required this.fields,
    this.isReview = false,
  });

  final String id;
  final String icon;
  final String titleKey;
  final List<FormFieldConfig> fields;
  final bool isReview;

  factory StepConfig.fromJson(Map<String, dynamic> json) => StepConfig(
        id: json['id'] as String,
        icon: json['icon'] as String? ?? 'check',
        titleKey: json['titleKey'] as String? ?? json['id'] as String,
        isReview: json['isReview'] as bool? ?? false,
        fields: (json['fields'] as List? ?? [])
            .map((e) => FormFieldConfig.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Top-level wizard definition parsed from `attempt_flow.json`.
class AttemptFlowConfig {
  AttemptFlowConfig({required this.titleKey, required this.steps});

  final String titleKey;
  final List<StepConfig> steps;

  factory AttemptFlowConfig.fromJson(Map<String, dynamic> json) =>
      AttemptFlowConfig(
        titleKey: json['titleKey'] as String? ?? 'wizard.title',
        steps: (json['steps'] as List? ?? [])
            .map((e) => StepConfig.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
