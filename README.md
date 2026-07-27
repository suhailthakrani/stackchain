<p align="center">
  <img src="https://raw.githubusercontent.com/suhailthakrani/stackchain/main/assets/stackchain_logo.png" alt="Stackchain logo" width="420">
</p>

# stackchain

Config-driven Flutter scaffolding you keep as a **dev dependency** — not a one-shot generator.

Set your stack in `stackchain.yaml`, generate a runnable app, add **vertical slices** as you build, then **sync / upgrade / migrate** as the project evolves. Every generate runs a **quality gate**.

**Docs:** [suhailthakrani.github.io/stackchain-docs](https://suhailthakrani.github.io/stackchain-docs/) · **pub.dev:** [pub.dev/packages/stackchain](https://pub.dev/packages/stackchain)

## Quick start

Requires an existing Flutter app (`flutter create my_app`).

```bash
cd my_app
dart pub add --dev stackchain
dart run stackchain init
flutter pub get
flutter run
```

`init` replaces Flutter’s default counter `lib/main.dart` with a production entrypoint (`configureDependencies` + `App`), scaffolds `lib/app`, `lib/core`, and `lib/features`, writes `.stackchain/lock.yaml`, and runs the quality gate.

Or in `pubspec.yaml`:

```yaml
dev_dependencies:
  stackchain: ^1.1.3
```

No config file needed on first run — production defaults are applied automatically (including secure storage, flavors, and CI).

## Production-grade in few commands

```bash
dart pub add --dev stackchain
# stackchain.yaml
#   preset: production_bloc
#   features: [splash, auth, home, settings]

dart run stackchain init
dart run stackchain feature auth   # session + guards + form + tests + sync
flutter pub get
flutter run -t lib/main_dev.dart --dart-define=FLAVOR=dev
```

What you get out of the box:

| Concern | Generated |
| --- | --- |
| Scalable architecture | feature-first / clean / mvvm / mvc + your state/router/DI |
| Secure session | `SessionService` + secure storage + 401 clears session |
| Auth routing | `RouteGuards` + GoRouter redirect when `auth` exists |
| Network | Dio + auth/retry/error interceptors (retry keeps auth headers) |
| Flavors | `main_dev/staging/prod.dart` + `--dart-define=FLAVOR/API_BASE_URL` |
| Quality | doctor/gate + stricter lints; `strict_quality` fails analyze |
| CI | GitHub Actions: format · analyze · test |
| Evolve | `sync` / `upgrade` / `migrate` — not a one-shot generator |

## Why teams keep it forever

| Capability | What it does |
| --- | --- |
| **Presets** | One-line blueprints (`production_bloc`, `firebase_bloc`, …) |
| **Vertical slices** | `feature` / `rename` / `remove` wire or tear down files + router + DI + tests |
| **Smart sync** | Merges only `<stackchain:…>` regions — hand edits survive |
| **Upgrade** | Refreshes deps, re-syncs, updates lockfile, re-runs gate |
| **Migrate** | Evolve stack intentionally (`bloc` → `cubit`, apply preset) |
| **Doctor / gate** | Structure + security baseline + optional strict analyze |

## Staying ahead (quality-first roadmap)

Ship only when quality is real — no hollow stubs. Next moats competitors won't match if we keep this bar:

1. **OpenAPI → vertical slice** — generate typed models/repos/pages from a spec (quality: compiles + tests)
2. **Architecture linter pack** — `custom_lint` rules that enforce the chosen architecture forever
3. **Token refresh flow** — production refresh queue on 401 (not just clear session)
4. **Offline-first module** — Drift/Isar + cache policy + conflict strategy
5. **Deep links + app links** — platform manifests + GoRouter wired from config
6. **Observability pack** — Crashlytics/`FlutterError`/Zones + analytics that actually initialize
7. **Golden + integration recipes** — per-feature widget goldens and critical-path integration tests
8. **Org brick registry** — share company-approved slices (auth, payments) privately
9. **Security audit command** — `stackchain audit` (pinning checklist, secret scan, insecure defaults)
10. **Melos monorepo mode** — apps + packages from one config without losing sync/migrate

Rule: if it isn't trustworthy in a production app review, it doesn't ship.

## Configuration (`stackchain.yaml`)

### Preset (recommended)

```yaml
stackchain:
  preset: production_bloc
  features:
    - splash
    - auth
    - home
```

List blueprints: `dart run stackchain presets`

### Full

```yaml
stackchain:
  # preset: production_bloc   # optional blueprint; explicit keys win
  architecture: feature_first   # feature_first | clean | mvvm | mvc
  state_management: bloc        # bloc | cubit | riverpod | provider | getx | rxdart
  routing: go_router            # go_router | auto_route | navigator | getx
  di: get_it                    # get_it | injectable | getx
  network: dio                  # dio | http
  storage:
    - shared_preferences
    - secure_storage
  localization: false
  firebase: false
  flavors: true
  ci: true
  strict_quality: false
  features:
    - splash
    - auth
    - home
    - profile
    - settings
```

Omit any key to use the default. If `state_management: getx` and you do not set `routing` / `di`, both default to GetX.

## Commands

```bash
# Help
dart run stackchain help
dart run stackchain help migrate
dart run stackchain help feature

# Scaffold
dart run stackchain init
dart run stackchain init --overwrite
dart run stackchain init --dry-run

# Vertical slice (files + router + DI + tests + gate)
dart run stackchain feature auth
dart run stackchain add notifications
dart run stackchain rename profile account
dart run stackchain remove auth
dart run stackchain remove notifications --dry-run

# Smart merge managed regions (no full overwrite)
dart run stackchain sync

# Evolve the project
dart run stackchain upgrade
dart run stackchain migrate --state cubit --dry-run
dart run stackchain migrate --state cubit
dart run stackchain migrate --preset production_riverpod
dart run stackchain migrate --state cubit --keep-old   # skip cleanup

# Trust
dart run stackchain doctor
dart run stackchain presets

# Generators
dart run stackchain make feature chat
dart run stackchain make page onboarding
dart run stackchain make widget app_chip
dart run stackchain make service sync
dart run stackchain list
dart run stackchain new my_generator
```

Pass `--skip-analyze` to skip the analyzer pass inside the quality gate.

Custom generators live in `.stackchain/bricks/<name>/__brick__/`. Template files end in `.tpl`.

## Smart merges

Generated router/DI files contain managed regions:

```dart
// <stackchain:routes>
GoRoute(path: AppRoutes.home, ...),
// </stackchain:routes>
```

`sync`, `feature`, `upgrade`, and `migrate` replace **only** those regions and merge missing imports. Code outside the markers is preserved.

## Switching state management

`migrate --state <target>` moves the whole project in one command:

- regenerates every feature's state, pages, and bindings for the new stack
- deletes the files the old stack generated and drops packages it no longer needs
- rewires router and DI managed regions, then runs the quality gate

Your `domain/` and `data/` layers are untouched — business logic survives the swap. Only Stackchain-generated files are candidates for deletion, so hand-written files stay. Generated files you edited by hand *are* rewritten, so commit first and preview with `--dry-run`; `--keep-old` skips cleanup entirely.

## What `init` generates

```text
lib/
├── app/           # App widget, theme, config, router
├── core/          # network, storage, di, errors, utils, services, widgets
├── features/      # one module per feature (layout matches architecture)
└── main.dart      # replaces Flutter counter template
.stackchain/
└── lock.yaml      # stack fingerprint for upgrade / migrate
```

Also updates `pubspec.yaml` dependencies, analysis options, and test scaffolding.

## Example stacks

**Preset**

```yaml
stackchain:
  preset: production_bloc
  features: [auth, home]
```

**Bloc + GoRouter + GetIt**

```yaml
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features: [auth, home]
```

**Riverpod**

```yaml
stackchain:
  preset: production_riverpod
  features: [home, profile]
```

**RxDart**

```yaml
stackchain:
  preset: production_rxdart
  features: [auth, home]
```

**GetX + MVC**

```yaml
stackchain:
  preset: getx_mvc
  features: [splash, auth, home]
```

## License

MIT
