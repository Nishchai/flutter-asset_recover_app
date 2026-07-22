# Testing Guide

## Test environment

A dedicated **`test`** environment (`assets/config/environments/test.json`) drives
all automated tests:

- `useMockData: true` — no network.
- `deterministicSeed: 42` — the mock backend, stub location and proof services
  all seed from a fixed RNG, so data and "GPS jitter" are reproducible.
- `MockTicketRepository(latency: Duration.zero)` in tests — instant, no real
  timers, so `pumpAndSettle` never stalls.

`test/helpers/test_harness.dart` (`TestEnv.create()` + `wrapApp()`) resets and
re-configures the **DI container** (`configureDependencies(repository: mock, …)`)
with the deterministic backend, then builds the exact provider + localization +
theme graph the real app uses, with an authenticated agent and tickets
pre-loaded. View-models and use cases are resolved from `get_it`, so tests
exercise the same wiring as production.

## Running

```bash
flutter test                          # all unit + widget tests
flutter test test/unit                # logic only
flutter test test/widget              # UI only
flutter test --coverage               # coverage/lcov.info
flutter test integration_test         # full E2E (needs a device/emulator)
```

## What's covered

### Unit (`test/unit/`)
| File | Verifies |
|---|---|
| `validators_test.dart` | mobile / OTP / non-empty rules |
| `models_test.dart` | GeoPoint haversine, Ticket SLA countdown, JSON round-trip, mobile masking |
| `config_service_test.dart` | real config files parse; SLA=90, 6 languages, outcome metadata, dotted-path flags, deterministic test env |
| `mock_repository_test.dart` | login, cluster tickets, QR validation, **post-decision behaviour** (Swap closes + deploys, FIR stays active), road > aerial distance, OTP |
| `attempt_validation_test.dart` | wizard engine: required dropdown, **mandatory proof gate**, conditional field visibility, OTP-on-recovery, **geo-fence enforcement**, outcome→resolution, terminal-outcome closure |

### Widget (`test/widget/`)
| File | Verifies |
|---|---|
| `task_list_screen_test.dart` | agent header, seeded tickets, segment switching, Start Attempt → wizard |
| `attempt_wizard_test.dart` | wizard renders; **blocks advance without required input**; advances once call status + proof captured |
| `distance_chip_test.dart` | distance formatting + unknown fallback |
| `localization_test.dart` | English full set, Hindi overrides, English fallback for partial languages, `{param}` interpolation, all 6 languages load |

### Integration (`integration_test/recovery_flow_test.dart`)
Full happy path: **login → open ticket → 5-step wizard (Call, Location, Home,
Outcome=Organic Swap, Review) → submit → back to task list**, driving the real
app widget tree.

## Acceptance-criteria traceability (PRD §5.2.A)

| Criterion | Test |
|---|---|
| Agent cannot proceed without proof | `attempt_validation_test` / `attempt_wizard_test` |
| Outcome selection mandatory | `attempt_validation_test` |
| GPS / geo-fence enforced | `attempt_validation_test` (within/outside fence) |
| QR validates correct BP, blocks incorrect | `mock_repository_test` |
| Swap moves BP to deployed zone without manual step | `mock_repository_test` |
| OTP mandatory for physical recovery | `attempt_validation_test` |
| Tasks sorted by distance | `TicketProvider` sort (covered via task list) |
| Multi-language UI | `localization_test` |
| Attempt recorded sequentially with outcome | `mock_repository_test` + closed-ticket history |

## Adding tests

Use `TestEnv.create()` for anything needing config/services, and `wrapApp(env,
yourWidget)` for widget tests. Keep `latency: Duration.zero` (already the harness
default) to avoid timer-related flakiness.
