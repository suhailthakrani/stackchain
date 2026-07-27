import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/slices/feature_renamer.dart';
import 'package:stackchain/src/slices/vertical_slice.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('rename feature', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_rename_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: rename_app
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
      ).add('profile');

      // Hand-written file that must survive rename with content rewrite.
      final customDir = Directory(
        p.join(temp.path, 'lib/features/profile/presentation/widgets'),
      );
      await customDir.create(recursive: true);
      await File(p.join(customDir.path, 'profile_card.dart')).writeAsString('''
class ProfileCard {
  const ProfileCard();
}
''');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('profile → account rewires yaml, files, router, and DI', () async {
      final report = await FeatureRenamer(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
      ).rename('profile', 'account');

      expect(report.from, 'profile');
      expect(report.to, 'account');

      final yaml = await File(p.join(temp.path, 'stackchain.yaml'))
          .readAsString();
      final config = YamlParser.parse(yaml, packageName: 'rename_app');
      expect(config.features, contains('account'));
      expect(config.features, isNot(contains('profile')));

      expect(
        await Directory(p.join(temp.path, 'lib/features/profile')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(temp.path, 'lib/features/account')).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(
            temp.path,
            'lib/features/account/presentation/pages/account_page.dart',
          ),
        ).exists(),
        isTrue,
      );

      final custom = await File(
        p.join(
          temp.path,
          'lib/features/account/presentation/widgets/account_card.dart',
        ),
      ).readAsString();
      expect(custom, contains('AccountCard'));
      expect(custom, isNot(contains('ProfileCard')));

      final routes = await File(
        p.join(temp.path, 'lib/app/router/app_routes.dart'),
      ).readAsString();
      expect(routes, contains('static const String account'));
      expect(routes, isNot(contains('static const String profile')));

      final router = await File(
        p.join(temp.path, 'lib/app/router/app_router.dart'),
      ).readAsString();
      expect(router, contains('AccountPage'));
      expect(router, isNot(contains('ProfilePage')));

      final di = await File(
        p.join(temp.path, 'lib/core/di/injection.dart'),
      ).readAsString();
      expect(di, contains('AccountBloc'));
      expect(di, contains('AccountRepository'));
      expect(di, isNot(contains('ProfileBloc')));
    });

    test('refuses to overwrite an existing target feature', () async {
      expect(
        () => FeatureRenamer(
          root: temp.path,
          logger: Logger(),
          skipAnalyze: true,
        ).rename('profile', 'home'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
