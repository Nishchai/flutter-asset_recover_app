/// IST's fixed offset from UTC (+05:30). India observes no daylight saving, so
/// this is a constant and needs no time-zone database.
///
/// India Standard Time is the one wall clock the app reasons about, whatever
/// zone the device itself is set to: the auto-logout window is anchored to the
/// moment the agent signed in, so it has to survive a device that travels or
/// changes zone between two launches.
const Duration istOffset = Duration(hours: 5, minutes: 30);

/// "Now" on the IST wall clock.
///
/// Returned as a UTC-flagged [DateTime] shifted by [istOffset]: the fields read
/// as Indian local time, `toIso8601String` round-trips losslessly through
/// [istFromIso], and subtracting two of these gives the true elapsed duration
/// regardless of the device's zone.
DateTime nowIst() => DateTime.now().toUtc().add(istOffset);

/// Parses a timestamp written by [nowIst]. Returns null for null, empty or
/// malformed input — a session with an unreadable login time is treated as one
/// with no login time at all, i.e. expired.
DateTime? istFromIso(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  return DateTime.tryParse(iso)?.toUtc();
}
