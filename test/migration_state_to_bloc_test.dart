import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/migrate/migration_engine.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('state migration riverpod -> bloc', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_mig_state_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: stackchain_test
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
  state_management: riverpod
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
    - auth
''');

      await ProjectGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run();
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('migrate rewrites bootstrap and syncs feature DI graph', () async {
      final beforeBootstrap =
          await File(p.join(temp.path, 'lib/bootstrap.dart')).readAsString();
      expect(beforeBootstrap, contains('flutter_riverpod'));
      expect(beforeBootstrap, contains('ProviderScope'));

      await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run(const MigrationPatch(stateManagement: StateManagement.bloc));

      final bootstrap =
          await File(p.join(temp.path, 'lib/bootstrap.dart')).readAsString();
      expect(bootstrap, isNot(contains('flutter_riverpod')));
      expect(bootstrap, isNot(contains('ProviderScope')));
      expect(bootstrap, contains('runApp(const App())'));

      final di =
          await File(p.join(temp.path, 'lib/core/di/injection.dart')).readAsString();
      expect(di, contains('HomeRemoteDataSource'));
      expect(di, contains('HomeRepository'));
      expect(di, contains('GetHome'));
      expect(di, contains('HomeBloc'));
      expect(di, contains('AuthRemoteDataSource'));
      expect(di, contains('AuthRepository'));
      expect(di, contains('GetAuth'));
      expect(di, contains('AuthBloc'));

      expect(
        await File(
          p.join(temp.path, 'lib/features/home/presentation/bloc/home_bloc.dart'),
        ).exists(),
        isTrue,
      );
      expect(
        await Directory(
          p.join(temp.path, 'lib/features/home/presentation/providers'),
        ).exists(),
        isFalse,
      );
      expect(
        await File(p.join(temp.path, 'test/features/home_bloc_test.dart'))
            .exists(),
        isTrue,
      );

      final homePage = await File(
        p.join(
          temp.path,
          'lib/features/home/presentation/pages/home_page.dart',
        ),
      ).readAsString();
      expect(homePage, contains('HomeBloc'));
      expect(homePage, contains('BlocProvider'));
      expect(homePage, isNot(contains('ConsumerWidget')));
      expect(homePage, isNot(contains('homeProvider')));
      expect(homePage, contains('// <stackchain:generated>'));
    });

    test('migrate --routing refreshes router shell', () async {
      await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run(const MigrationPatch(routing: Routing.getx));

      final router = await File(
        p.join(temp.path, 'lib/app/router/app_router.dart'),
      ).readAsString();
      expect(router, contains('GetPage'));
      expect(router.toLowerCase(), isNot(contains('gorouter')));
    });
  });
}
