import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/models/stackchain_config.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/quality/doctor_engine.dart';
import 'package:stackchain/src/slices/crud_recipe.dart';
import 'package:stackchain/src/slices/recipe_extras.dart';
import 'package:stackchain/src/slices/vertical_slice.dart';
import 'package:stackchain/src/testing/custom_method_stubber.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('1.3.0 recipes + stub + doctor', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_13_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: v13_app
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
        overwrite: true,
      ).run();
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    Future<StackchainConfig> loadConfig() async {
      final yaml =
          await File(p.join(temp.path, 'stackchain.yaml')).readAsString();
      return YamlParser.parse(yaml, packageName: 'v13_app');
    }

    test('auth recipe includes form widget test', () async {
      await VerticalSliceGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).add('auth');

      expect(
        await File(
          p.join(
            temp.path,
            'lib/features/auth/presentation/widgets/auth_form.dart',
          ),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'test/features/auth_form_test.dart'))
            .exists(),
        isTrue,
      );
    });

    test('known recipes include onboarding notifications search', () {
      expect(
        FeatureRecipeExtras.known,
        containsAll(['onboarding', 'notifications', 'search']),
      );
    });

    test('crud adds list tile + form', () async {
      await VerticalSliceGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        crud: true,
      ).add('product');

      expect(
        await File(
          p.join(
            temp.path,
            'lib/features/product/presentation/widgets/product_form.dart',
          ),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'test/features/product_form_test.dart'))
            .exists(),
        isTrue,
      );
      final extras = CrudRecipe.extras('product', await loadConfig());
      expect(extras.keys, contains('lib/features/product/product.dart'));
    });

    test('stubber appends failing tests for custom methods', () async {
      await VerticalSliceGenerator(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).add('auth');

      final bloc = File(
        p.join(temp.path, 'lib/features/auth/presentation/bloc/auth_bloc.dart'),
      );
      var src = await bloc.readAsString();
      src = RegionMerger.replaceRegion(
        source: src,
        id: 'custom',
        body: '''
  Future<void> loginWithBiometrics() async {
    // user
  }

  void refreshSession() {}
''',
      );
      await bloc.writeAsString(src);

      final stubber = CustomMethodStubber(
        root: temp.path,
        config: await loadConfig(),
        logger: Logger(),
      );
      final added = await stubber.stubFeature('auth');
      expect(added, containsAll(['loginWithBiometrics', 'refreshSession']));

      final custom = await File(
        p.join(temp.path, 'test/features/auth_custom_test.dart'),
      ).readAsString();
      expect(custom, contains('loginWithBiometrics is implemented'));
      expect(custom, contains("fail('Implement test for loginWithBiometrics')"));
    });

    test('doctor --fix refreshes lock', () async {
      final engine = DoctorEngine(
        root: temp.path,
        config: await loadConfig(),
        logger: Logger(),
        fix: true,
        skipAnalyze: true,
      );
      final report = await engine.run();
      expect(report.passed, isTrue);
      expect(engine.fixed, isNotEmpty);
      expect(
        await File(p.join(temp.path, '.stackchain/lock.yaml')).exists(),
        isTrue,
      );
    });
  });
}
