# Asset Recovery App (Flutter)

Mobile application for **SUN Mobility / Smart Network** field agents to identify,
track and recover at-risk / theft battery packs (BPs). Built to **PRD v0.3 §5.2
(Mobile Application — Field Agent)** and the **Asset Assurance Figma flows**
(Navigation, Recovery Attempt, QR scan/confirmation, Daily-logout).

> **Phase 1 scope:** Retail customer recovery workflows. Fleet workflows (MVP2)
> are out of scope.

**This release matches the Asset Assurance Figma design** — a dark navy + acid-
yellow (`#E2E300`) system with:
- a **shift-based home** (shift toggle, SHIFT ACTIVE banner, Assigned / In
  Progress / Pending stats, All/Open/In-Progress/Pending filters);
- a **BP detail** screen (dark header, SLA-critical banner, customer + battery
  attributes, attempt history) leading into the recovery flow;
- a **QR verification flow** — scanner (scanning / detected / wrong states),
  **QR Matched** and **QR Mismatch** result screens with scanned-vs-expected;
- an **end-of-shift OTP** flow (Daily logout); and
- the multi-step **documentation wizard** (Call → Location → Battery → Outcome →
  Review) with "Step X/N" dark headers.

It remains a **config-driven** app: theme, languages, navigation, business rules
(SLA, attempt limits, geo-fence, session timeout) and the entire **attempt
wizard** are defined in JSON under `assets/config/` — no code changes needed to
retune them. The data layer sits behind a repository interface with a **seeded
mock backend**, so the app runs end-to-end today and swaps to live APIs via a
single environment flag once endpoints are provided.

IDs/personas follow the Figma: agent **Rohan M.**, tickets **TKT-48217**,
batteries **BP-IF-09823-A**.

---

## Quick start

```bash
# 1. Generate the platform runner folders (android/ios/web) for this source tree.
#    Safe to run — it only adds the missing platform scaffolding, not lib/ or assets/.
flutter create .

# 2. Fetch packages and run.
flutter pub get
flutter run                          # 'dev' environment (mock data)
flutter run --dart-define=ENV=test   # deterministic test environment
```

Demo login: any Agent ID + password (mock mode). Pre-filled as `FA-RM-01` / `demo`.
The project folder name contains spaces — quote it: `cd "Asset Recovery App"`.

**Requirements:** Flutter ≥ 3.24, Dart ≥ 3.5.

> This package ships the application source (`lib/`, `assets/`, `test/`,
> `integration_test/`) only. `flutter create .` adds the `android/`, `ios/`,
> `web/` runners without touching any existing file.

---

## What's implemented (mapped to the PRD)

| Area | Where |
|---|---|
| Shift home — toggle, banner, stats, filters, ticket cards | `presentation/features/home/` (`task_list_screen`, `widgets/shift_header`, `widgets/ticket_card`) |
| BP detail — dark header, SLA banner, customer/battery, attempt history | `presentation/features/ticket_detail/ticket_detail_screen.dart` |
| Recovery documentation wizard (Call → Location → Battery → Outcome → Review) | `presentation/features/attempt/` + `assets/config/attempt_flow.json` |
| QR scanner (scanning / detected / wrong) | `presentation/features/qr/qr_scan_screen.dart` |
| QR Matched / QR Mismatch result screens | `presentation/features/qr/qr_result_screen.dart` |
| End-of-shift OTP (Daily logout) | `presentation/features/home/widgets/end_shift_sheet.dart`, `presentation/state/shift_provider.dart` |
| Mandatory geo-tagged proof + geo-fence validation | `presentation/state/attempt_controller.dart`, `core/services/` |
| Post-decision behaviour (Swap/Recovered/FIR zone + closure) | `data/repositories/mock_ticket_repository.dart` |
| Multi-language UI (6 languages) | `assets/l10n/`, `core/localization/` |
| Auto-logout (12h, configurable) | `core/services/session_manager.dart` |
| Map view + nearest case | `presentation/features/map/map_screen.dart` |

The outcome → resolution mapping (Swap Organic/Assisted, Recovered, FIR/Lost),
approval requirements, OTP-on-recovery and FIR-document rules are all encoded in
`assets/config/dropdowns.json` and enforced by the wizard engine.

---

## Project structure (Clean Architecture)

Layered `core / domain / data / presentation`; dependencies point inward.
Design-pattern catalogue: **docs/PATTERNS.md**.

