import '../../models/enums.dart';
import '../../models/stackchain_config.dart';

/// GoRouter / routes / guards.
class RouterTemplates {
  RouterTemplates(this.config);

  final StackchainConfig config;

  String get pkg => config.packageName ?? 'app';

  Map<String, String> generate() {
    if (config.routing == Routing.navigator) {
      return {
        'lib/app/router/app_routes.dart': _routesOnly(),
      };
    }

    return {
      'lib/app/router/app_routes.dart': _routesOnly(),
      'lib/app/router/route_guards.dart': _guards(),
      'lib/app/router/app_router.dart': _router(),
    };
  }

  String _routesOnly() {
    final buffer = StringBuffer()
      ..writeln('abstract final class AppRoutes {')
      ..writeln('  // <stackchain:routes>');
    for (final f in config.features) {
      final path = f == 'home' || f == 'splash'
          ? (f == 'splash' ? '/splash' : '/')
          : '/$f';
      buffer.writeln("  static const String $f = '$path';");
    }
    buffer
      ..writeln('  // </stackchain:routes>')
      ..writeln('}');
    return buffer.toString();
  }

  String _guards() {
    final hasAuth = config.features.contains('auth');
    final diImport = config.di == DiType.getx
        ? "import 'package:get/get.dart';\n"
        : "import 'package:$pkg/core/di/injection.dart';\n";
    final sessionLookup = config.di == DiType.getx
        ? 'Get.find<SessionService>()'
        : 'getIt<SessionService>()';

    return '''
import 'package:flutter/foundation.dart';
$diImport
import 'package:$pkg/core/session/session_service.dart';

/// Auth gate backed by [SessionService] (secure token store).
abstract final class RouteGuards {
  static Future<bool> get isAuthenticated async {
    try {
      return await $sessionLookup.hasSession;
    } catch (_) {
      return false;
    }
  }

  static bool isPublicLocation(String location) {
    const publicPrefixes = <String>{
      '/auth',
      '/splash',
      '/onboarding',
    };
    return publicPrefixes.any(
      (p) => location == p || location.startsWith('\$p/'),
    );
  }

  static Future<void> clearSession() async {
    try {
      await $sessionLookup.clear();
    } catch (_) {/* DI not ready */}
  }

  static void debugAuth(bool value) {
    if (kDebugMode) {
      // hook for tests
    }
  }
}

${hasAuth ? '' : '// Tip: add an `auth` feature to enable login redirects.\n'}
''';
  }
  String _router() {
    if (config.routing == Routing.autoRoute) {
      return _autoRouteStub();
    }
    if (config.routing == Routing.getx) {
      return _getxRouter();
    }
    return _goRouter();
  }

  String _getxRouter() {
    final importLines = <String>[
      "import 'package:get/get.dart';",
    ];
    final pages = StringBuffer();
    for (final f in config.features) {
      final pascal = _pascal(f);
      importLines.add("import 'package:$pkg/${_pageImport(f)}';");
      importLines.add("import 'package:$pkg/${_bindingImport(f)}';");
      pages.writeln('''
      GetPage(
        name: AppRoutes.$f,
        page: ${pascal}Page.new,
        binding: ${pascal}Binding(),
      ),''');
    }
    importLines.sort();

    final initial = config.features.contains('splash')
        ? 'AppRoutes.splash'
        : (config.features.contains('home')
            ? 'AppRoutes.home'
            : 'AppRoutes.${config.features.first}');

    return '''
${importLines.join('\n')}

import 'app_routes.dart';

abstract final class AppRouter {
  static const String initial = $initial;

  static final List<GetPage<dynamic>> pages = [
    // <stackchain:routes>
$pages
    // </stackchain:routes>
  ];
}
''';
  }

  String _bindingImport(String feature) {
    return 'features/$feature/bindings/${feature}_binding.dart';
  }

  String _goRouter() {
    final importLines = <String>[
      "import 'package:flutter/material.dart';",
      "import 'package:go_router/go_router.dart';",
    ];
    for (final f in config.features) {
      final pagePath = _pageImport(f);
      importLines.add("import 'package:$pkg/$pagePath';");
    }
    importLines.sort();

    final routes = StringBuffer();
    for (final f in config.features) {
      final pascal = _pascal(f);
      final pathExpr = 'AppRoutes.$f';
      routes.writeln('''
      GoRoute(
        path: $pathExpr,
        name: '$f',
        builder: (context, state) => const ${pascal}Page(),
      ),''');
    }

    final initial = config.features.contains('splash')
        ? 'AppRoutes.splash'
        : (config.features.contains('home')
            ? 'AppRoutes.home'
            : 'AppRoutes.${config.features.first}');

    final imports = importLines.join('\n');
    final hasAuth = config.features.contains('auth');
    final redirect = hasAuth
        ? '''
    redirect: (context, state) async {
      final loggedIn = await RouteGuards.isAuthenticated;
      final loc = state.matchedLocation;
      final onAuth = loc == AppRoutes.auth || loc.startsWith('\${AppRoutes.auth}/');
      if (!loggedIn && !RouteGuards.isPublicLocation(loc) && !onAuth) {
        return AppRoutes.auth;
      }
      if (loggedIn && onAuth) {
        return ${config.features.contains('home') ? 'AppRoutes.home' : 'AppRoutes.${config.features.firstWhere((f) => f != 'auth', orElse: () => config.features.first)}'};
      }
      return null;
    },'''
        : '';

    return '''
$imports

import 'app_routes.dart';
import 'route_guards.dart';

abstract final class AppRouter {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: $initial,
$redirect
    routes: [
      // <stackchain:routes>
$routes
      // </stackchain:routes>
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: \${state.uri}')),
    ),
  );
}
''';
  }

  String _autoRouteStub() {
    final imports = StringBuffer();
    final routes = StringBuffer();
    for (final f in config.features) {
      final pascal = _pascal(f);
      imports.writeln("import 'package:$pkg/${_pageImport(f)}';");
      routes.writeln(
          '        AutoRoute(page: ${pascal}Route.page, path: AppRoutes.$f),');
    }

    return '''
import 'package:auto_route/auto_route.dart';

import 'app_routes.dart';
$imports
part 'app_router.gr.dart';

@AutoRouterConfig()
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        // <stackchain:routes>
$routes
        // </stackchain:routes>
      ];
}
''';
  }

  String _pageImport(String feature) {
    final arch = config.architecture;
    switch (arch) {
      case Architecture.mvvm:
        return 'features/$feature/views/${feature}_page.dart';
      case Architecture.mvc:
        return 'features/$feature/views/${feature}_page.dart';
      case Architecture.featureFirst:
      case Architecture.clean:
        return 'features/$feature/presentation/pages/${feature}_page.dart';
    }
  }

  static String _pascal(String snake) {
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();
  }
}
