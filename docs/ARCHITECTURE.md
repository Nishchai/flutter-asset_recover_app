# Architecture

## Goals

1. **Config-driven** — business rules, UI flow, theme and copy live in JSON, not
   Dart. Product/ops can retune without a code release.
2. **Backend-swappable** — screens depend on an interface, never on HTTP. Mock
   today, real API tomorrow, one flag flip.
3. **Testable** — deterministic mock backend + injectable services make unit,
   widget and integration tests fast and reproducible.

## Layers (Clean Architecture)

```
┌──────────────────────────────────────────────────────────────┐
│ presentation/   features/<f>/ screens+widgets · state/ (VMs)  │
├──────────────────────────────────────────────────────────────┤
│ domain/         entities/ · repositories/ (interfaces) ·      │
│                 usecases/ (interactors, return Result<T>)     │
├──────────────────────────────────────────────────────────────┤
│ data/           repositories/  MockTicketRepository           │
│                                 ApiTicketRepository            │
├──────────────────────────────────────────────────────────────┤
│ core/           config · di (get_it) · error (Result/Failure) │
│                 localization · theme · services · utils       │
└──────────────────────────────────────────────────────────────┘
   ▲ assets/config/*.json   ▲ assets/l10n/*.json
```

Dependencies point inward: `presentation → domain ← data`, everything → `core`.
The domain layer is pure Dart (no Flutter imports). Full pattern catalogue in
**docs/PATTERNS.md**.

## Composition root (Dependency Injection)

`core/di/injector.dart` (`get_it`) is the **only** place that decides mock vs.
real backend and wires the whole graph: core services → `TicketRepository`
(chosen from `EnvironmentConfig.useMockData`) → use cases → presentation
view-models. `main.dart` calls `configureDependencies()`; tests call it with
overrides for a deterministic, zero-latency mock and `resetDependencies()`
between runs. `AppServices` (`core/di/app_services.dart`) is a thin **Facade**
exposing config + device services to screens.

## State management

Provider (`ChangeNotifier`) — deliberately lightweight:

- `AuthProvider` — sign-in + current `Agent`.
- `TicketProvider` — assigned tickets, segment filtering, sort, distance refresh,
  attempt submission.
- `AttemptController` — created per wizard session; holds dynamic field values +
  captured proofs, evaluates visibility/requirement rules, validates each step
  (mandatory proof, geo-fence, OTP, phone), builds and submits the `Attempt`.

## The config-driven wizard engine

`attempt_flow.json` → parsed into `AttemptFlowConfig` (`StepConfig` +
`FormFieldConfig`). The engine:

- Renders one widget per field `type` (`dynamic_field.dart`).
- Computes visibility from `visibleWhen` (`equals` / `in` against another field).
- Computes "required" from `required`, `requiredFlag` (a config flag path) or a
  feature flag.
- Enforces geo-fence on `recovery` proof and OTP on physical-recovery outcomes.
- Auto-builds the Review summary from whatever fields were captured.

Adding a step or field, changing which outcomes demand an amount, or making FIR
documents mandatory is a **JSON edit** — no Dart.

## Data model (PRD §7 core entities)

`Ticket` → `Battery (BP)` → `Attempt` → `Proof`. `Attempt.values` is an open
map keyed by wizard field id, so new wizard fields never require a model change.

## Theming

`theme_config.json` → `AppPalette` (semantic colors, case-type & outcome colors)
→ `AppTheme.build()` produces `ThemeData`. Screens read `AppPalette` from
Provider; no hard-coded colors.

## Localization

Custom JSON delegate (`core/localization/app_localizations.dart`) with English
fallback and `{param}` interpolation. Avoids code-gen so adding a language is a
single asset file. `flutter_localizations` supplies Material/Cupertino strings
for the 6 supported Indian locales.
