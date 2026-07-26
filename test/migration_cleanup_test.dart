import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/migrate/migration_engine.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('migrate cleanup', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_migrate_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: migrate_app
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
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    File projectFile(String relative) => File(p.join(temp.path, relative));

    test('bloc → riverpod removes old state files and packages', () async {
      expect(
        await projectFile('lib/features/home/presentation/bloc/home_bloc.dart')
            .exists(),
        isTrue,
      );

      final report = await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run(const MigrationPatch(stateManagement: StateManagement.riverpod));

      expect(
        await Directory(p.join(temp.path, 'lib/features/home/presentation/bloc'))
            .exists(),
        isFalse,
        reason: 'old bloc folder should be deleted, not left as dead code',
      );
      expect(
        await projectFile(
          'lib/features/home/presentation/providers/home_provider.dart',
        ).exists(),
        isTrue,
      );

      final pubspec = await projectFile('pubspec.yaml').readAsString();
      expect(pubspec, isNot(contains('flutter_bloc:')));
      expect(pubspec, isNot(contains('bloc_test:')));
      expect(pubspec, contains('flutter_riverpod:'));
      expect(report.removedPackages, contains('flutter_bloc'));

      // Business logic layers survive a state management swap.
      expect(
        await projectFile('lib/features/home/domain/entities/home_entity.dart')
            .exists(),
        isTrue,
      );
      expect(
        await projectFile(
          'lib/features/home/data/repositories/home_repository_impl.dart',
        ).exists(),
        isTrue,
      );
    });

    test('hand-written files inside presentation are never deleted', () async {
      final custom = projectFile(
        'lib/features/home/presentation/widgets/my_custom_chart.dart',
      );
      await custom.writeAsString('// hand written\n');

      await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run(const MigrationPatch(stateManagement: StateManagement.cubit));

      expect(await custom.exists(), isTrue);
      expect(await custom.readAsString(), contains('hand written'));
    });

    test('--keep-old leaves the previous stack in place', () async {
      final report = await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        cleanup: false,
      ).run(const MigrationPatch(stateManagement: StateManagement.riverpod));

      expect(report.removedFiles, isEmpty);
      expect(report.removedPackages, isEmpty);
      expect(
        await projectFile('lib/features/home/presentation/bloc/home_bloc.dart')
            .exists(),
        isTrue,
      );
      expect(
        await projectFile('pubspec.yaml').readAsString(),
        contains('flutter_bloc:'),
      );
    });

    test('dry run reports removals without touching disk', () async {
      final report = await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        dryRun: true,
      ).run(const MigrationPatch(stateManagement: StateManagement.riverpod));

      expect(report.removedFiles, isNotEmpty);
      expect(
        await projectFile('lib/features/home/presentation/bloc/home_bloc.dart')
            .exists(),
        isTrue,
      );
      expect(
        await projectFile('pubspec.yaml').readAsString(),
        contains('flutter_bloc:'),
      );
    });
  });
}
