import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/slices/feature_remover.dart';
import 'package:stackchain/src/slices/vertical_slice.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('remove feature', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_remove_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: remove_app
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

    test('remove auth deletes files, yaml, router/DI, and auth redirect',
        () async {
      expect(
        await Directory(p.join(temp.path, 'lib/features/auth')).exists(),
        isTrue,
      );

      final report = await FeatureRemover(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).remove('auth');

      expect(report.name, 'auth');
      expect(
        await Directory(p.join(temp.path, 'lib/features/auth')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(temp.path, 'test/features/auth_bloc_test.dart'))
            .exists(),
        isFalse,
      );

      final yaml = await File(p.join(temp.path, 'stackchain.yaml'))
          .readAsString();
      final config = YamlParser.parse(yaml, packageName: 'remove_app');
      expect(config.features, equals(['home']));
      expect(config.features, isNot(contains('auth')));

      final routes = await File(
        p.join(temp.path, 'lib/app/router/app_routes.dart'),
      ).readAsString();
      expect(routes, isNot(contains('static const String auth')));
      expect(routes, contains('static const String home'));

      final router = await File(
        p.join(temp.path, 'lib/app/router/app_router.dart'),
      ).readAsString();
      expect(router, isNot(contains('AuthPage')));
      expect(router, isNot(contains("name: 'auth'")));
      expect(router, isNot(contains('redirect:')));
      expect(router, isNot(contains('route_guards.dart')));
      expect(router, contains('HomePage'));

      final di = await File(
        p.join(temp.path, 'lib/core/di/injection.dart'),
      ).readAsString();
      expect(di, isNot(contains('AuthBloc')));
      expect(di, isNot(contains('/features/auth/')));
      expect(di, contains('HomeBloc'));
    });

    test('cannot remove the last feature', () async {
      await FeatureRemover(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).remove('auth');

      expect(
        () => FeatureRemover(
          root: temp.path,
          logger: Logger(),
          skipAnalyze: true,
        ).remove('home'),
        throwsA(isA<StateError>()),
      );
    });

    test('dry-run leaves feature on disk', () async {
      await FeatureRemover(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        dryRun: true,
      ).remove('auth');

      expect(
        await Directory(p.join(temp.path, 'lib/features/auth')).exists(),
        isTrue,
      );
      final yaml = await File(p.join(temp.path, 'stackchain.yaml'))
          .readAsString();
      expect(yaml, contains('- auth'));
    });
  });
}
