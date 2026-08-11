# API Integration Guide

The app runs on a **mock backend** by default. This guide explains how to point
it at real services once endpoint details are provided.

> The integration surface is intentionally tiny: **one interface**
> (`TicketRepository`), **one HTTP wrapper** (`ApiClient`) and **one config file**
> (`api_endpoints.json`). UI/state code does not change.

## 1. Switch on the real backend

In the target environment file (`assets/config/environments/prod.json` —
copy from `prod.sample.json`):

```json
{ "useMockData": false,
  "apiBaseUrl": "https://asset-recovery.sunmobility.com/api/v1",
  "mapsApiKey": "…", "apiTimeoutSeconds": 30 }
```

Select the environment at launch:
```bash
flutter run --dart-define=ENV=prod
```
`configureDependencies()` (`lib/core/di/injector.dart`) then registers
`ApiTicketRepository` instead of the mock — the single backend-wiring decision.

## 2. Map the endpoints

`assets/config/api_endpoints.json` holds `"METHOD /path/{param}"` strings,
relative to `apiBaseUrl`. Update paths to match the real contract — **no code
change** needed for routing:

```json
"attempts": { "create": "POST /tickets/{ticketId}/batteries/{bpId}/attempts" }
```

`ApiClient.call('attempts.create', pathParams: {...}, body: {...})` resolves the
method + path, fills `{param}` segments, attaches the bearer token and timeout.

## 3. Map request/response shapes

`ApiTicketRepository` translates between the JSON contract and the app models.
The lines to adjust are marked `// MAP:`. Example:

```dart
final res = await _api.call('auth.verifyOtp', body: {...});
_api.authToken = res['token'];                 // MAP: token field name
return Agent.fromJson(res['agent']);           // MAP: agent envelope
```

The model `fromJson` / `toJson` methods (in `data/models/`) define the field
names the app expects. Either align the backend to them or adjust the mapping
here — keep one source of truth.

## 4. Endpoints the app needs

| Capability | Config key | Used by |
|---|---|---|
| Partner directory lookup (login step 1) | `auth.commonLogin` | sign-in |
| Mobile OTP request/verify (login) | `auth.requestOtp` / `auth.verifyOtp` | sign-in |
| Assigned tickets (cluster-scoped) | `tickets.assigned` | task list |
| Ticket detail | `tickets.detail` | detail screen |
| Submit attempt | `attempts.create` | wizard |
| Proof upload | `proof.upload` | proof capture |
| QR scan validation | `qr.validate` | QR screen |
| Road distance | `distance.roadDistance` | distance refresh |
| Planned route for the shift | `agent.route` | map tab |
| Customer update | `customer.update` | BP detail |
| Handover OTP request/verify | `otp.request` / `otp.verify` | physical recovery |

## 5. Native integrations (separate from the API)

These are device plugins, wired independently of the backend (see stubs in
`core/services/` and the commented plugin blocks):

- **GPS / geo-fence** — `geolocator` → replace `StubLocationService`.
- **Proof camera** — `image_picker` / `camera` → replace `StubProofService`
  (burn lat/lng/timestamp overlay before upload).
- **QR scanning** — `mobile_scanner` → feed the decoded serial into
  `repository.validateScan(...)` (logic already implemented).
- **Maps** — `google_maps_flutter` is already wired in `features/map/map_screen.dart`
  (needs a valid API key + billing enabled on the Google Cloud project).
- **Call recording** — Exotel / Ozonetel (PRD §5.2.3) — feasibility TBD; the
  `callRecordingProvider` env field is the wiring point.

## 6. Auth, RBAC & cluster scoping

### The login flow (two steps)

