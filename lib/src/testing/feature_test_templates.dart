import '../merge/owned_regions.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../utils/stack_paths.dart';
import 'test_types.dart';

/// Stack-aware unit / widget / integration test scaffolds for one feature.
class FeatureTestTemplates {
  FeatureTestTemplates(this.config);

  final StackchainConfig config;

  String get _pkg => config.packageName ?? 'app';

  /// Relative paths → file contents for [feature] and selected [types].
  ///
  /// Always includes `test/features/<feature>_custom_test.dart` (user-owned).
  Map<String, String> generate(
    String feature, {
    Set<TestType> types = TestType.all,
  }) {
    final files = <String, String>{
      _customTestPath(feature): _customTest(feature),
    };
    if (types.contains(TestType.unit)) {
      files.addAll(_unit(feature));
    }
    if (types.contains(TestType.widget)) {
      files.addAll(_widget(feature));
    }
    if (types.contains(TestType.integration)) {
      files.addAll(_integration(feature));
    }
    return files;
  }

  /// Paths this feature's tests may own (scaffolds only — not custom).
  static Set<String> ownedPaths(String feature, StackchainConfig config) {
    return FeatureTestTemplates(config)
        .generate(feature, types: TestType.all)
        .keys
        .where((k) => !k.endsWith('_custom_test.dart'))
        .toSet();
  }

  static String customTestPath(String feature) =>
      'test/features/${feature}_custom_test.dart';

  String _customTestPath(String feature) => customTestPath(feature);

  Map<String, String> _unit(String feature) {
    final pascal = StackPaths.pascal(feature);
    final pkg = _pkg;

    if (StackPaths.layered(config) && config.stateManagement.usesFlutterBloc) {
      if (config.stateManagement == StateManagement.bloc) {
        return {
          'test/features/${feature}_bloc_test.dart': _wrapScaffold('''
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_bloc.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_event.dart';
import 'package:$pkg/features/$feature/presentation/bloc/${feature}_state.dart';

void main() {
  // <stackchain:generated>
  group('${pascal}Bloc', () {
    blocTest<${pascal}Bloc, ${pascal}State>(
      'emits loading then success on start',
      build: ${pascal}Bloc.new,
      act: (b) => b.add(const ${pascal}Started()),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<${pascal}State>(),
        isA<${pascal}State>(),
      ],
    );
  });
  // </stackchain:generated>
}
'''),
        };
      }
      return {
        'test/features/${feature}_cubit_test.dart': _wrapScaffold('''
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/cubit/${feature}_cubit.dart';
import 'package:$pkg/features/$feature/presentation/cubit/${feature}_state.dart';

void main() {
  // <stackchain:generated>
  group('${pascal}Cubit', () {
    blocTest<${pascal}Cubit, ${pascal}State>(
      'emits success after load',
      build: ${pascal}Cubit.new,
      act: (c) => c.load(),
      wait: const Duration(milliseconds: 300),
      expect: () => [
        isA<${pascal}State>(),
        isA<${pascal}State>(),
      ],
    );
  });
  // </stackchain:generated>
}
'''),
      };
    }

    if (StackPaths.layered(config) && config.stateManagement.usesRxDart) {
      return {
        'test/features/${feature}_controller_test.dart': _wrapScaffold('''
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/features/$feature/presentation/controllers/${feature}_controller.dart';
import 'package:$pkg/features/$feature/presentation/controllers/${feature}_state.dart';

void main() {
  // <stackchain:generated>
  late ${pascal}Controller controller;

  setUp(() {
    controller = ${pascal}Controller();
  });

  tearDown(() {
    controller.dispose();
  });

  test('emits success after load', () async {
    await expectLater(
      controller.stream,
      emitsThrough(
        isA<${pascal}State>().having(
          (s) => s.status,
          'status',
          ${pascal}Status.success,
        ),
      ),
    );
  });
  // </stackchain:generated>
}
'''),
      };
    }

    return {
      'test/features/${feature}_test.dart': _wrapScaffold('''
import 'package:flutter_test/flutter_test.dart';
import 'package:$pkg/${StackPaths.pageImport(config, feature)}';

void main() {
  // <stackchain:generated>
  test('${pascal}Page type is available', () {
    expect(${pascal}Page, isNotNull);
  });
  // </stackchain:generated>
}
'''),
    };
  }

