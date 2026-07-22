/// A single selectable option from `dropdowns.json`.
///
/// [value] is what gets stored/sent to the backend; [labelKey] is resolved
/// through localization for display. [extra] carries option-specific metadata
/// (e.g. an outcome's `resolution`, `requiresApproval`, `requiresOtp`).
class OptionItem {
  const OptionItem({
    required this.value,
    required this.labelKey,
    this.extra = const {},
  });

  final String value;
  final String labelKey;
  final Map<String, dynamic> extra;

  bool boolExtra(String key) => extra[key] == true;
  String? stringExtra(String key) => extra[key] as String?;

  factory OptionItem.fromJson(Map<String, dynamic> json) {
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (entry.key != 'value' && entry.key != 'labelKey') {
        extra[entry.key] = entry.value;
      }
    }
    return OptionItem(
      value: json['value'] as String,
      labelKey: json['labelKey'] as String? ?? json['value'] as String,
      extra: extra,
    );
  }
}
