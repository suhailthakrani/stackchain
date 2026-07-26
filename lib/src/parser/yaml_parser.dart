import 'package:yaml/yaml.dart';

import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../presets/preset_registry.dart';

/// Parses and validates `stackchain.yaml`.
class YamlParser {
  /// Loads config from YAML content. Empty / missing root uses defaults.
  static StackchainConfig parse(
    String content, {
    String? packageName,
  }) {
    if (content.trim().isEmpty) {
      return StackchainConfig.defaults(packageName: packageName);
    }

    final dynamic loaded = loadYaml(content);
    if (loaded == null) {
      return StackchainConfig.defaults(packageName: packageName);
    }

    if (loaded is! YamlMap) {
      throw const FormatException('stackchain.yaml must be a YAML map.');
    }

    final root = loaded['stackchain'] ?? loaded['flutter_starter'];
    if (root == null) {
      return StackchainConfig.defaults(packageName: packageName);
    }
    if (root is! YamlMap) {
      throw const FormatException(
        '"stackchain" must be a map.',
      );
    }

    return _fromMap(root, packageName: packageName);
  }

  static StackchainConfig _fromMap(
    YamlMap map, {
    String? packageName,
  }) {
    final user = _yamlToLooseMap(map);
    final presetId = user.remove('preset') as String?;
    final expanded = const PresetRegistry().expand(presetId, user);

    final storageRaw = expanded['storage'];
    final List<StorageType> storage;
    if (storageRaw == null) {
      storage = const [
        StorageType.sharedPreferences,
        StorageType.secureStorage,
      ];
    } else if (storageRaw is String) {
      storage = [StorageType.fromYaml(storageRaw)];
    } else if (storageRaw is List) {
      storage = storageRaw.map((e) => StorageType.fromYaml('$e')).toList();
    } else {
      throw const FormatException(
        '"storage" must be a string or a list of strings.',
      );
    }

    final featuresRaw = expanded['features'];
    final List<String> features;
    if (featuresRaw == null) {
      features = const ['home'];
    } else if (featuresRaw is List) {
      features = featuresRaw
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (features.isEmpty) features.add('home');
    } else {
      throw const FormatException('"features" must be a list.');
    }

    final modulesMap = <dynamic, dynamic>{};
    final nested = expanded['modules'];
    if (nested is Map) {
      modulesMap.addAll(Map<dynamic, dynamic>.from(nested));
    }
    for (final key in [
      'localization',
      'firebase',
      'analytics',
      'crashlytics',
      'biometrics',
      'dark_mode',
      'core_services',
      'core_widgets',
      'flavors',
      'ci',
      'strict_quality',
    ]) {
      if (expanded.containsKey(key) && !modulesMap.containsKey(key)) {
        modulesMap[key] = expanded[key];
      }
    }

    // Smart defaults when GetX is selected.
    final state = StateManagement.fromYaml(
      expanded['state_management'] as String?,
    );
    final routingRaw = expanded['routing'] as String?;
    final diRaw = expanded['di'] as String?;

    final routing = routingRaw != null
        ? Routing.fromYaml(routingRaw)
        : (state == StateManagement.getx ? Routing.getx : Routing.goRouter);

    final di = diRaw != null
        ? DiType.fromYaml(diRaw)
        : (state == StateManagement.getx ? DiType.getx : DiType.getIt);

    return StackchainConfig(
      architecture: Architecture.fromYaml(expanded['architecture'] as String?),
      stateManagement: state,
      routing: routing,
      di: di,
      network: NetworkClient.fromYaml(expanded['network'] as String?),
      storage: storage,
      features: features,
      modules: ModulesConfig.fromMap(modulesMap),
      packageName: packageName,
      preset: presetId,
    );
  }

  static Map<String, Object?> _yamlToLooseMap(YamlMap map) {
    final out = <String, Object?>{};
    for (final entry in map.entries) {
      final key = '${entry.key}';
      final value = entry.value;
      if (value is YamlMap) {
        out[key] = _yamlToLooseMap(value);
      } else if (value is YamlList) {
        out[key] = value.map((e) {
          if (e is YamlMap) return _yamlToLooseMap(e);
          return e;
        }).toList();
      } else {
        out[key] = value;
      }
    }
    return out;
  }
}
