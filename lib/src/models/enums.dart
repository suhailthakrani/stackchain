/// Supported project architectures.
enum Architecture {
  featureFirst('feature_first'),
  clean('clean'),
  mvvm('mvvm'),
  mvc('mvc');

  const Architecture(this.yaml);
  final String yaml;

  static Architecture fromYaml(String? value) {
    if (value == null) return Architecture.featureFirst;
    return Architecture.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown architecture "$value". '
        'Use: feature_first, clean, mvvm, mvc',
      ),
    );
  }
}

/// Supported state-management options.
enum StateManagement {
  bloc('bloc'),
  cubit('cubit'),
  riverpod('riverpod'),
  provider('provider'),
  getx('getx'),
  rxdart('rxdart');

  const StateManagement(this.yaml);
  final String yaml;

  static StateManagement fromYaml(String? value) {
    if (value == null) return StateManagement.bloc;
    return StateManagement.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown state_management "$value". '
        'Use: bloc, cubit, riverpod, provider, getx, rxdart',
      ),
    );
  }

  /// Whether this stack uses the flutter_bloc package.
  bool get usesFlutterBloc =>
      this == StateManagement.bloc || this == StateManagement.cubit;

  /// Whether presentation uses disposable stream controllers.
  bool get usesRxDart => this == StateManagement.rxdart;
}

/// Supported routers.
enum Routing {
  goRouter('go_router'),
  autoRoute('auto_route'),
  navigator('navigator'),
  getx('getx');

  const Routing(this.yaml);
  final String yaml;

  static Routing fromYaml(String? value) {
    if (value == null) return Routing.goRouter;
    return Routing.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown routing "$value". '
        'Use: go_router, auto_route, navigator, getx',
      ),
    );
  }
}

/// Supported DI containers.
enum DiType {
  getIt('get_it'),
  injectable('injectable'),
  getx('getx');

  const DiType(this.yaml);
  final String yaml;

  static DiType fromYaml(String? value) {
    if (value == null) return DiType.getIt;
    return DiType.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown di "$value". Use: get_it, injectable, getx',
      ),
    );
  }
}

/// Supported HTTP clients.
enum NetworkClient {
  dio('dio'),
  http('http');

  const NetworkClient(this.yaml);
  final String yaml;

  static NetworkClient fromYaml(String? value) {
    if (value == null) return NetworkClient.dio;
    return NetworkClient.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown network "$value". Use: dio, http',
      ),
    );
  }
}

/// Supported local storage backends.
enum StorageType {
  sharedPreferences('shared_preferences'),
  hive('hive'),
  secureStorage('secure_storage');

  const StorageType(this.yaml);
  final String yaml;

  static StorageType fromYaml(String value) {
    return StorageType.values.firstWhere(
      (e) => e.yaml == value,
      orElse: () => throw FormatException(
        'Unknown storage "$value". '
        'Use: shared_preferences, hive, secure_storage',
      ),
    );
  }
}
