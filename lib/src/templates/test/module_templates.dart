import '../../models/enums.dart';
import '../../models/stackchain_config.dart';

/// Optional localization + firebase stubs + test scaffolding.
class ModuleTemplates {
  ModuleTemplates(this.config);

  final StackchainConfig config;
  String get pkg => config.packageName ?? 'app';

  Map<String, String> generate() {
    final files = <String, String>{
      'test/unit/.gitkeep': '',
      'test/widget/app_test.dart': _widgetTest(),
      'test/mocks/.gitkeep': '',
      'integration_test/.gitkeep': '',
      'analysis_options.yaml': _analysisOptions(),
    };

    if (config.modules.ci) {
      files['.github/workflows/stackchain_ci.yml'] = _ciWorkflow();
    }

    if (config.modules.localization) {
      files.addAll({
        'l10n.yaml': '''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
''',
        'lib/l10n/app_en.arb': '''
{
  "@@locale": "en",
  "appTitle": "App",
  "homeTitle": "Home",
  "login": "Log in",
  "logout": "Log out"
}
''',
        'lib/l10n/app_es.arb': '''
{
  "@@locale": "es",
  "appTitle": "Aplicación",
  "homeTitle": "Inicio",
  "login": "Iniciar sesión",
  "logout": "Cerrar sesión"
}
''',
        'lib/l10n/app_ar.arb': '''
{
  "@@locale": "ar",
  "appTitle": "تطبيق",
  "homeTitle": "الرئيسية",
  "login": "تسجيل الدخول",
  "logout": "تسجيل الخروج"
}
''',
      });
    }

    if (config.modules.firebase) {
      files['lib/app/config/firebase_options.dart'] = '''
// Replace with `flutterfire configure` output.
// ignore_for_file: lines_longer_than_80_chars
class DefaultFirebaseOptions {
  // Placeholder — run FlutterFire CLI to generate real options.
  static Never get currentPlatform =>
      throw UnimplementedError('Run: flutterfire configure');
}
''';
    }

    return files;
  }

  String _widgetTest() {
    final home =
        config.features.contains('home') ? 'home' : config.features.first;
    final pascal = home
        .split('_')
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();

    final riverpod = config.stateManagement == StateManagement.riverpod;
    final imports = riverpod
        ? "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
        : '';
    final appWidget =
        riverpod ? 'const ProviderScope(child: App())' : 'const App()';

    return '''
import 'package:flutter_test/flutter_test.dart';
$imports
import 'package:$pkg/app/app.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget($appWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('$pascal'), findsWidgets);
  });
}
''';
  }

  String _analysisOptions() => '''
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    invalid_annotation_target: ignore
  exclude:
    - '**/*.g.dart'
    - '**/*.freezed.dart'
    - '**/*.gr.dart'

linter:
  rules:
    prefer_const_constructors: true
    prefer_const_declarations: true
    prefer_final_locals: true
    avoid_print: true
    directives_ordering: true
    unawaited_futures: true
    cancel_subscriptions: true
    close_sinks: true
    only_throw_errors: true
    avoid_dynamic_calls: true
    depend_on_referenced_packages: true
''';

  String _ciWorkflow() => '''
name: stackchain CI

on:
  push:
    branches: [main, master, develop]
  pull_request:

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: dart run stackchain doctor --skip-analyze
      - run: flutter test
''';
}
