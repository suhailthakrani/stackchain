# stackchain

Config-driven Flutter scaffolding you keep as a **dev dependency**.

Set your stack in `stackchain.yaml`, generate a runnable app, then keep adding features, pages, widgets, and services as the project grows — without recreating the same folders by hand.

## Quick start

Requires an existing Flutter app (`flutter create my_app`).

```bash
cd my_app
dart pub add --dev stackchain
dart run stackchain init
flutter pub get
flutter run
```

`init` replaces Flutter’s default counter `lib/main.dart` with a production entrypoint (`configureDependencies` + `App`), and scaffolds `lib/app`, `lib/core`, and `lib/features`.

Or in `pubspec.yaml`:

```yaml
dev_dependencies:
  stackchain: ^1.0.0
```

No config file needed on first run — production defaults are applied automatically.

## Why keep it in every project

| | |
| --- | --- |
| **Flat config** | `stackchain.yaml` is readable in under a minute |
| **Your stack** | Architecture, state, routing, DI, and network — your choice |
| **Real code** | Generates runnable Dart/Flutter files, not empty folders |
| **Ongoing use** | Add features and files later with the same package |
| **Defaults** | Works with zero configuration |

## Configuration (`stackchain.yaml`)

### Minimal (enough for most apps)

```yaml
stackchain:
  features:
    - auth
    - home
    - profile
```

### Full

```yaml
stackchain:
  architecture: feature_first   # feature_first | clean | mvvm | mvc
  state_management: bloc        # bloc | cubit | riverpod | provider | getx
  routing: go_router            # go_router | auto_route | navigator | getx
  di: get_it                    # get_it | injectable | getx
  network: dio                  # dio | http
  storage:
    - shared_preferences
    - secure_storage
  localization: false
  firebase: false
  features:
    - splash
    - auth
    - home
    - profile
    - settings
```

Omit any key to use the default. If `state_management: getx` and you do not set `routing` / `di`, both default to GetX.

## Supported options

| Area | Options |
| --- | --- |
| Architecture | `feature_first`, `clean`, `mvvm`, `mvc` |
| State | `bloc`, `cubit`, `riverpod`, `provider`, `getx` |
| Routing | `go_router`, `auto_route`, `navigator`, `getx` |
| DI | `get_it`, `injectable`, `getx` |
| Network | `dio`, `http` |
| Storage | `shared_preferences`, `hive`, `secure_storage` |

## Defaults

| Setting | Default |
| --- | --- |
| `architecture` | `feature_first` |
| `state_management` | `bloc` |
| `routing` | `go_router` |
| `di` | `get_it` |
| `network` | `dio` |
| `storage` | `shared_preferences` |
| `localization` / `firebase` | `false` |
| dark mode | enabled |

## Commands

All commands use the short form `dart run stackchain …`:

```bash
# Scaffold (replaces default counter main.dart)
dart run stackchain init
dart run stackchain:init                 # same thing

# Useful flags
dart run stackchain init --overwrite
dart run stackchain init --dry-run

# Add a feature (positional name — no --name required)
dart run stackchain feature auth
dart run stackchain add notifications    # alias for feature

# Generate files anytime
dart run stackchain make feature chat
dart run stackchain make page onboarding
dart run stackchain make widget app_chip
dart run stackchain make service sync

# List generators / add a custom one
dart run stackchain list
dart run stackchain new my_generator
```

After adding features, re-run `dart run stackchain init --overwrite` if you want router and DI registrations refreshed automatically.

Optional: `dart pub global activate stackchain` then use `stackchain init` without `dart run`.

## What `init` generates

```text
lib/
├── app/           # App widget, theme, config, router
├── core/          # network, storage, di, errors, utils, services, widgets
├── features/      # one module per feature (layout matches architecture)
└── main.dart      # replaces Flutter counter template
```

Also updates `pubspec.yaml` dependencies, analysis options, and basic test scaffolding.

Feature layout follows your architecture (example for `feature_first` / `clean`):

```text
features/auth/
├── data/
├── domain/
└── presentation/   # bloc | cubit | providers | controllers
```

## Example stacks

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

**Cubit + Clean**

```yaml
stackchain:
  architecture: clean
  state_management: cubit
  features: [home, settings]
```

**Riverpod**

```yaml
stackchain:
  state_management: riverpod
  features: [home, profile]
```

**Provider**

```yaml
stackchain:
  state_management: provider
  features: [home, profile]
```

**GetX + MVC**

```yaml
stackchain:
  architecture: mvc
  state_management: getx
  features: [splash, auth, home]
```

## License

MIT