1. **`auth.commonLogin`** — the moment the agent submits their mobile number,
   `GET https://sm-partners-api.azurewebsites.net/api/v1/commonLogin?appName=INDOFAST_PARTNER&userMobilenumber=<mobile>`
   resolves it against the SM-Partners directory. The response envelope is
   `{status, reason, data}`; `data` maps to `PartnerLoginData` and **is** the
   real agent record (`userId`, `userName`, `partnerId`, `userRole`, …).
   A non-200 `status`, a missing `data`, or `isActive: false` aborts the login
   with the backend's own `reason` shown under the mobile field — **no OTP is
   sent**.
2. **OTP send → verify → token mint** — only on a step-1 success. The agent
   identity persisted for the session is `PartnerLoginData.toAgent()`, whose
   `Agent.id` is the **`partnerId`** (falling back to `userId`, then the mobile
   number). `cluster` / `zone` / `recoveredCount` are not in the partner payload,
   so they come from whatever the recovery backend supplied (`toAgent(base: …)`).

`userRole` is mapped by `agentRoleFromString`, which falls back to
`AgentRole.fieldAgent` for any value it doesn't recognise — Phase 1 is
field-agent-only, so an unexpected role never locks an agent out.

### Request scoping (`agentId`)

`ApiClient` attaches `agentId=<userId>` to every **relative** endpoint —
the `userId` (the `SUNMU…` series) from the `commonLogin` response, exposed as
`PersistedSession.apiAgentId` and pushed into `ApiClient.agentId` by
`SessionStore` on restore / login / logout. Nothing is hard-coded, and the value
survives restarts with the session.

Endpoints with an `{agentId}` **path** segment (e.g. `tickets.stats`) are filled
by their callers from `Agent.id`, which is that same `userId` — one id
everywhere, so the query param and the path segment can never disagree.

- No session → the param is **omitted** (never sent empty).
- No `userId` in the payload → falls back to `partnerId`, then the mobile number.
- The 401 token swap deliberately leaves it untouched: same agent, new
  credential, and the retried request still needs its scope.
- Absolute endpoint URLs (Battery Master, `commonLogin`, the attempts service)
  never receive it.

- The bearer token from `auth.verifyOtp` is held by `ApiClient` and sent on
  every request.
- Cluster-based data access (PRD §4.6) is expected to be enforced **server-side**
  on `tickets.assigned`; the app additionally only ever requests the signed-in
  agent's tickets.

### Session persistence (login shown only once)

`SessionStore` (`lib/core/services/session_store.dart`) persists the access
token + signed-in `Agent` in encrypted storage — Android
EncryptedSharedPreferences, iOS Keychain (`flutter_secure_storage`). The token
never touches plain SharedPreferences. Nothing else writes
`ApiClient.authToken`: every transition below flows through the store's
`onAuthTokenChanged` sink, wired in `configureDependencies`.

| Event | Store call | Effect |
|---|---|---|
| OTP verified | `save(token + agent + commonLogin profile)` | last time the login screens are shown |
| App launch | `restore()` (in `configureDependencies`, before any UI) | `AuthProvider` is constructed already logged in → `_RootRouter` opens `HomeShell` |
| **401** on any `ApiClient.call` | `clearAuthToken()` → re-mint → `replaceAuthToken(new)` | rejected token erased, fresh one saved, request retried once, agent stays signed in — no re-entry of mobile/OTP |
| Logout / 12 h auto-logout | `clear()` | next launch starts at the login screen |

Two consequences worth knowing:

- A **restored token may already be expired** (client-credentials tokens are
  ~1 h). That is fine and needs no startup network call: the first API request
  401s, `ApiClient.onUnauthorized` re-mints silently and replays it.
- If the re-mint itself fails, the token is already gone from disk, so the next
  launch asks for the OTP again rather than restoring a credential the backend
  refuses.

The `test` environment uses `InMemorySessionStore` — `flutter_secure_storage`
needs platform channels that `flutter_test` does not provide.

## 7. Offline & failures

`features.offlineQueue` is a flag placeholder for a future submit-queue. Today,
`ApiClient` surfaces `ApiException` with status + body; wrap repository calls in
your preferred retry/queue policy (PRD §7 ingestion acceptance criteria mention
retries on the server side).