```
lib/
  main.dart                  Entry — configures DI, runs the app
  app/asset_recovery_app.dart Root widget: provider scopes, theme, routing
  core/
    config/                  ConfigService, environment, options model
    di/                      injector.dart (get_it composition root) + AppServices facade
    error/                   Result<T> + Failure (functional error handling)
    localization/  theme/    JSON localization engine, AppTheme/palette
    services/                location, proof, session, api_client (adapters/stubs)
    utils/                   validators, formatters
  domain/                    ← pure business core (no Flutter)
    entities/                Ticket, Battery, Attempt, Customer, Proof, Agent, ShiftStats, enums, form configs
    repositories/            TicketRepository (interface)
    usecases/                Login, GetAssignedTickets, GetShiftStats, SubmitAttempt,
                             ValidateBatteryScan, GetRoadDistance, … (Interactors → Result<T>)
  data/
    repositories/            MockTicketRepository · ApiTicketRepository (implement the interface)
  presentation/
    state/                   AuthProvider, TicketProvider, ShiftProvider, AttemptController (ChangeNotifier VMs)
    features/                auth, home, ticket_detail, attempt, qr, map, profile (screens + widgets)
    shared/widgets/          pill button, info chip, status badge, proof capture
android/                     Android module — minSdk 26 (Android 8.0+)
assets/  config/ · l10n/     JSON config + 6 languages
test/                        unit + widget tests + DI-aware harness
integration_test/            full recovery-flow E2E
docs/                        ARCHITECTURE, PATTERNS, CONFIGURATION, API_INTEGRATION, TESTING, FIGMA_MAPPING
```

## Dependency injection

`core/di/injector.dart` (**get_it**) is the single composition root. `main.dart`
calls `configureDependencies()`, which picks the mock or real repository from the
environment and wires use cases + view-models. Tests inject a deterministic mock
via `configureDependencies(repository: …)` and isolate with `resetDependencies()`.

## Android 8+ compatibility

The bundled `android/` module sets `minSdk = 26` (Android 8.0 Oreo) in
`android/app/build.gradle.kts`, uses an adaptive launcher icon, and declares the
camera/location/internet permissions the recovery flow needs. The Gradle wrapper
binary and `local.properties` are generated by the Flutter toolchain — see
`android/README.md`.

---

## Configurability (the core requirement)

Everything below is data, not code — see **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)**:

- **Theme** — colors, radii, typography → `theme_config.json`
- **Languages** — add a `assets/l10n/<code>.json` + list it in `app_config.json`
- **Navigation tabs** — `app_config.json → navigation.items`
- **Business rules** — SLA days, max attempts, geo-fence radius, session timeout, proof mandates, feature flags → `app_config.json`
- **Dropdowns** — call statuses, outcomes, helping factors, pending reasons → `dropdowns.json`
- **The attempt wizard itself** — steps, fields, field types, required rules, conditional visibility → `attempt_flow.json`

---

## API integration

The app ships in **mock mode**. When backend endpoints are confirmed:

1. Fill `assets/config/environments/prod.json` (copy from `prod.sample.json`).
2. Set `useMockData: false`.
3. Adjust endpoint paths in `assets/config/api_endpoints.json` and the response
   field mappings (lines marked `// MAP:`) in `ApiTicketRepository`.

Full guide: **[docs/API_INTEGRATION.md](docs/API_INTEGRATION.md)**.

---

## Testing

```bash
flutter test                              # unit + widget tests
flutter test integration_test             # full E2E recovery flow (device/emulator)
```

The `test` environment seeds a deterministic, zero-latency mock backend so runs
are fast and reproducible. Details: **[docs/TESTING.md](docs/TESTING.md)**.

---

## Notes & assumptions

- **Native device features** (camera, GPS, maps, QR) ship as **stub services**
  so the app compiles and runs with no platform setup. Each stub documents the
  real plugin to drop in (`geolocator`, `image_picker`, `google_maps_flutter`,
  `mobile_scanner`). Uncomment them in `pubspec.yaml` and swap the service
  implementation in `core/app_services.dart`.
- The Figma reconstruction is based on the mockups embedded in the PRD. The
  orange *Submit Attempt* flow (node 29-12) is the primary design; the QR-scan,
  map and case-detail screens are unified under one configurable theme.
- No real customer data is bundled — the seed set is synthetic and mirrors the
  mockup names/IDs for visual parity.
