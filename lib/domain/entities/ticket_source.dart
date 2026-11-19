/// Where a ticket came from — the tickets API's `source` value, offered as the
/// home list's Source sub-filter.
///
/// Matching ignores case and punctuation, so `at_risk`, `At-risk` and
/// `AT RISK` are the same source.
enum TicketSource {
  theft('filter.source.theft', {'theft', 'theftdashboard'}),
  atRisk('filter.source.atRisk', {'atrisk'}),
  manual('filter.source.manual', {'manual'});

  const TicketSource(this.labelKey, this._keys);

  final String labelKey;
  final Set<String> _keys;

  /// Lower-cases [raw] and drops everything but letters and digits.
  static String normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// True when the API's [raw] `source` value is this source.
  bool matches(String raw) => _keys.contains(normalize(raw));

  /// The source [raw] names, or null when it is none of the known ones.
  static TicketSource? fromRaw(String raw) {
    for (final s in values) {
      if (s.matches(raw)) return s;
    }
    return null;
  }

  /// [raw] made readable when it is not a known source: underscores and dashes
  /// become spaces and the first letter is capitalised (`some_new` → `Some new`).
  static String prettify(String raw) {
    final text = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  /// True when [raw] is one of [selected]. An empty selection matches all.
  static bool anyMatches(Set<TicketSource> selected, String raw) =>
      selected.isEmpty || selected.any((s) => s.matches(raw));
}
