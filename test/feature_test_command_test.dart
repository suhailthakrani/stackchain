import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/models/stackchain_config.dart';
import 'package:stackchain/src/slices/vertical_slice.dart';
import 'package:stackchain/src/testing/feature_test_generator.dart';
import 'package:stackchain/src/testing/feature_test_templates.dart';
import 'package:stackchain/src/testing/test_types.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:stackchain/src/utils/pubspec_merger.dart';
import 'package:test/test.dart';

void main() {
  group('TestType.parse', () {
    test('empty means all', () {
      expect(TestType.parse(null), TestType.all);
      expect(TestType.parse(''), TestType.all);
      expect(TestType.parse('  '), TestType.all);
    });

    test('parses comma list', () {
      expect(
        TestType.parse('unit,widget'),
        equals({TestType.unit, TestType.widget}),
      );
      expect(
        TestType.parse('integration'),
        equals({TestType.integration}),
      );
    });

    test('rejects unknown', () {
      expect(() => TestType.parse('e2e'), throwsFormatException);
    });
  });

  group('FeatureTestTemplates', () {
    test('bloc stack emits unit + widget + integration paths', () {
      final config = StackchainConfig.defaults(packageName: 'demo').copyWith(
        features: const ['auth', 'home'],
      );
      final files = FeatureTestTemplates(config).generate('auth');

      expect(files.keys, contains('test/features/auth_bloc_test.dart'));
      expect(files.keys, contains('test/features/auth_page_test.dart'));
      expect(files.keys, contains('integration_test/auth_flow_test.dart'));
      expect(files['test/features/auth_bloc_test.dart'], contains('AuthBloc'));
      expect(
        files['test/features/auth_page_test.dart'],
        contains('AuthPage renders'),
      );
      expect(
        files['integration_test/auth_flow_test.dart'],
        contains('AppRouter.router.go'),
      );
    });

    test('cubit unit only when type filtered', () {
      final config = StackchainConfig(
        architecture: Architecture.featureFirst,
        stateManagement: StateManagement.cubit,
        routing: Routing.goRouter,
        di: DiType.getIt,
        network: NetworkClient.dio,
        storage: const [],
        features: const ['home'],
        packageName: 'demo',
      );
      final files = FeatureTestTemplates(config).generate(
        'home',
        types: const {TestType.unit},
      );
      expect(files.keys, contains('test/features/home_cubit_test.dart'));
      expect(files.keys, contains('test/features/home_custom_test.dart'));
      expect(files.keys, isNot(contains('test/features/home_page_test.dart')));
    });

    test('riverpod wraps widget test in ProviderScope', () {
      final config = StackchainConfig(
        architecture: Architecture.featureFirst,
        stateManagement: StateManagement.riverpod,
        routing: Routing.goRouter,
        di: DiType.getIt,
        network: NetworkClient.dio,
        storage: const [],
        features: const ['home'],
        packageName: 'demo',
      );
      final files = FeatureTestTemplates(config).generate(
        'home',
        types: const {TestType.widget},
      );
      expect(
        files['test/features/home_page_test.dart'],
        contains('ProviderScope'),
      );
    });
  });

  group('PubspecMerger.ensureSdkDevDependency', () {
    test('inserts integration_test under dev_dependencies', () {
      const existing = '''
name: demo
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  uses-material-design: true
''';
      final updated = PubspecMerger.ensureSdkDevDependency(
        existing,
        'integration_test',
      );
      expect(updated, contains('integration_test:'));
      expect(updated, contains('sdk: flutter'));
      expect(
        RegExp(r'integration_test:', multiLine: true)
            .allMatches(updated)
            .length,
        1,
      );
    });

    test('is idempotent', () {
      const existing = '''
dev_dependencies:
  integration_test:
    sdk: flutter
  flutter_test:
    sdk: flutter
''';
      expect(
        PubspecMerger.ensureSdkDevDependency(existing, 'integration_test'),
        existing,
      );
    });
  });

  group('FeatureTestGenerator', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_test_cmd_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: test_cmd_app
description: test
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter

flutter:
  uses-material-design: true
''');
      await Directory(p.join(temp.path, 'lib')).create();
      await File(p.join(temp.path, 'lib/main.dart')).writeAsString('''
import 'package:flutter/material.dart';
void main() => runApp(const MaterialApp(home: SizedBox()));
''');
      await File(p.join(temp.path, 'stackchain.yaml')).writeAsString('''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  features:
    - home
''');
      await ProjectGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run();
      await VerticalSliceGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).add('auth');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('generates full suite for auth with overwrite', () async {
      final report = await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(featureName: 'auth');

      expect(report.features, ['auth']);
      expect(
        await File(p.join(temp.path, 'test/features/auth_bloc_test.dart'))
            .exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'test/features/auth_page_test.dart'))
            .exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'integration_test/auth_flow_test.dart'))
            .exists(),
        isTrue,
      );

      final pubspec =
          await File(p.join(temp.path, 'pubspec.yaml')).readAsString();
      expect(pubspec, contains('integration_test:'));
    });

    test('type filter writes only widget (+ custom once)', () async {
      final report = await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(
        featureName: 'auth',
        types: const {TestType.widget},
      );

      expect(
        report.created + report.updated,
        contains('test/features/auth_page_test.dart'),
      );
      expect(
        await File(p.join(temp.path, 'test/features/auth_custom_test.dart'))
            .exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'integration_test/auth_flow_test.dart'))
            .exists(),
        isFalse,
      );
    });

    test('--all covers every feature', () async {
      final report = await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(
        all: true,
        types: const {TestType.unit},
      );

      expect(report.features, containsAll(['home', 'auth']));
      expect(
        await File(p.join(temp.path, 'test/features/home_bloc_test.dart'))
            .exists(),
        isTrue,
      );
    });

    test('unknown feature throws', () async {
      expect(
        () => FeatureTestGenerator(
          root: temp.path,
          logger: Logger(),
          skipAnalyze: true,
        ).run(featureName: 'missing'),
        throwsStateError,
      );
    });
  });
}
