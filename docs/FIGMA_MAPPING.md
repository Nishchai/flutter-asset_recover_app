# Figma → Code Mapping

Source: **Asset Assurance** export (`Asset Assurance.zip`) — flow boards and
individual screens. This release implements those designs.

## Design system

| Token | Value | Notes |
|---|---|---|
| Primary (acid yellow) | `#E2E300` | BP serials, highlights, yellow CTAs |
| Hero gradient | `#0A0D14 → #1B2336` | dark headers / result heroes |
| Dark surface | `#141A27` (border `#2A3142`) | stat cards, chips on dark |
| Light background | `#F6F6F3` | content area |
| Danger | `#E5484D` | wrong battery, SLA-critical, days-left |
| CTAs | dark pill + yellow text, **or** yellow pill + dark text | `shared/widgets/pill_button.dart` |

All tokens live in `assets/config/theme_config.json`.

## Screen mapping

| Figma screen / flow | Implementation |
|---|---|
| **Flow 5 – Navigation** : Home (shift toggle, stats, filters, ticket cards) | `features/tasks/task_list_screen.dart` + `widgets/shift_header.dart` + `widgets/ticket_card.dart` |
| **Flow 5** : BP detail (BATTERY PACK header, SLA banner, customer, attempt history) | `features/tasks/ticket_detail_screen.dart` |
| **Flow 5** : Call screen + Call Documentation (Step 1/2) | wizard step `call` — `features/attempt/`, `assets/config/attempt_flow.json` |
| **Flow 5** : Navigate to location / Slide-to-arrive | navigation + arrival captured by the wizard (`captureArrival`) |
| **Flow 5** : Location proof + Battery Documentation (Step n/4) | wizard steps `location_visit`, `home_visit` |
| **Flow 6 – Recovery Attempt** : Battery scanner (scanning / Identified / detected) | `features/qr/qr_scan_screen.dart` |
| **Flow 6** : Wrong battery detected | `qr_scan_screen.dart` (`_ScanState.wrong`) |
| **Confirmation Screen** : QR Matched | `features/qr/qr_result_screen.dart` (`matched: true`) |
| **QR mismatch** : scanned vs expected, blocked | `qr_result_screen.dart` (`matched: false`) |
| **Daily logout flow** : end-of-shift OTP sheet | `features/tasks/widgets/end_shift_sheet.dart` + `state/shift_provider.dart` |
| **Daily logout flow** : "Oops — outside shift zone" | geo-fence enforcement (`attempt_controller.dart`, `validation.geofence`) |
| **Flow 7 – FIR** | outcome `fir_lost` + `firDocument` upload field (config-driven) |
| **Flow 10 – Retry** | re-attempt — unlimited attempts per BP |

## Personas / IDs (from the Figma)

- Agent **Rohan M.** (RM), cluster **Bengaluru South · Zone 4**
- Tickets **TKT-48217**, batteries **BP-IF-09823-A**, VIN **MD9KS5C46N125679**
- Customer **Gulshan Kumar**, vehicle **3W – Passenger Auto**

## Notes / deviations

- The live camera, GPS, maps and QR decode are **stub services** (the app runs
  with no native setup). Each documents the production plugin to drop in
  (`mobile_scanner`, `geolocator`, `image_picker`, `google_maps_flutter`). The
  validation, geo-fence and result-routing logic is production-ready.
- The multi-step "Step X/N" counters in the Figma vary per sub-flow; the unified
  wizard shows `Step {index}/{total}` over its configured steps.
- Source render assets used during implementation are not shipped in the app.
