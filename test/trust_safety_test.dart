import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/generators/project_generator.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/migrate/app_shell_safety.dart';
import 'package:stackchain/src/migrate/migration_engine.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/quality/doctor_engine.dart';
import 'package:stackchain/src/quality/marker_integrity.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

Future<Directory> _scaffold({
  required String name,
  required String yaml,
}) async {
  final temp = await Directory.systemTemp.createTemp('stackchain_trust_');
  await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: $name
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
  await File(p.join(temp.path, 'stackchain.yaml')).writeAsString(yaml);
  await ProjectGenerator(
    root: temp.path,
    logger: Logger(),
    skipAnalyze: true,
  ).run();
  return temp;
}

void main() {
  group('app shell safety', () {
    late Directory temp;

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('migrate refuses customized bootstrap', () async {
      temp = await _scaffold(
        name: 'shell_app',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: riverpod
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final bootstrap = File(p.join(temp.path, 'lib/bootstrap.dart'));
      final original = await bootstrap.readAsString();
      await bootstrap.writeAsString(
        '$original\n// CUSTOM: do not clobber me\n',
      );

      expect(
        () => MigrationEngine(
          root: temp.path,
          logger: Logger(),
          skipAnalyze: true,
        ).run(const MigrationPatch(stateManagement: StateManagement.bloc)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Refusing to overwrite customized app shell'),
          ),
        ),
      );

      // yaml must not have been rewritten on refuse
      final yaml = await File(p.join(temp.path, 'stackchain.yaml')).readAsString();
      expect(yaml, contains('state_management: riverpod'));
      expect(await bootstrap.readAsString(), contains('CUSTOM: do not clobber me'));
    });

    test('migrate --force-shell overwrites customized bootstrap', () async {
      temp = await _scaffold(
        name: 'shell_force_app',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: riverpod
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final bootstrap = File(p.join(temp.path, 'lib/bootstrap.dart'));
      await bootstrap.writeAsString(
        '${await bootstrap.readAsString()}\n// CUSTOM hook\n',
      );

      await MigrationEngine(
        root: temp.path,
        logger: Logger(),
        skipAnalyze: true,
        forceShell: true,
      ).run(const MigrationPatch(stateManagement: StateManagement.bloc));

      final next = await bootstrap.readAsString();
      expect(next, isNot(contains('CUSTOM hook')));
      expect(next, isNot(contains('ProviderScope')));
      expect(next, contains('runApp(const App())'));
    });

    test('isVirginShell matches before/after templates', () {
      expect(
        AppShellSafety.isVirginShell(
          existing: 'a\n',
          beforeTemplate: 'a',
          afterTemplate: 'b',
        ),
        isTrue,
      );
      expect(
        AppShellSafety.isVirginShell(
          existing: 'custom',
          beforeTemplate: 'a',
          afterTemplate: 'b',
        ),
        isFalse,
      );
      expect(
        AppShellSafety.isVirginShell(
          relativePath: 'lib/main.dart',
          existing:
              "import 'package:flutter/material.dart';\nvoid main() => runApp(const MaterialApp(home: SizedBox()));\n",
          beforeTemplate: 'a',
          afterTemplate: 'b',
        ),
        isTrue,
      );
    });
  });

  group('marker integrity', () {
    late Directory temp;

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('doctor passes on fresh init', () async {
      temp = await _scaffold(
        name: 'integrity_ok',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'integrity_ok',
      );
      final report = await DoctorEngine(
        root: temp.path,
        config: config,
        logger: Logger(),
        skipAnalyze: true,
      ).run();
      expect(report.passed, isTrue);
    });

    test('doctor fails when generated region is hand-edited', () async {
      temp = await _scaffold(
        name: 'integrity_bad',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final blocPath = p.join(
        temp.path,
        'lib/features/home/presentation/bloc/home_bloc.dart',
      );
      final content = await File(blocPath).readAsString();
      final tampered = RegionMerger.replaceRegion(
        source: content,
        id: 'generated',
        body: '  // TAMPERED HAND EDIT\n',
      );
      await File(blocPath).writeAsString(tampered);

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'integrity_bad',
      );
      final report = await DoctorEngine(
        root: temp.path,
        config: config,
        logger: Logger(),
        skipAnalyze: true,
      ).run();

      expect(report.passed, isFalse);
      expect(
        report.errors.any((e) => e.contains('home_bloc.dart') && e.contains('generated')),
        isTrue,
      );
    });

    test('doctor fails when routes region is hand-edited', () async {
      temp = await _scaffold(
        name: 'integrity_routes',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final routes = File(p.join(temp.path, 'lib/app/router/app_routes.dart'));
      final content = await routes.readAsString();
      await routes.writeAsString(
        RegionMerger.replaceRegion(
          source: content,
          id: 'routes',
          body: "  static const String home = '/hacked';\n",
        ),
      );

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'integrity_routes',
      );
      final report = await DoctorEngine(
        root: temp.path,
        config: config,
        logger: Logger(),
        skipAnalyze: true,
      ).run();

      expect(report.passed, isFalse);
      expect(
        report.errors.any((e) => e.contains('app_routes.dart')),
        isTrue,
      );
    });

    test('doctor --fix restores router region drift', () async {
      temp = await _scaffold(
        name: 'integrity_fix',
        yaml: '''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  features:
    - home
''',
      );

      final routes = File(p.join(temp.path, 'lib/app/router/app_routes.dart'));
      await routes.writeAsString(
        RegionMerger.replaceRegion(
          source: await routes.readAsString(),
          id: 'routes',
          body: "  static const String home = '/hacked';\n",
        ),
      );

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'integrity_fix',
      );
      final report = await DoctorEngine(
        root: temp.path,
        config: config,
        logger: Logger(),
        skipAnalyze: true,
        fix: true,
      ).run();

      expect(report.passed, isTrue);
      expect(await routes.readAsString(), contains("home = '/'"));
      expect(await routes.readAsString(), isNot(contains('/hacked')));
    });

    test('bodiesEqual normalizes whitespace', () {
      expect(
        MarkerIntegrity.bodiesEqual('  foo  \n', 'foo'),
        isTrue,
      );
      expect(
        MarkerIntegrity.bodiesEqual('foo', 'bar'),
        isFalse,
      );
    });
  });
}
