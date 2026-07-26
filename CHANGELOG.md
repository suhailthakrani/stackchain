# Changelog

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
