import 'dart:convert';

import 'package:asset_recovery_app/domain/entities/ticket_detail.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exact response you pasted for `GET /tickets/{UUID}`.
const _sample = '''
{
  "id": "f3cbb35e-386f-4185-b13f-2dbae104afbd",
  "ticketNumber": "TKT-2026-00024",
  "status": "assigned",
  "priority": 3,
  "source": "theft_dashboard",
  "customer": {
    "id": "c54a0f0f-fa09-4ad8-81a9-be062543de21",
    "externalId": "SUNMC00006011",
    "fullName": "13jkfs sorg ",
    "phonePrimary": "2345",
    "phoneSecondary": null,
    "email": "s@h.v",
    "addressLine1": "es",
    "city": "sf",
    "state": "sre",
    "pincode": null,
    "geoLocation": null,
    "bpType": null,
    "lastSwapDate": null,
    "lastSwapStationCode": null
  },
  "battery": { "id": "162af710", "bpId": "INSMOMAH1203G0404E09", "status": "pending" },
  "attempts": [
    {
      "id": "7497e52b",
      "outcome": "recovered",
      "proofUrls": "[\\"https://smstation.blob.core.windows.net/asset-recovery/proofs/a.jpg\\"]"
    }
  ],
  "isEmergency": true,
  "esvFlag": true
}
''';

// Mirrors the _CustomerCard helpers so the mapping is asserted directly.
String mobileOf(TicketDetailCustomer c) {
  final parts = [c.phonePrimary, c.phoneSecondary].where((p) => p.isNotEmpty);
  return parts.join(', ');
}

String addressOf(TicketDetailCustomer c) =>
    [c.addressLine1, c.city, c.state, c.pincode]
        .where((p) => p.isNotEmpty)
        .join(', ');

void main() {
  test('parses the sample response and maps customer fields', () {
    final d = TicketDetail.fromJson(jsonDecode(_sample) as Map<String, dynamic>);

    expect(d.id, 'f3cbb35e-386f-4185-b13f-2dbae104afbd');
    expect(d.ticketNumber, 'TKT-2026-00024');
    expect(d.isEmergency, true);
    expect(d.esvFlag, true);

    final c = d.customer!;
    // Mobile: only phonePrimary present → just that one.
    expect(mobileOf(c), '2345');
    // Address: line1 + city + state, pincode null → skipped.
    expect(addressOf(c), 'es, sf, sre');
    // The three enrichment fields are all null in this sample → empty.
    expect(c.geoLocation, '');
    expect(c.lastSwapDate, isNull);
    expect(c.lastSwapStationCode, '');

    // proofUrls arrives as a JSON-encoded string → decoded to a real list.
    expect(d.attempts.single.proofUrls.single,
        'https://smstation.blob.core.windows.net/asset-recovery/proofs/a.jpg',);
  });

  test('mobile joins both numbers when both present', () {
    const c = TicketDetailCustomer(
        id: '', phonePrimary: '2345', phoneSecondary: '9876',);
    expect(mobileOf(c), '2345, 9876');
  });

  test('mobile is empty when both numbers are absent', () {
    const c = TicketDetailCustomer(id: '');
    expect(mobileOf(c), '');
  });

  test('parses the real attempts array shape', () {
    // The exact array returned for the `attempts` field.
    const attemptsJson = '''
[
  {
    "id": "658bc80d-9a31-4fa2-8f67-b3e122ff2758",
    "ticketId": "f3cbb35e-386f-4185-b13f-2dbae104afbd",
    "batteryId": "162af710-7c8a-4d62-9408-dc6fb5b8583d",
    "agentId": "SUNMU00002340",
    "agentName": "RANGANATH",
    "attemptType": "field_visit",
    "outcome": "recovered",
    "attemptedAt": "2026-07-27T10:15:00+00:00",
    "completedAt": "2026-07-27T10:22:00+00:00",
    "location": "{\\"lat\\": 26.8368, \\"lng\\": 75.681}",
    "customerPresent": true,
    "notes": "Customer handed over the battery at the doorstep. but its not in working condition",
    "proofUrls": "[\\"https://smstation.blob.core.windows.net/asset-recovery/proofs/TKT-2026-00024/INSMOMAH1203G0404E09/document_2026-07-24T12-10-19-844672Z.jpg\\"]",
    "metadata": null
  },
  {
    "id": "7497e52b-b6a7-4cc8-8821-4e76cd45005d",
    "ticketId": "f3cbb35e-386f-4185-b13f-2dbae104afbd",
    "batteryId": "162af710-7c8a-4d62-9408-dc6fb5b8583d",
    "agentId": "SUNMU00002340",
    "agentName": "RANGANATH",
    "attemptType": "field_visit",
    "outcome": "recovered",
    "attemptedAt": "2026-07-27T10:15:00+00:00",
    "completedAt": "2026-07-27T10:22:00+00:00",
    "location": "{\\"lat\\": 26.8368, \\"lng\\": 75.681}",
    "customerPresent": true,
    "notes": "Customer handed over the battery at the doorstep.",
    "proofUrls": "[\\"https://smstation.blob.core.windows.net/asset-recovery/proofs/TKT-2026-00024/INSMOMAH1203G0404E09/document_2026-07-24T12-10-19-844672Z.jpg\\"]",
    "metadata": null
  }
]
''';

    final list = (jsonDecode(attemptsJson) as List)
        .cast<Map<String, dynamic>>()
        .map(TicketDetailAttempt.fromJson)
        .toList();

    expect(list, hasLength(2));

    final first = list.first;
    expect(first.id, '658bc80d-9a31-4fa2-8f67-b3e122ff2758');
    expect(first.agentName, 'RANGANATH');
    expect(first.attemptType, 'field_visit');
    expect(first.outcome, 'recovered');
    expect(first.customerPresent, isTrue);
    expect(first.attemptedAt, DateTime.utc(2026, 7, 27, 10, 15));
    expect(first.completedAt, DateTime.utc(2026, 7, 27, 10, 22));
    // location: JSON-encoded object string → decoded lat/lng doubles.
    expect(first.latitude, 26.8368);
    expect(first.longitude, 75.681);
    // proofUrls: JSON-encoded string → real single-element list.
    expect(
      first.proofUrls.single,
      'https://smstation.blob.core.windows.net/asset-recovery/proofs/TKT-2026-00024/INSMOMAH1203G0404E09/document_2026-07-24T12-10-19-844672Z.jpg',
    );
    expect(first.metadata, isNull);

    expect(list.last.notes, 'Customer handed over the battery at the doorstep.');
  });
}
