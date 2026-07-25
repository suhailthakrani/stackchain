import '../../models/enums.dart';
import '../../models/stackchain_config.dart';

/// App shell: main, App widget, theme, config.
class AppTemplates {
  AppTemplates(this.config);

  final StackchainConfig config;

  String get pkg => config.packageName ?? 'app';

  Map<String, String> generate() {
    return {
      'lib/main.dart': _main(),
      'lib/app/app.dart': _app(),
      'lib/app/theme/app_colors.dart': _colors(),
      'lib/app/theme/app_text_styles.dart': _textStyles(),
      'lib/app/theme/app_spacing.dart': _spacing(),
      'lib/app/theme/app_dimensions.dart': _dimensions(),
      'lib/app/theme/app_theme.dart': _theme(),
      'lib/app/config/constants.dart': _constants(),
      'lib/app/config/environment.dart': _environment(),
    };
  }

  String _main() {
    final imports = <String>{
      "import 'package:flutter/material.dart';",
      "import 'package:$pkg/app/app.dart';",
      "import 'package:$pkg/core/di/injection.dart';",
    };

    if (config.modules.firebase) {
      imports.add("import 'package:firebase_core/firebase_core.dart';");
    }
    if (config.stateManagement == StateManagement.riverpod) {
      imports.add("import 'package:flutter_riverpod/flutter_riverpod.dart';");
    }

    final firebase = config.modules.firebase
        ? '''
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
'''
        : '  WidgetsFlutterBinding.ensureInitialized();\n';

    final riverpod = config.stateManagement == StateManagement.riverpod;
    final sortedImports = (imports.toList()..sort()).join('\n');

    return '''
$sortedImports

Future<void> main() async {
$firebase
  await configureDependencies();
  runApp(${riverpod ? 'const ProviderScope(child: App())' : 'const App()'});
}
''';
  }

  String _app() {
    final routerImport = config.routing == Routing.navigator
        ? ''
        : "import 'package:$pkg/app/router/app_router.dart';\n";

    final themeMode = config.modules.darkMode
        ? 'themeMode: ThemeMode.system,'
        : 'themeMode: ThemeMode.light,';

    final localization = config.modules.localization
        ? '''
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
'''
        : '';

    final l10nImport = config.modules.localization
        ? "import 'package:flutter_gen/gen_l10n/app_localizations.dart';\n"
        : '';

    if (config.routing == Routing.goRouter) {
      return '''
import 'package:flutter/material.dart';
$l10nImport$routerImport
import 'package:$pkg/app/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      $themeMode
$localization
      routerConfig: AppRouter.router,
    );
  }
}
''';
    }

    if (config.routing == Routing.getx) {
      return '''
import 'package:flutter/material.dart';
import 'package:get/get.dart';
$l10nImport$routerImport
import 'package:$pkg/app/theme/app_theme.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      $themeMode
$localization
      initialRoute: AppRouter.initial,
      getPages: AppRouter.pages,
      defaultTransition: Transition.cupertino,
    );
  }
}
''';
    }

    // navigator / auto_route fallback uses MaterialApp + home
    final homeFeature =
        config.features.contains('home') ? 'home' : config.features.first;
    final pageImport = _pageImport(homeFeature);
    return '''
import 'package:flutter/material.dart';
$l10nImport
import 'package:$pkg/app/theme/app_theme.dart';
import 'package:$pkg/$pageImport';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      $themeMode
$localization
      home: const ${_pascal(homeFeature)}Page(),
    );
  }
}
''';
  }

  String _pageImport(String feature) {
    switch (config.architecture) {
      case Architecture.mvvm:
      case Architecture.mvc:
        return 'features/$feature/views/${feature}_page.dart';
      case Architecture.featureFirst:
      case Architecture.clean:
        return 'features/$feature/presentation/pages/${feature}_page.dart';
    }
  }

  String _colors() => '''
import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF1565C0);
  static const Color secondary = Color(0xFF00897B);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);

  static const Color backgroundLight = Color(0xFFF7F9FC);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
}
''';

  String _textStyles() => '''
import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
}
''';

  String _spacing() => '''
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}
''';

  String _dimensions() => '''
abstract final class AppDimensions {
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double buttonHeight = 48;
  static const double iconSm = 16;
  static const double iconMd = 24;
}
''';

  String _theme() => '''
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimensions.dart';

abstract final class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppDimensions.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
        ),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    );
  }
}
''';

  String _constants() => '''
abstract final class AppConstants {
  static const String appName = 'App';
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const int maxRetries = 3;
}
''';

  String _environment() => '''
enum Environment { dev, staging, prod }

abstract final class AppEnvironment {
  static Environment current = Environment.dev;

  static String get apiBaseUrl => switch (current) {
        Environment.dev => 'https://api.dev.example.com',
        Environment.staging => 'https://api.staging.example.com',
        Environment.prod => 'https://api.example.com',
      };

  static bool get isProduction => current == Environment.prod;
}
''';

  static String _pascal(String snake) {
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();
  }
}
