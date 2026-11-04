# Play Console — Data safety answers (draft)

Derived from the code (geolocator, image_picker, mobile_scanner, url_launcher,
http, azblob, flutter_secure_storage, Gupshup OTP, Azure AD token, Google Maps).
Re-check each answer against the final privacy policy before submitting.

## Top-level questions

| Question | Answer |
|---|---|
| Does the app collect or share any required user data types? | Yes |
| Is all collected data encrypted in transit? | Yes (HTTPS; release build blocks cleartext) |
| Do you provide a way for users to request data deletion? | Yes — by email request (give the URL/email from the privacy policy) |
| Independent security review? | No |

## Data types

"Shared" below means transferred to a third party. Service providers acting only
on your behalf (Azure hosting, Gupshup SMS) are **not** "sharing" under Play's
definition, but Google Maps receives location for map rendering/navigation only
if you consider it a transfer — confirm with Legal; the conservative choice is
to declare it as shared for App functionality.

| Category → Type | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Location → Approximate location | Yes | No | Required | App functionality |
| Location → Precise location | Yes | No (see note) | Required | App functionality |
| Personal info → Name | Yes | No | Required | App functionality, account management |
| Personal info → Phone number | Yes | No | Required | App functionality, account management |
| Personal info → User IDs | Yes | No | Required | App functionality, account management |
| Personal info → Address | Yes (customer address on tickets) | No | Required | App functionality |
| Photos and videos → Photos | Yes | No | Required | App functionality |
| App activity → Other user-generated content / in-app actions | Yes (attempt records, audit log) | No | Required | App functionality |
| Phone/call data | Not a listed Play category — covered by **Personal info → Phone number** and **App activity** (call duration). State in the policy. | | | |

Not collected: financial info, health, messages, contacts, audio/voice
recordings, files & docs, calendar, web browsing, device/other IDs for ads,
crash logs/diagnostics (no Crashlytics/analytics SDK in pubspec).

## Data handling

- Data is processed ephemerally? **No** — records and photos are stored server-side.
- Users can request deletion: **Yes**.
- Committed to Play Families policy: **No** (not a child-directed app).

## Permissions Declaration / sensitive permission notes

- `CALL_PHONE`, `READ_PHONE_STATE`: core feature = calling the customer from the
  Call Customer screen. Prepare the demo video (see reviewer-access.md).
- `ACCESS_FINE/COARSE_LOCATION`: foreground only; no background location.
- `CAMERA`: proof photos, QR scan.
