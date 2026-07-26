import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/slices/vertical_slice.dart';
import 'package:stackchain/src/sync/project_sync.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('vertical slice + sync', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_slice_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: slice_app
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
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('feature auth wires router without overwrite', () async {
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

      final router = await File(
        p.join(temp.path, 'lib/app/router/app_router.dart'),
      ).readAsString();
      expect(router, contains('AuthPage'));
      expect(router, contains("name: 'auth'"));
      expect(RegionMerger.hasRegion(router, 'routes'), isTrue);

      final routes = await File(
        p.join(temp.path, 'lib/app/router/app_routes.dart'),
      ).readAsString();
      expect(routes, contains('static const String auth'));

      final di = await File(
        p.join(temp.path, 'lib/core/di/injection.dart'),
      ).readAsString();
      expect(di, contains('AuthBloc'));
      expect(RegionMerger.hasRegion(di, 'features'), isTrue);

      expect(
        await File(
          p.join(temp.path, 'lib/features/auth/presentation/widgets/auth_form.dart'),
        ).exists(),
        isTrue,
      );
      expect(
        await File(p.join(temp.path, 'test/features/auth_bloc_test.dart'))
            .exists(),
        isTrue,
      );

      // Manual edit outside region must survive sync.
      final edited = router.replaceFirst(
        'abstract final class AppRouter {',
        'abstract final class AppRouter {\n  // hand edit\n',
      );
      await File(p.join(temp.path, 'lib/app/router/app_router.dart'))
          .writeAsString(edited);

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'slice_app',
      );
      expect(config.features, containsAll(['home', 'auth']));

      await ProjectSync(
        root: temp.path,
        config: config,
        logger: Logger(),
      ).run();

      final after = await File(
        p.join(temp.path, 'lib/app/router/app_router.dart'),
      ).readAsString();
      expect(after, contains('hand edit'));
      expect(after, contains('AuthPage'));
      expect(after, contains('redirect:'));
      expect(config.stateManagement, StateManagement.bloc);
    });
  });
}
