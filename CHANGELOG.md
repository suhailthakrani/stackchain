# Changelog

## 1.4.1

- **App shell safety** — `migrate` refuses to overwrite customized `bootstrap` / `main` / `app.dart` (stock shells still swap); use `--force-shell` to clobber
- **Marker integrity** — `doctor` fails when managed region bodies (`routes`, `core`, `features`, `handlers`, `generated`) were hand-edited
- **CI** — generated workflow runs `dart run stackchain doctor --skip-analyze`
- **Honest `api` docs** — README + CLI state MVP limits: schemas → DTO + stub repos, guessed paths, no DI wiring
- **Fix** — `RegionMerger` only matches markers that sit alone on a line (doc comments mentioning `<stackchain:…>` no longer corrupt DI sync)

## 1.4.0

- **`api <spec>`** — generate models + API repositories from OpenAPI 3 schemas (`lib/core/api/`); re-run safe via `generated` / `custom` markers; remembers last spec in `.stackchain/openapi.yaml`
- **DI cleanup** — `injection.dart` is documented, import-grouped, and sectioned (logging, storage, session, network, per-feature)
- Widen Dart SDK constraint to `>=3.0.0 <4.0.0` so apps are not locked to a narrow SDK floor
- Loosen `lints` to `>=3.0.0 <6.0.0` so older Dart SDKs can still resolve the package

## 1.3.1

- **Fix migrate / `feature --overwrite`:** rewrite presentation pages for the new state API (Bloc → Cubit, etc.) while preserving `// <stackchain:custom>`
- **Fix quality gate:** `dart analyze` errors/warnings always fail the gate (no longer “non-blocking”)
- **Fix `production_riverpod` (and any `localization: true`):** add `flutter_localizations` SDK dep, enable `generate: true`, stop pinning conflicting `intl: ^0.19.0`
- **Fix migrate shell:** state-only migrates no longer wipe router/DI files — `ProjectSync` updates markers and keeps hand-written code outside them
- Page templates wrap UI in `// <stackchain:generated>` for safe soft-merge refreshes

## 1.3.0

- Richer shippable recipes: deepen auth (form + widget test) and settings (preferences + persistence test); add onboarding, notifications, search
- Add `crud <entity>` for list tile + form + form tests on top of a vertical slice
- Add `stub <feature>` (and `test --stub-custom`) to scan `// <stackchain:custom>` and append placeholder tests
- Add `doctor --fix`: detect marker/lock/orphan drift and auto sync + refresh lockfile

## 1.2.0

- Add `test <feature>` to generate unit, widget, and integration tests (`--type`, `--all`, `--overwrite`)
- Preserve user code in `// <stackchain:custom>` regions across `migrate` / `feature` / `test`
- Port custom regions when state management changes (e.g. Bloc → Cubit)
- Add `test/features/<feature>_custom_test.dart` (never overwritten)
- Scaffold tests use `// <stackchain:generated>` regions (safe refresh)
- Legacy unmarked customized files are backed up as `*.stackchain.bak` before replace

## 1.1.4

- Clarify README for pub.dev: quicker onboarding, full support matrix, examples, and contribution / support call-to-action

## 1.1.3

- Harden `migrate` so any stack change refreshes bootstrap/app/router/DI and feature tests (not only presentation files)
- Add `rename <from> <to>` for end-to-end feature rename (yaml + files + tests + router/DI)
- Add `remove <name>` — delete a feature's files/tests, drop it from `stackchain.yaml`, and re-sync router/DI (strips auth redirect when removing `auth`)

## 1.1.2

- Point homepage / documentation to the official docs site: https://suhailthakrani.github.io/stackchain-docs/

## 1.1.1

- `migrate` now cleans up the old stack: deletes the state files it generated and drops packages the new stack no longer needs (`--keep-old` to opt out)
- Fix `migrate` / `upgrade` / `sync` on older apps: create missing `SessionService` and upgrade legacy Dio, environment, and route guard files
- Fix package logo on pub.dev

## 1.1.0

- Keep scaffolding after init: `sync`, `upgrade`, and `migrate`
- `feature` / `add` now wires router, DI, and tests automatically
- `doctor` and a quality gate on every generate
- Presets for common production stacks
- Secure session + route guards, flavors, and CI workflow out of the box
- RxDart as a state management option
- `dart run stackchain help` (and `help <command>`)

## 1.0.0

- `stackchain` — config-driven Flutter scaffolding via `stackchain.yaml`
- Architectures: feature_first, clean, mvvm, mvc
- State: bloc, cubit, riverpod, provider, getx
- Routing: go_router, auto_route, navigator, getx
- DI: get_it, injectable, getx
- Network: dio, http
- Commands: `dart run stackchain init|feature|make|list|new` (positional names)
- `init` replaces Flutter’s default counter `lib/main.dart`
- Ongoing generators for features, pages, widgets, services
- Custom generators under `.stackchain/bricks/`
