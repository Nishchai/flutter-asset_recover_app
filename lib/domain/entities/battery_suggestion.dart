/// One battery offered by the serial-number type-ahead on the Request Data form
/// (Battery Master `SearchBattery`).
class BatterySuggestion {
  const BatterySuggestion({
    required this.serialNumber,
    this.tiuSerialNumber = '',
  });

  /// The battery's serial number — what the movement report is requested for.
  final String serialNumber;

  /// The battery's TIU serial, when the service sends one.
  final String tiuSerialNumber;

  @override
  bool operator ==(Object other) =>
      other is BatterySuggestion && other.serialNumber == serialNumber;

  @override
  int get hashCode => serialNumber.hashCode;
}
