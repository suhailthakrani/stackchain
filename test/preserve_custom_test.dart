import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/migrate/migration_engine.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/testing/feature_test_generator.dart';
import 'package:stackchain/src/testing/test_types.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('preserve custom regions', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_preserve_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: preserve_app
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
    - auth
''');
      await ProjectGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        overwrite: true,
      ).run();
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('migrate bloc→cubit ports custom region methods', () async {
      final blocFile = File(
        p.join(
          temp.path,
          'lib/features/auth/presentation/bloc/auth_bloc.dart',
        ),
      );
      expect(await blocFile.exists(), isTrue);
      var content = await blocFile.readAsString();
      expect(content, contains('// <stackchain:custom>'));

      content = RegionMerger.replaceRegion(
        source: content,
        id: 'custom',
        body: '''
  Future<void> loginWithBiometrics() async {
    // user logic
  }
''',
      );
      await blocFile.writeAsString(content);

      await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).run(
        const MigrationPatch(stateManagement: StateManagement.cubit),
      );

      final cubitFile = File(
        p.join(
          temp.path,
          'lib/features/auth/presentation/cubit/auth_cubit.dart',
        ),
      );
      expect(await cubitFile.exists(), isTrue);
      final cubit = await cubitFile.readAsString();
      expect(cubit, contains('loginWithBiometrics'));
      expect(cubit, contains('// <stackchain:custom>'));
      expect(cubit, contains('Future<void> load()'));
      expect(await blocFile.exists(), isFalse);

      final page = await File(
        p.join(
          temp.path,
          'lib/features/auth/presentation/pages/auth_page.dart',
        ),
      ).readAsString();
      expect(page, contains('AuthCubit'));
      expect(page, contains('..load()'));
      expect(page, isNot(contains('AuthBloc')));
      expect(page, isNot(contains('AuthStarted')));
      expect(page, contains('// <stackchain:custom>'));
    });

    test('custom_test.dart is never overwritten', () async {
      await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(featureName: 'auth', types: const {TestType.unit});

      final custom = File(
        p.join(temp.path, 'test/features/auth_custom_test.dart'),
      );
      expect(await custom.exists(), isTrue);
      await custom.writeAsString('''
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user owned assertion', () {
    expect(1 + 1, 2);
  });
}
''');

      await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(featureName: 'auth', types: TestType.all);

      final after = await custom.readAsString();
      expect(after, contains('user owned assertion'));
      expect(after, isNot(contains('Add tests for your custom')));
    });

    test('scaffold generated region refreshes without wiping sibling tests',
        () async {
      await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(featureName: 'auth', types: const {TestType.unit});

      final scaffold = File(
        p.join(temp.path, 'test/features/auth_bloc_test.dart'),
      );
      var text = await scaffold.readAsString();
      expect(text, contains('// </stackchain:generated>'));
      text = text.replaceFirst(
        '// </stackchain:generated>\n}',
        '''// </stackchain:generated>

  test('hand written outside scaffold', () {
    expect(true, isTrue);
  });
}
''',
      );
      await scaffold.writeAsString(text);

      await FeatureTestGenerator(
        root: temp.path,
        logger: Logger(),
        overwrite: true,
        skipAnalyze: true,
      ).run(featureName: 'auth', types: const {TestType.unit});

      final refreshed = await scaffold.readAsString();
      expect(refreshed, contains('hand written outside scaffold'));
      expect(refreshed, contains('emits loading then success on start'));
    });
  });
}
