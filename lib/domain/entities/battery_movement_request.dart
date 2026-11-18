/// Why a movement-data request cannot be sent.
enum BatteryMovementRequestError {
  serialTooShort,
  datesMissing,
  endBeforeStart,
  rangeTooLong,
  startTooOld,
}

/// A request for one battery's movement data over a date range — the "Request
/// Data" action of the Battery Movement Report (`POST /BatteryMovementReport`).
///
/// The range is whole calendar days in India Standard Time: it starts at
/// 00:00:00 IST on [startDate] and ends at 23:59:59 IST on [endDate], sent to
/// the service as epoch seconds.
class BatteryMovementRequest {
  const BatteryMovementRequest({
    required this.serialNumber,
    required this.startDate,
    required this.endDate,
    required this.requestedBy,
    required this.email,
  });

  /// Fewest characters a serial number may have, as on the BDD tool.
  static const int minSerialLength = 4;

  /// Longest period the service will fetch, in days (start and end inclusive).
  static const int maxDays = 10;

  /// How far back the start date may reach, in months.
  static const int maxStartAgeMonths = 12;

  static const Duration _ist = Duration(hours: 5, minutes: 30);

  final String serialNumber;

  /// Calendar dates (only year / month / day are used).
  final DateTime startDate;
  final DateTime endDate;

  /// Agent who raised the request (`createdBy` / `modifiedBy`).
  final String requestedBy;

  /// Where the finished report is delivered (`mailId`).
  final String email;

  /// 00:00:00 IST on [startDate], as epoch seconds.
  int get startEpochSeconds => _istEpoch(startDate, 0, 0, 0);

  /// 23:59:59 IST on [endDate], as epoch seconds.
  int get endEpochSeconds => _istEpoch(endDate, 23, 59, 59);

  static int _istEpoch(DateTime d, int h, int m, int s) =>
      DateTime.utc(d.year, d.month, d.day, h, m, s)
          .subtract(_ist)
          .millisecondsSinceEpoch ~/
      1000;

  /// The first rule the inputs break, or null when they are sendable. [today]
  /// is the current date in India (injectable for tests).
  static BatteryMovementRequestError? validate({
    required String serialNumber,
    required DateTime? startDate,
    required DateTime? endDate,
    required DateTime today,
  }) {
    if (serialNumber.trim().length < minSerialLength) {
      return BatteryMovementRequestError.serialTooShort;
    }
    if (startDate == null || endDate == null) {
      return BatteryMovementRequestError.datesMissing;
    }
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day);
    if (end.isBefore(start)) return BatteryMovementRequestError.endBeforeStart;
    if (end.difference(start).inDays + 1 > maxDays) {
      return BatteryMovementRequestError.rangeTooLong;
    }
    final earliest =
        DateTime.utc(today.year, today.month - maxStartAgeMonths, today.day);
    if (start.isBefore(earliest)) {
      return BatteryMovementRequestError.startTooOld;
    }
    return null;
  }
}
