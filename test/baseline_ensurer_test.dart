import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/models/stackchain_config.dart';
import 'package:stackchain/src/sync/project_sync.dart';
import 'package:stackchain/src/utils/logger.dart';
import 'package:test/test.dart';

void main() {
  group('baseline ensurer via sync', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('stackchain_baseline_');
      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: legacy_app
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
      await Directory(p.join(temp.path, 'lib/app/router')).create(recursive: true);
      await Directory(p.join(temp.path, 'lib/core/di')).create(recursive: true);
      await Directory(p.join(temp.path, 'lib/core/network')).create(recursive: true);
      await Directory(p.join(temp.path, 'lib/app/config')).create(recursive: true);

      // Legacy 1.0 stubs that quality gate rejects.
      await File(p.join(temp.path, 'lib/app/router/route_guards.dart'))
          .writeAsString('''
abstract final class RouteGuards {
  static bool get isAuthenticated => true;
}
''');
      await File(p.join(temp.path, 'lib/core/network/dio_client.dart'))
          .writeAsString('''
class DioClient {
  DioClient();
}
''');
      await File(p.join(temp.path, 'lib/app/config/environment.dart'))
          .writeAsString('''
enum Environment { dev, staging, prod }
abstract final class AppEnvironment {
  static Environment current = Environment.dev;
  static String get apiBaseUrl => 'https://api.example.com';
  static bool get isProduction => false;
}
''');
      await File(p.join(temp.path, 'lib/core/di/injection.dart')).writeAsString('''
import 'package:get_it/get_it.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // <stackchain:core>
  getIt.registerLazySingleton<Object>(() => Object());
  // </stackchain:core>
  // <stackchain:features>
  // </stackchain:features>
}
''');
      await File(p.join(temp.path, 'lib/app/router/app_routes.dart'))
          .writeAsString('''
abstract final class AppRoutes {
  // <stackchain:routes>
  static const String home = '/';
  // </stackchain:routes>
}
''');
      await File(p.join(temp.path, 'lib/app/router/app_router.dart'))
          .writeAsString('''
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:legacy_app/features/home/presentation/pages/home_page.dart';

import 'app_routes.dart';

abstract final class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      // <stackchain:routes>
      GoRoute(path: AppRoutes.home, name: 'home', builder: (_, __) => const HomePage()),
      // </stackchain:routes>
    ],
  );
}
''');
      await Directory(
        p.join(temp.path, 'lib/features/home/presentation/pages'),
      ).create(recursive: true);
      await File(
        p.join(temp.path, 'lib/features/home/presentation/pages/home_page.dart'),
      ).writeAsString('''
import 'package:flutter/material.dart';
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox();
}
''');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('sync creates SessionService and upgrades legacy stubs', () async {
      final config = StackchainConfig(
        packageName: 'legacy_app',
        stateManagement: StateManagement.cubit,
        features: const ['home'],
      );

      await ProjectSync(
        root: temp.path,
        config: config,
        logger: Logger(),
      ).run();

      expect(
        await File(p.join(temp.path, 'lib/core/session/session_service.dart'))
            .exists(),
        isTrue,
      );

      final guards = await File(
        p.join(temp.path, 'lib/app/router/route_guards.dart'),
      ).readAsString();
      expect(guards, contains('SessionService'));
      expect(guards, contains('hasSession'));

      final dio = await File(
        p.join(temp.path, 'lib/core/network/dio_client.dart'),
      ).readAsString();
      expect(dio, contains('tokenProvider'));

      final env = await File(
        p.join(temp.path, 'lib/app/config/environment.dart'),
      ).readAsString();
      expect(env, contains('String.fromEnvironment'));

      final di = await File(
        p.join(temp.path, 'lib/core/di/injection.dart'),
      ).readAsString();
      expect(di, contains('SessionService'));
    });
  });
}
