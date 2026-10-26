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
    this.maxLength,
    this.digitsOnly = false,
    this.proofKind,
    this.source,
    this.acceptExtensions,
    this.fileType,
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

  /// Conditional visibility rule, e.g. {field: outcome, in: [refused]} or
  /// {field: newCustomerMobile, notEmpty: true} (visible once that field has
  /// a non-blank value).
  final Map<String, dynamic>? visibleWhen;

  /// For readonly fields — which derived value to display.
  final String? sourceField;
  final String? iconKey;
  final String? group;
  final String? prefix;
  final int maxLines;

  /// Character cap for text-style fields (e.g. a 6-digit pincode). `null`
  /// leaves the input unbounded — the type-specific default still applies.
  final int? maxLength;

  /// Restricts a `number` field to digits only (e.g. a pincode) — amounts stay
  /// unrestricted so decimals remain typable.
  final bool digitsOnly;
  final String? proofKind;

  /// `proof` fields only: where the file comes from — `camera` (default,
  /// unset), `gallery` (image picker's photo library), or `file` (arbitrary
  /// file via the system picker, restricted to [acceptExtensions]).
  final String? source;

  /// `proof` fields with `source: file` only — the extensions the system
  /// file picker offers (e.g. `['mp3', 'mp4']`). Ignored when [fileType] is
  /// set to anything other than `custom`.
  final List<String>? acceptExtensions;

  /// `proof` fields with `source: file` only — which category the system
  /// file picker restricts to: `audio`, `video`, `image`, `media` (image or
  /// video) or `custom` (the default when [acceptExtensions] is set — matches
  /// those extensions only). Unlike filtering by extension, this is enforced
  /// by the OS picker itself against the file's real type, so an audio-only
  /// field can't be satisfied by a renamed video file.
  final String? fileType;

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
        maxLength: (json['maxLength'] as num?)?.toInt(),
        digitsOnly: json['digitsOnly'] as bool? ?? false,
        proofKind: json['proofKind'] as String?,
        source: json['source'] as String?,
        acceptExtensions:
            (json['acceptExtensions'] as List?)?.map((e) => e.toString()).toList(),
        fileType: json['fileType'] as String?,
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
