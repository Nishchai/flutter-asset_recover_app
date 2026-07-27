import 'dart:convert';

import 'package:asset_recovery_app/domain/entities/battery_detail.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact response shape for `battery.getBatteryDetails`
/// (`GET .../WheelerBattery/SearchBattery/{bpId}`) — trimmed to the fields the
/// BP detail screen consumes plus the envelope structure.
const _sample = '''
{
  "version": "1.0.0.0",
  "statusCode": 200,
  "message": "ok",
  "responseException": null,
  "result": [
    {
      "batterySerialNumber": "INSMOMAH1203G0404E09",
      "tiuSerialNumber": "1902000392",
      "lastLatitude": 30.66448800,
      "lastLongitude": 76.81370200,
      "lastTiutimestamp": 1704890395,
      "lastPackVoltage": 51.20,
      "lastSoc": 50.0
    }
  ]
}
''';

void main() {
  test('unwraps the envelope and parses result[0]', () {
    final d = BatteryDetail.fromEnvelope(
      jsonDecode(_sample) as Map<String, dynamic>,
    );

    expect(d, isNotNull);
    expect(d!.batterySerialNumber, 'INSMOMAH1203G0404E09');
    expect(d.tiuSerialNumber, '1902000392');
    expect(d.lastLatitude, 30.664488);
    expect(d.lastLongitude, 76.813702);
    expect(d.lastSoc, 50.0);
    expect(d.hasLocation, isTrue);
    expect(d.location!.display, '30.664488, 76.813702');

    // lastTiutimestamp is Unix epoch SECONDS — round-trips to ms since epoch.
    expect(d.lastTiuTimestamp, isNotNull);
    expect(d.lastTiuTimestamp!.millisecondsSinceEpoch, 1704890395 * 1000);
  });

  test('empty / missing result → null', () {
    expect(
      BatteryDetail.fromEnvelope(
          jsonDecode('{"statusCode":200,"result":[]}')
              as Map<String, dynamic>,),
      isNull,
    );
    expect(
      BatteryDetail.fromEnvelope(
          jsonDecode('{"statusCode":200,"result":null}')
              as Map<String, dynamic>,),
      isNull,
    );
  });

  test('zero / missing telemetry fields degrade gracefully', () {
    final d = BatteryDetail.fromEnvelope(
      jsonDecode('{"result":[{"lastTiutimestamp":0}]}')
          as Map<String, dynamic>,
    );
    expect(d, isNotNull);
    expect(d!.hasLocation, isFalse);
    expect(d.location, isNull);
    // A zero epoch sentinel is treated as "no timestamp".
    expect(d.lastTiuTimestamp, isNull);
  });
}
