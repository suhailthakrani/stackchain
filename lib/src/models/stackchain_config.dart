import 'enums.dart';

/// Optional product modules toggled from config.
class ModulesConfig {
  const ModulesConfig({
    this.localization = false,
    this.firebase = false,
    this.analytics = false,
    this.crashlytics = false,
    this.biometrics = false,
    this.darkMode = true,
    this.coreServices = true,
    this.coreWidgets = true,
    this.flavors = true,
    this.ci = true,
    this.strictQuality = false,
  });

  final bool localization;
  final bool firebase;
  final bool analytics;
  final bool crashlytics;
  final bool biometrics;
  final bool darkMode;
  final bool coreServices;
  final bool coreWidgets;

  /// Generate flavor entrypoints + dart-define environment.
  final bool flavors;

  /// Generate GitHub Actions CI workflow.
  final bool ci;

  /// Quality gate also fails analyzer infos when true (`--fatal-infos`).
  /// Analyzer errors/warnings always fail the gate regardless.
  final bool strictQuality;

  factory ModulesConfig.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const ModulesConfig();
    return ModulesConfig(
      localization: map['localization'] as bool? ?? false,
      firebase: map['firebase'] as bool? ?? false,
      analytics: map['analytics'] as bool? ?? false,
      crashlytics: map['crashlytics'] as bool? ?? false,
      biometrics: map['biometrics'] as bool? ?? false,
      darkMode: map['dark_mode'] as bool? ?? true,
      coreServices: map['core_services'] as bool? ?? true,
      coreWidgets: map['core_widgets'] as bool? ?? true,
      flavors: map['flavors'] as bool? ?? true,
      ci: map['ci'] as bool? ?? true,
      strictQuality: map['strict_quality'] as bool? ?? false,
    );
  }
}

/// Root configuration loaded from `stackchain.yaml`.
///
/// Missing values are filled with production-ready defaults.
class StackchainConfig {
  StackchainConfig({
    this.architecture = Architecture.featureFirst,
    this.stateManagement = StateManagement.bloc,
    this.routing = Routing.goRouter,
    this.di = DiType.getIt,
    this.network = NetworkClient.dio,
    List<StorageType>? storage,
    this.features = const ['home'],
    ModulesConfig? modules,
    this.packageName,
    this.preset,
  })  : storage = storage ??
            const [StorageType.sharedPreferences, StorageType.secureStorage],
        modules = modules ?? const ModulesConfig();

  final Architecture architecture;
  final StateManagement stateManagement;
  final Routing routing;
  final DiType di;
  final NetworkClient network;
  final List<StorageType> storage;
  final List<String> features;
  final ModulesConfig modules;

  /// Dart package name of the host Flutter app (from pubspec).
  final String? packageName;

  /// Optional blueprint id from [PresetRegistry] (e.g. production_bloc).
  final String? preset;

  /// Defaults used when no YAML exists.
  factory StackchainConfig.defaults({String? packageName}) => StackchainConfig(
        packageName: packageName,
      );

  StackchainConfig copyWith({
    Architecture? architecture,
    StateManagement? stateManagement,
    Routing? routing,
    DiType? di,
    NetworkClient? network,
    List<StorageType>? storage,
    List<String>? features,
    ModulesConfig? modules,
    String? packageName,
    String? preset,
  }) {
    return StackchainConfig(
      architecture: architecture ?? this.architecture,
      stateManagement: stateManagement ?? this.stateManagement,
      routing: routing ?? this.routing,
      di: di ?? this.di,
      network: network ?? this.network,
      storage: storage ?? this.storage,
      features: features ?? this.features,
      modules: modules ?? this.modules,
      packageName: packageName ?? this.packageName,
      preset: preset ?? this.preset,
    );
  }

  /// Pub packages implied by this config (runtime deps).
  Map<String, String> inferredDependencies() {
    final deps = <String, String>{
      'equatable': '^2.0.7',
      'logger': '^2.5.0',
      'connectivity_plus': '^6.1.0',
    };

    switch (stateManagement) {
      case StateManagement.bloc:
      case StateManagement.cubit:
        deps['flutter_bloc'] = '^9.0.0';
        deps['bloc'] = '^9.0.0';
      case StateManagement.riverpod:
        deps['flutter_riverpod'] = '^2.6.1';
      case StateManagement.provider:
        deps['provider'] = '^6.1.2';
      case StateManagement.getx:
        deps['get'] = '^4.6.6';
      case StateManagement.rxdart:
        deps['rxdart'] = '^0.28.0';
    }

    switch (routing) {
      case Routing.goRouter:
        deps['go_router'] = '^14.6.0';
      case Routing.autoRoute:
        deps['auto_route'] = '^9.2.0';
      case Routing.navigator:
        break;
      case Routing.getx:
        deps['get'] = '^4.6.6';
    }

    switch (di) {
      case DiType.getIt:
        deps['get_it'] = '^8.0.0';
      case DiType.injectable:
        deps['get_it'] = '^8.0.0';
        deps['injectable'] = '^2.5.0';
      case DiType.getx:
        deps['get'] = '^4.6.6';
    }

    switch (network) {
      case NetworkClient.dio:
        deps['dio'] = '^5.7.0';
        deps['pretty_dio_logger'] = '^1.4.0';
      case NetworkClient.http:
        deps['http'] = '^1.2.2';
    }

    for (final s in storage) {
      switch (s) {
        case StorageType.sharedPreferences:
          deps['shared_preferences'] = '^2.3.0';
        case StorageType.hive:
          deps['hive'] = '^2.2.3';
          deps['hive_flutter'] = '^1.1.0';
        case StorageType.secureStorage:
          deps['flutter_secure_storage'] = '^9.2.0';
      }
    }

    if (modules.firebase) {
      deps['firebase_core'] = '^3.8.0';
      deps['firebase_auth'] = '^5.3.0';
      deps['cloud_firestore'] = '^5.5.0';
      deps['firebase_messaging'] = '^15.1.0';
      if (modules.analytics || modules.firebase) {
        deps['firebase_analytics'] = '^11.3.0';
      }
      if (modules.crashlytics || modules.firebase) {
        deps['firebase_crashlytics'] = '^4.1.0';
      }
    }

    if (modules.biometrics) {
      deps['local_auth'] = '^2.3.0';
    }

    if (modules.coreServices) {
      deps['permission_handler'] = '^11.3.1';
      deps['image_picker'] = '^1.1.2';
      deps['url_launcher'] = '^6.3.0';
      deps['package_info_plus'] = '^8.0.0';
      deps['device_info_plus'] = '^11.0.0';
      deps['share_plus'] = '^10.0.0';
    }

    if (modules.localization) {
      // intl comes transitively via flutter_localizations — do not pin an
      // older constraint that conflicts with the Flutter SDK.
    }

    return deps;
  }

  /// Dev packages implied by this config.
  Map<String, String> inferredDevDependencies() {
    final deps = <String, String>{
      'flutter_lints': '^5.0.0',
      'mocktail': '^1.0.4',
      'build_runner': '^2.4.13',
    };

    if (stateManagement.usesFlutterBloc) {
      deps['bloc_test'] = '^10.0.0';
    }

    if (di == DiType.injectable) {
      deps['injectable_generator'] = '^2.6.0';
    }

    if (routing == Routing.autoRoute) {
      deps['auto_route_generator'] = '^9.0.0';
    }

    return deps;
  }
}
