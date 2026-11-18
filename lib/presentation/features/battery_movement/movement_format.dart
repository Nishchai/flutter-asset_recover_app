import 'package:intl/intl.dart';

/// Placeholder shown for a missing value.
const movementDash = '—';

final _stampFormat = DateFormat('dd MMM yyyy, hh:mm a');

/// Compact IST stamp (e.g. "11 Nov 2026, 08:30 AM"). Shown without an "IST"
/// suffix so each value fits on one line; India has no DST, so the fixed
/// +05:30 offset is right year-round.
String movementStamp(DateTime? dt) => dt == null
    ? movementDash
    : _stampFormat
        .format(dt.toUtc().add(const Duration(hours: 5, minutes: 30)));
