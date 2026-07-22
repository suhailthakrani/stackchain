import 'package:recase/recase.dart';

import '../models/enums.dart';
import '../models/stackchain_config.dart';

/// Paths produced for a single feature under a given architecture.
class FeatureLayout {
  const FeatureLayout({
    required this.root,
    required this.directories,
    required this.stateDir,
    required this.pagesDir,
    required this.widgetsDir,
  });

  final String root;
  final List<String> directories;
  final String stateDir;
  final String pagesDir;
  final String widgetsDir;
}

/// Plugin contract — add architectures without touching the core generator.
abstract class ArchitecturePlugin {
  String get id;

  FeatureLayout layoutFor(String featureName, StackchainConfig config);
}

class FeatureFirstPlugin implements ArchitecturePlugin {
  const FeatureFirstPlugin();

  @override
  String get id => Architecture.featureFirst.yaml;

  @override
  FeatureLayout layoutFor(String featureName, StackchainConfig config) {
    final root = 'lib/features/$featureName';
    final stateFolder = _stateFolder(config.stateManagement);
    final dirs = [
      '$root/data/datasources',
      '$root/data/repositories',
      '$root/data/models',
      '$root/domain/entities',
      '$root/domain/repositories',
      '$root/domain/usecases',
      '$root/presentation/$stateFolder',
      '$root/presentation/pages',
      '$root/presentation/widgets',
    ];
    if (config.stateManagement == StateManagement.getx) {
      dirs.add('$root/bindings');
    }
    return FeatureLayout(
      root: root,
      directories: dirs,
      stateDir: '$root/presentation/$stateFolder',
      pagesDir: '$root/presentation/pages',
      widgetsDir: '$root/presentation/widgets',
    );
  }
}

class CleanPlugin implements ArchitecturePlugin {
  const CleanPlugin();

  @override
  String get id => Architecture.clean.yaml;

  @override
  FeatureLayout layoutFor(String featureName, StackchainConfig config) {
    // Clean keeps the same layered feature layout; difference is conventions
    // in generated repository/use-case wiring (stricter domain isolation).
    return const FeatureFirstPlugin().layoutFor(featureName, config);
  }
}

class MvvmPlugin implements ArchitecturePlugin {
  const MvvmPlugin();

  @override
  String get id => Architecture.mvvm.yaml;

  @override
  FeatureLayout layoutFor(String featureName, StackchainConfig config) {
    final root = 'lib/features/$featureName';
    return FeatureLayout(
      root: root,
      directories: [
        '$root/data',
        '$root/models',
        '$root/viewmodels',
        '$root/views',
        '$root/widgets',
      ],
      stateDir: '$root/viewmodels',
      pagesDir: '$root/views',
      widgetsDir: '$root/widgets',
    );
  }
}

class MvcPlugin implements ArchitecturePlugin {
  const MvcPlugin();

  @override
  String get id => Architecture.mvc.yaml;

  @override
  FeatureLayout layoutFor(String featureName, StackchainConfig config) {
    final root = 'lib/features/$featureName';
    final dirs = [
      '$root/models',
      '$root/controllers',
      '$root/views',
      '$root/widgets',
    ];
    if (config.stateManagement == StateManagement.getx) {
      dirs.add('$root/bindings');
    }
    return FeatureLayout(
      root: root,
      directories: dirs,
      stateDir: '$root/controllers',
      pagesDir: '$root/views',
      widgetsDir: '$root/widgets',
    );
  }
}

String _stateFolder(StateManagement sm) {
  switch (sm) {
    case StateManagement.bloc:
      return 'bloc';
    case StateManagement.cubit:
      return 'cubit';
    case StateManagement.riverpod:
    case StateManagement.provider:
      return 'providers';
    case StateManagement.getx:
      return 'controllers';
  }
}

/// Registry of architecture plugins.
class ArchitectureRegistry {
  ArchitectureRegistry({List<ArchitecturePlugin>? plugins})
      : _plugins = {
          for (final p in plugins ?? _defaults) p.id: p,
        };

  static const _defaults = <ArchitecturePlugin>[
    FeatureFirstPlugin(),
    CleanPlugin(),
    MvvmPlugin(),
    MvcPlugin(),
  ];

  final Map<String, ArchitecturePlugin> _plugins;

  void register(ArchitecturePlugin plugin) {
    _plugins[plugin.id] = plugin;
  }

  ArchitecturePlugin resolve(Architecture architecture) {
    final plugin = _plugins[architecture.yaml];
    if (plugin == null) {
      throw StateError('No architecture plugin for "${architecture.yaml}"');
    }
    return plugin;
  }

  FeatureLayout layoutFor(String featureName, StackchainConfig config) {
    final name = ReCase(featureName).snakeCase;
    return resolve(config.architecture).layoutFor(name, config);
  }
}
