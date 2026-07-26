import '../models/enums.dart';
import '../models/stackchain_config.dart';

/// Named production blueprints composed on top of stackchain.yaml.
///
/// Usage:
/// ```yaml
/// stackchain:
///   preset: production_bloc
///   features: [auth, home]
/// ```
///
/// Explicit keys in YAML always win over the preset.
class PresetRegistry {
  const PresetRegistry();

  static const Map<String, Map<String, Object?>> presets = {
    'production_bloc': {
      'architecture': 'feature_first',
      'state_management': 'bloc',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'localization': true,
      'dark_mode': true,
      'core_services': true,
      'flavors': true,
      'ci': true,
      'strict_quality': true,
    },
    'production_riverpod': {
      'architecture': 'feature_first',
      'state_management': 'riverpod',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'localization': true,
      'dark_mode': true,
      'flavors': true,
      'ci': true,
      'strict_quality': true,
    },
    'clean_cubit': {
      'architecture': 'clean',
      'state_management': 'cubit',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'flavors': true,
      'ci': true,
    },
    'getx_mvc': {
      'architecture': 'mvc',
      'state_management': 'getx',
      'routing': 'getx',
      'di': 'getx',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'flavors': true,
      'ci': true,
    },
    'firebase_bloc': {
      'architecture': 'feature_first',
      'state_management': 'bloc',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'firebase': true,
      'analytics': true,
      'crashlytics': true,
      'localization': true,
      'flavors': true,
      'ci': true,
      'strict_quality': true,
    },
    'minimal': {
      'architecture': 'feature_first',
      'state_management': 'bloc',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'core_services': false,
      'core_widgets': false,
      'flavors': false,
      'ci': false,
      'strict_quality': false,
    },
    'production_rxdart': {
      'architecture': 'feature_first',
      'state_management': 'rxdart',
      'routing': 'go_router',
      'di': 'get_it',
      'network': 'dio',
      'storage': ['shared_preferences', 'secure_storage'],
      'localization': true,
      'dark_mode': true,
      'flavors': true,
      'ci': true,
      'strict_quality': true,
    },
  };

  /// Lists available preset ids.
  List<String> get ids => presets.keys.toList()..sort();

  /// Merges [presetId] defaults under [user] (user wins).
  Map<String, Object?> expand(
    String? presetId,
    Map<String, Object?> user,
  ) {
    if (presetId == null || presetId.isEmpty) return Map.of(user);
    final base = presets[presetId];
    if (base == null) {
      throw FormatException(
        'Unknown preset "$presetId". Available: ${ids.join(', ')}',
      );
    }
    return {
      ...base,
      ...user,
      // Keep nested module-ish keys from preset when user omitted them.
    };
  }

  /// Human-readable summary for CLI `list` / docs.
  String describe(String id) {
    final p = presets[id];
    if (p == null) return id;
    return '$id → ${p['architecture']}/${p['state_management']}/'
        '${p['routing']}/${p['di']}';
  }
}

/// Applies a preset map onto a partially built config path via YamlParser.
extension PresetApply on StackchainConfig {
  /// Returns a fingerprint used by the upgrade/migration lockfile.
  String stackFingerprint() {
    final storage = this.storage.map((e) => e.yaml).join('+');
    return [
      architecture.yaml,
      stateManagement.yaml,
      routing.yaml,
      di.yaml,
      network.yaml,
      storage,
      modules.localization,
      modules.firebase,
    ].join('|');
  }
}

/// Resolves enum fields from a loose preset/user map (for migrations).
StackchainConfig configFromLooseMap(
  Map<String, Object?> map, {
  required List<String> features,
  String? packageName,
  ModulesConfig? modules,
}) {
  final storageRaw = map['storage'];
  List<StorageType> storage;
  if (storageRaw is List) {
    storage = storageRaw.map((e) => StorageType.fromYaml('$e')).toList();
  } else if (storageRaw is String) {
    storage = [StorageType.fromYaml(storageRaw)];
  } else {
    storage = const [StorageType.sharedPreferences];
  }

  return StackchainConfig(
    architecture: Architecture.fromYaml(map['architecture'] as String?),
    stateManagement:
        StateManagement.fromYaml(map['state_management'] as String?),
    routing: Routing.fromYaml(map['routing'] as String?),
    di: DiType.fromYaml(map['di'] as String?),
    network: NetworkClient.fromYaml(map['network'] as String?),
    storage: storage,
    features: features,
    modules: modules ??
        ModulesConfig.fromMap({
          'localization': map['localization'],
          'firebase': map['firebase'],
          'analytics': map['analytics'],
          'crashlytics': map['crashlytics'],
          'biometrics': map['biometrics'],
          'dark_mode': map['dark_mode'],
          'core_services': map['core_services'],
          'core_widgets': map['core_widgets'],
        }),
    packageName: packageName,
  );
}
