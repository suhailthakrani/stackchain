import '../models/enums.dart';
import '../models/stackchain_config.dart';

/// Naming / path helpers shared by sync, slices, and quality gate.
abstract final class StackPaths {
  static String pascal(String snake) {
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();
  }

  static String pageImport(StackchainConfig config, String feature) {
    switch (config.architecture) {
      case Architecture.mvvm:
      case Architecture.mvc:
        return 'features/$feature/views/${feature}_page.dart';
      case Architecture.featureFirst:
      case Architecture.clean:
        return 'features/$feature/presentation/pages/${feature}_page.dart';
    }
  }

  static String pagePath(StackchainConfig config, String feature) =>
      'lib/${pageImport(config, feature)}';

  static String bindingImport(String feature) =>
      'features/$feature/bindings/${feature}_binding.dart';

  static String routePath(String feature) {
    if (feature == 'home') return '/';
    if (feature == 'splash') return '/splash';
    return '/$feature';
  }

  static bool layered(StackchainConfig config) =>
      config.architecture == Architecture.featureFirst ||
      config.architecture == Architecture.clean;
}
