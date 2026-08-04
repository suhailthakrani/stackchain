<p align="center">
  <img src="https://raw.githubusercontent.com/suhailthakrani/stackchain/main/assets/stackchain_logo.png" alt="Stackchain logo" width="420">
</p>

<p align="center">
  <a href="https://pub.dev/packages/stackchain"><img src="https://img.shields.io/pub/v/stackchain.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/stackchain/score"><img src="https://img.shields.io/pub/likes/stackchain" alt="likes"></a>
  <a href="https://github.com/suhailthakrani/stackchain/stargazers"><img src="https://img.shields.io/github/stars/suhailthakrani/stackchain?style=flat" alt="stars"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license"></a>
</p>

# stackchain

**Scaffold a Flutter app from a YAML config — then keep using it as you build.**

Pick your stack once. Generate shippable features. Keep your hand-written code. Fix the project when it drifts.

[Docs](https://suhailthakrani.github.io/stackchain-docs/) · [pub.dev](https://pub.dev/packages/stackchain) · [GitHub](https://github.com/suhailthakrani/stackchain)

## Install & run

Needs an existing Flutter app (`flutter create my_app`).

```bash
cd my_app
dart pub add --dev stackchain
dart run stackchain init
flutter pub get
flutter run
```

`init` replaces the counter app with `lib/app`, `lib/core`, `lib/features`, merges dependencies, and runs a quality check. No config file needed — production defaults apply (Bloc + GoRouter + GetIt + Dio).

## Choose your stack

**Preset (easiest):**

```yaml
stackchain:
  preset: production_bloc
  features: [splash, auth, home, settings]
```

**Full control:**

```yaml
stackchain:
  # preset: production_bloc   # optional; explicit keys win
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

List presets: `dart run stackchain presets`

## What it supports

| Area | Options |
| --- | --- |
| **Architecture** | `feature_first` · `clean` · `mvvm` · `mvc` |
| **State management** | `bloc` · `cubit` · `riverpod` · `provider` · `getx` · `rxdart` |
| **Routing** | `go_router` · `auto_route` · `navigator` · `getx` |
| **DI** | `get_it` · `injectable` · `getx` |
| **Network** | `dio` · `http` |
| **Storage** | `shared_preferences` · `secure_storage` · `hive` |
| **Extras** | flavors · CI workflow · localization · firebase · dark mode · analytics · crashlytics · biometrics |
| **Presets** | `production_bloc` · `production_riverpod` · `production_rxdart` · `clean_cubit` · `getx_mvc` · `firebase_bloc` · `minimal` |

Also out of the box: session + secure storage, auth route guards (when `auth` exists), Dio interceptors (auth / retry / errors), and a quality gate on every generate.

## Everyday commands

```bash
# Features
dart run stackchain feature auth     # files + routes + DI + tests
dart run stackchain feature onboarding
dart run stackchain add notifications
dart run stackchain crud product     # feature + list/form CRUD extras
dart run stackchain rename profile account
dart run stackchain remove auth

# Stay in sync
dart run stackchain sync             # re-wire router & DI
dart run stackchain upgrade          # refresh deps
dart run stackchain migrate --state cubit --dry-run
dart run stackchain migrate --state cubit
dart run stackchain migrate --preset production_riverpod

# Tests for a feature
dart run stackchain test auth                    # unit + widget + integration
dart run stackchain test auth --type unit,widget
dart run stackchain stub auth                    # stub // <stackchain:custom> methods
dart run stackchain test --all
# Custom logic → test/features/<feature>_custom_test.dart (never overwritten)
# Custom methods → // <stackchain:custom> in generated Bloc/Cubit/Page classes

# Trust & generate
dart run stackchain doctor
dart run stackchain doctor --fix              # sync + refresh lock
dart run stackchain presets
dart run stackchain make page onboarding
dart run stackchain make widget app_chip
dart run stackchain make service analytics
```

## Your code is safe

Generated router/DI files use markers:

```dart
// <stackchain:routes>
GoRoute(path: AppRoutes.home, ...),
// </stackchain:routes>
```

`sync` / `feature` / `upgrade` / `migrate` only rewrite code **inside** those markers. Everything outside is yours.

## What `init` generates

```text
lib/
├── app/           # App widget, theme, config, router
├── core/          # network, storage, DI, errors, utils, session, widgets
├── features/      # one module per feature (layout matches architecture)
└── main.dart      # replaces Flutter counter template
.stackchain/
└── lock.yaml      # stack fingerprint for upgrade / migrate
```

## Example stacks

**Riverpod**

```yaml
stackchain:
  preset: production_riverpod
  features: [home, profile]
```

**GetX + MVC**

```yaml
stackchain:
  preset: getx_mvc
  features: [splash, auth, home]
```

**Bloc + GoRouter + GetIt (manual)**

```yaml
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features: [auth, home]
```

## License

MIT

## Support & contribute

If stackchain saves you time:

- ⭐ **Star the repo** — [github.com/suhailthakrani/stackchain](https://github.com/suhailthakrani/stackchain)
- 💙 **Like the package** on [pub.dev](https://pub.dev/packages/stackchain)
- 🐛 **Open an issue** for bugs or ideas
- 🔧 **Send a PR** — presets, bricks, docs, and fixes are all welcome

Contributions of any size help. Thank you for the love and support ❤️
