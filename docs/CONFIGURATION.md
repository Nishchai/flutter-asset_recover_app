# Configuration Guide

All runtime behaviour is driven by JSON under `assets/config/`. After editing any
file, hot-restart (config is loaded once at startup).

## Files

| File | Controls |
|---|---|
| `app_config.json` | Business rules, session, location/geo-fence, proof mandates, feature flags, navigation, task list, localization defaults |
| `theme_config.json` | Colors, case-type/outcome colors, typography, radii, spacing |
| `dropdowns.json` | All selectable option sets + outcome metadata |
| `attempt_flow.json` | The recovery attempt wizard — steps, fields, rules |
| `api_endpoints.json` | Endpoint method+path strings (relative to base URL) |
| `environments/{dev,test,prod}.json` | Per-environment base URL, mock toggle, keys |

## Common changes

### Change the SLA
`app_config.json`:
```json
"business": { "slaDays": 90, "slaWarnDays": 7 }
```
Recovery attempts are not capped — an agent can log as many attempts per battery
pack as a case needs.

### Change the geo-fence radius / disable enforcement
```json
"location": { "geofenceRadiusMeters": 50, "enforceGeofenceOnRecovery": false }
```

### Change how often the agent's location is reported
`PATCH /agents/location` runs on a heartbeat while the app is in the foreground.
Set `0` to switch the heartbeat off, leaving only the reports fired when the
agent lands on the home screen.
```json
"location": { "reportIntervalMinutes": 5 }
```

### Make a proof optional
```json
"proof": { "mandatoryForHomeVisit": false }
```

### Toggle a feature
```json
"features": { "inAppCalling": true, "firDocumentMandatory": true }
```

### Add / change an outcome
`dropdowns.json → outcome[]`. Each option:
```json
{ "value": "impounded", "labelKey": "opt.outcome.impounded",
  "resolution": "Impounded", "terminal": true, "requiresApproval": true }
```
Add the `opt.outcome.impounded` key to every `assets/l10n/*.json` (English is
the fallback).

### Add a wizard field
`attempt_flow.json` → pick a step → add to `fields[]`:
```json
{ "id": "vehicleConditionNote", "type": "textarea",
  "labelKey": "field.vehicle_condition", "maxLines": 3 }
```
Field `type`: `readonly | text | textarea | number | phone | dropdown | proof | otp`.

Optional keys:
- `required`: true — always mandatory.
- `requiredFlag`: `"proof.mandatoryForCall"` — mandatory iff that config flag is true.
- `featureFlag`: `"features.customerDetailUpdate"` — hidden unless flag true.
- `visibleWhen`: `{ "field": "outcome", "in": ["refused"] }` or `{ "field": "outcome", "equals": "recovered" }`.
- `optionsRef`: name of a list in `dropdowns.json` (for `dropdown`).
- `group`: same value on two adjacent fields renders them side-by-side.
- `prefix`, `hintKey`, `maxLines`, `proofKind`, `sourceField`, `iconKey`.

### Add a wizard step
Add a `StepConfig` object to `attempt_flow.json → steps[]` with `id`, `icon`
(`phone|location|home|package|check`), `titleKey` and `fields[]`. Add the
`titleKey` to the localization files. The step indicator and navigation adapt
automatically. Keep the `isReview: true` step last.

### Add a language
1. Create `assets/l10n/<code>.json` (copy `en.json`, translate).
2. Add `<code>` to `app_config.json → localization.supportedLanguages`.
3. Add the display name in `features/profile/profile_screen.dart` `_names` (or it
   falls back to the code). Missing keys fall back to English automatically.

### Rebrand colors
`theme_config.json → colors.primary` etc. Hex `#RRGGBB` or `#AARRGGBB`.

### Reorder / rename bottom tabs
`app_config.json → navigation.items` (`id` ∈ `tasks|map|profile`, `labelKey`,
`icon` ∈ `checklist|map|person`).