  Map<String, String> _widget(String feature) {
    final pascal = StackPaths.pascal(feature);
    final pkg = _pkg;
    final pageImport = StackPaths.pageImport(config, feature);
    final setup = _widgetSetup(feature, pascal);
    final root = _widgetRoot('${pascal}Page()');

    return {
      'test/features/${feature}_page_test.dart': _wrapScaffold('''
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
${setup.imports}
import 'package:$pkg/$pageImport';

void main() {
${setup.body}  // <stackchain:generated>
  testWidgets('${pascal}Page renders', (tester) async {
    await tester.pumpWidget($root);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(${pascal}Page), findsOneWidget);
    expect(find.textContaining('$pascal'), findsWidgets);
  });
  // </stackchain:generated>
}
'''),
    };
  }

  Map<String, String> _integration(String feature) {
    final pascal = StackPaths.pascal(feature);
    final pkg = _pkg;
    final riverpod = config.stateManagement == StateManagement.riverpod;
    final navigate = _integrationNavigate(feature);
    final extraImports = _integrationImports(feature);

    return {
      'integration_test/${feature}_flow_test.dart': _wrapScaffold('''
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
${riverpod ? "import 'package:flutter_riverpod/flutter_riverpod.dart';\n" : ''}$extraImports
import 'package:$pkg/app/app.dart';
import 'package:$pkg/core/di/injection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await configureDependencies();
  });

  // <stackchain:generated>
  testWidgets('$pascal flow smoke', (tester) async {
    await tester.pumpWidget(
      ${riverpod ? 'const ProviderScope(child: App())' : 'const App()'},
    );
    await tester.pumpAndSettle();
$navigate
    expect(find.textContaining('$pascal'), findsWidgets);
  });
  // </stackchain:generated>
}
'''),
    };
  }

  String _customTest(String feature) {
    final pascal = StackPaths.pascal(feature);
    return '''
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('$pascal custom', () {
${OwnedRegions.customTestPlaceholder}    // test('my custom method', () async {});
  });
}
''';
  }

  /// Identity helper — content already contains markers.
  String _wrapScaffold(String source) => source;

  String _integrationImports(String feature) {
    final pkg = _pkg;
    switch (config.routing) {
      case Routing.goRouter:
        return "import 'package:$pkg/app/router/app_router.dart';\n";
      case Routing.getx:
        return "import 'package:get/get.dart';\n"
            "import 'package:$pkg/app/router/app_routes.dart';\n";
      case Routing.autoRoute:
      case Routing.navigator:
        return '';
    }
  }

  String _integrationNavigate(String feature) {
    switch (config.routing) {
      case Routing.goRouter:
        final route = StackPaths.routePath(feature);
        return '''
    AppRouter.router.go('$route');
    await tester.pumpAndSettle();
''';
      case Routing.getx:
        return '''
    await Get.toNamed(AppRoutes.$feature);
    await tester.pumpAndSettle();
''';
      case Routing.autoRoute:
      case Routing.navigator:
        return '';
    }
  }

  ({String imports, String body}) _widgetSetup(String feature, String pascal) {
    switch (config.stateManagement) {
      case StateManagement.riverpod:
        return (
          imports: "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
          body: '',
        );
      case StateManagement.getx:
        final controllerImport = _getxControllerImport(feature);
        return (
          imports: "import 'package:get/get.dart';\n"
              "import 'package:$_pkg/$controllerImport';\n",
          body: '''
  setUp(() {
    Get.testMode = true;
    Get.put(${pascal}Controller());
  });

  tearDown(Get.reset);

''',
        );
      case StateManagement.bloc:
      case StateManagement.cubit:
      case StateManagement.provider:
      case StateManagement.rxdart:
        return (imports: '', body: '');
    }
  }

  String _widgetRoot(String pageCtor) {
    switch (config.stateManagement) {
      case StateManagement.riverpod:
        return 'const ProviderScope(\n'
            '      child: MaterialApp(home: $pageCtor),\n'
            '    )';
      case StateManagement.getx:
        return 'GetMaterialApp(home: $pageCtor)';
      case StateManagement.bloc:
      case StateManagement.cubit:
      case StateManagement.provider:
      case StateManagement.rxdart:
        return 'const MaterialApp(home: $pageCtor)';
    }
  }

  String _getxControllerImport(String feature) {
    switch (config.architecture) {
      case Architecture.featureFirst:
      case Architecture.clean:
        return 'features/$feature/presentation/controllers/${feature}_controller.dart';
      case Architecture.mvvm:
      case Architecture.mvc:
        return 'features/$feature/controllers/${feature}_controller.dart';
    }
  }
}
