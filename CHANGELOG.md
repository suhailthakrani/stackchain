# Changelog

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
