import '../../models/enums.dart';
import '../../models/stackchain_config.dart';

/// Core infrastructure templates (always generated).
class CoreTemplates {
  CoreTemplates(this.config);

  final StackchainConfig config;
  String get pkg => config.packageName ?? 'app';

  Map<String, String> generate() {
    final files = <String, String>{
      ..._errors(),
      ..._utils(),
      ..._session(),
      ..._di(),
      ..._network(),
      ..._storage(),
    };
    if (config.modules.coreServices) {
      files.addAll(_services());
    }
    if (config.modules.coreWidgets) {
      files.addAll(_widgets());
    }
    return files;
  }

  Map<String, String> _session() {
    final hasSecure = config.storage.contains(StorageType.secureStorage);
    final hasPrefs = config.storage.contains(StorageType.sharedPreferences);
    final imports = <String>[
      "import 'package:$pkg/core/storage/storage_keys.dart';",
      if (hasSecure) "import 'package:$pkg/core/storage/secure_storage.dart';",
      if (hasPrefs) "import 'package:$pkg/core/storage/shared_prefs.dart';",
    ];

    return {
      'lib/core/session/session_service.dart': '''
${imports.join('\n')}

/// Production session boundary — tokens never live in plain UI state.
class SessionService {
  SessionService({
    ${hasSecure ? 'SecureStorageService? secure,' : ''}
    ${hasPrefs ? 'SharedPrefsService? prefs,' : ''}
  })${hasSecure || hasPrefs ? ' :' : ''}
      ${[
        if (hasSecure) '_secure = secure',
        if (hasPrefs) '_prefs = prefs',
      ].join(',\n      ')};

  ${hasSecure ? 'final SecureStorageService? _secure;' : ''}
  ${hasPrefs ? 'final SharedPrefsService? _prefs;' : ''}

  Future<String?> get accessToken async {
    ${hasSecure ? '''
    final fromSecure = await _secure?.read(StorageKeys.accessToken);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
''' : ''}
    ${hasPrefs ? 'return _prefs?.getString(StorageKeys.accessToken);' : 'return null;'}
  }

  Future<String?> get refreshToken async {
    ${hasSecure ? '''
    final fromSecure = await _secure?.read(StorageKeys.refreshToken);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;
''' : ''}
    ${hasPrefs ? 'return _prefs?.getString(StorageKeys.refreshToken);' : 'return null;'}
  }

  Future<bool> get hasSession async {
    final token = await accessToken;
    return token != null && token.isNotEmpty;
  }

  Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
  }) async {
    ${hasSecure ? '''
    await _secure?.write(StorageKeys.accessToken, accessToken);
    if (refreshToken != null) {
      await _secure?.write(StorageKeys.refreshToken, refreshToken);
    }
''' : hasPrefs ? '''
    await _prefs?.setString(StorageKeys.accessToken, accessToken);
    if (refreshToken != null) {
      await _prefs?.setString(StorageKeys.refreshToken, refreshToken);
    }
''' : ''}
  }

  Future<void> clear() async {
    ${hasSecure ? '''
    await _secure?.delete(StorageKeys.accessToken);
    await _secure?.delete(StorageKeys.refreshToken);
''' : ''}
    ${hasPrefs ? '''
    await _prefs?.remove(StorageKeys.accessToken);
    await _prefs?.remove(StorageKeys.refreshToken);
''' : ''}
  }
}
''',
    };
  }


  Map<String, String> _errors() => {
        'lib/core/errors/app_exception.dart': '''
class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppException(\$message)';
}

class NetworkException extends AppException {
  const NetworkException(super.message, {super.code, super.cause});
}

class ServerException extends AppException {
  const ServerException(super.message, {super.code, super.cause});
}

class CacheException extends AppException {
  const CacheException(super.message, {super.code, super.cause});
}

class AuthException extends AppException {
  const AuthException(super.message, {super.code, super.cause});
}
''',
        'lib/core/errors/failure.dart': '''
import 'package:equatable/equatable.dart';

sealed class Failure extends Equatable {
  const Failure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.message = 'Server error']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class AuthFailure extends Failure {
  const AuthFailure([super.message = 'Authentication failed']);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([super.message = 'Unexpected error']);
}
''',
        'lib/core/errors/error_handler.dart': '''
import 'package:logger/logger.dart';

import 'app_exception.dart';
import 'failure.dart';

class ErrorHandler {
  ErrorHandler({Logger? logger}) : _logger = logger ?? Logger();

  final Logger _logger;

  Failure mapException(Object error) {
    _logger.e('Handled error', error: error);
    if (error is NetworkException) return NetworkFailure(error.message);
    if (error is ServerException) return ServerFailure(error.message);
    if (error is CacheException) return CacheFailure(error.message);
    if (error is AuthException) return AuthFailure(error.message);
    if (error is AppException) return UnexpectedFailure(error.message);
    return UnexpectedFailure(error.toString());
  }

  String userMessage(Failure failure) => failure.message;
}
''',
        'lib/core/errors/error_mapper.dart': '''
import 'failure.dart';

/// Maps domain [Failure]s to UI-friendly copy.
abstract final class ErrorMapper {
  static String toMessage(Failure failure) => switch (failure) {
        NetworkFailure() => 'Please check your connection and try again.',
        ServerFailure() => 'Something went wrong on our side. Try again later.',
        AuthFailure() => 'Please sign in again.',
        CacheFailure() => 'Could not load saved data.',
        UnexpectedFailure() => failure.message,
      };
}
''',
        'lib/core/errors/error_messages.dart': '''
abstract final class ErrorMessages {
  static const String generic = 'Something went wrong';
  static const String offline = 'You appear to be offline';
  static const String timeout = 'Request timed out';
  static const String unauthorized = 'Session expired';
}
''',
      };

  Map<String, String> _utils() => {
        'lib/core/utils/validators.dart': '''
abstract final class Validators {
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+\$').hasMatch(value.trim());
    return ok ? null : 'Enter a valid email';
  }

  static String? password(String? value, {int min = 8}) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < min) return 'Password must be at least \$min characters';
    return null;
  }

  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '\$field is required';
    return null;
  }
}
''',
        'lib/core/utils/extensions.dart': '''
import 'package:flutter/material.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;
  MediaQueryData get mq => MediaQuery.of(this);
  Size get screenSize => mq.size;

  void showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? colors.error : null,
      ),
    );
  }
}

extension StringX on String {
  String get capitalize =>
      isEmpty ? this : '\${this[0].toUpperCase()}\${substring(1)}';
}
''',
        'lib/core/utils/debouncer.dart': '''
import 'dart:async';

class Debouncer {
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  Timer? _timer;

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() => _timer?.cancel();
}

typedef VoidCallback = void Function();
''',
        'lib/core/utils/date_utils.dart': '''
abstract final class AppDateUtils {
  static String formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '\$y-\$m-\$d';
  }

  static String timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '\${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '\${diff.inHours}h ago';
    if (diff.inDays < 7) return '\${diff.inDays}d ago';
    return formatDate(date);
  }
}
''',
        'lib/core/utils/helpers.dart': '''
import 'package:flutter/foundation.dart';

abstract final class Helpers {
  static void debugLog(Object? message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }

  static T? castOrNull<T>(Object? value) => value is T ? value : null;
}
''',
      };

  Map<String, String> _di() {
    if (config.di == DiType.getx) {
      return {
        'lib/core/di/injection.dart': _getxInjection(),
      };
    }

    if (config.di == DiType.injectable) {
      return {
        'lib/core/di/injection.dart': '''
// Application dependency injection (injectable).
// Run: dart run build_runner build --delete-conflicting-outputs
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'injection.config.dart';

final getIt = GetIt.instance;

@InjectableInit()
Future<void> configureDependencies() async => getIt.init();
''',
        'lib/core/di/injection.config.dart': '''
// GENERATED PLACEHOLDER — run:
//   dart run build_runner build --delete-conflicting-outputs
// after adding @injectable annotations.
//
// Until then, register manually in injection.dart or use get_it mode.

import 'package:get_it/get_it.dart';

extension GetItInjectableX on GetIt {
  Future<GetIt> init() async {
    // Registrations will be generated by injectable_generator.
    return this;
  }
}
''',
        'lib/core/di/modules/core_module.dart': _coreModuleInjectable(),
      };
    }

    // get_it manual registration
    return {
      'lib/core/di/injection.dart': _getItInjection(),
    };
  }

  String _coreModuleInjectable() => '''
import 'package:injectable/injectable.dart';
import 'package:logger/logger.dart';

@module
abstract class CoreModule {
  @lazySingleton
  Logger get logger => Logger();
}
''';

  String _getxInjection() {
    final packageImports = <String>{
      "import 'package:get/get.dart';",
      "import 'package:logger/logger.dart';",
    };
    final coreImports = <String>{
      "import 'package:$pkg/core/errors/error_handler.dart';",
      "import 'package:$pkg/core/session/session_service.dart';",
    };

    final body = StringBuffer();

    body
      ..writeln('  // ── Logging & errors ───────────────────────────────────')
      ..writeln('  Get.put<Logger>(Logger(), permanent: true);')
      ..writeln(
        '  Get.put<ErrorHandler>('
        'ErrorHandler(logger: Get.find()), permanent: true);',
      )
      ..writeln();

    final hasPrefs = config.storage.contains(StorageType.sharedPreferences);
    final hasSecure = config.storage.contains(StorageType.secureStorage);
    if (hasPrefs || hasSecure) {
      body.writeln('  // ── Storage ─────────────────────────────────────────');
      if (hasPrefs) {
        coreImports.add("import 'package:$pkg/core/storage/shared_prefs.dart';");
        body
          ..writeln('  final prefs = await SharedPrefsService.create();')
          ..writeln(
            '  Get.put<SharedPrefsService>(prefs, permanent: true);',
          );
      }
      if (hasSecure) {
        coreImports
            .add("import 'package:$pkg/core/storage/secure_storage.dart';");
        body.writeln(
          '  Get.put<SecureStorageService>('
          'SecureStorageService(), permanent: true);',
        );
      }
      body.writeln();
    }

    body
      ..writeln('  // ── Session ──────────────────────────────────────────')
      ..writeln('  Get.put<SessionService>(')
      ..writeln('    SessionService(');
    if (hasSecure) body.writeln('      secure: Get.find(),');
    if (hasPrefs) body.writeln('      prefs: Get.find(),');
    body
      ..writeln('    ),')
      ..writeln('    permanent: true,')
      ..writeln('  );')
      ..writeln();

    if (config.network == NetworkClient.dio) {
      coreImports
        ..add("import 'package:$pkg/core/network/api_client.dart';")
        ..add("import 'package:$pkg/core/network/dio_client.dart';");
      body
        ..writeln('  // ── Network ──────────────────────────────────────────')
        ..writeln('  Get.lazyPut<DioClient>(')
        ..writeln('    () => DioClient(')
        ..writeln(
          '      tokenProvider: () => Get.find<SessionService>().accessToken,',
        )
        ..writeln(
          '      onUnauthorized: () => Get.find<SessionService>().clear(),',
        )
        ..writeln('    ),')
        ..writeln('    fenix: true,')
        ..writeln('  );')
        ..writeln(
          '  Get.lazyPut<ApiClient>(() => ApiClient(Get.find()), fenix: true);',
        )
        ..writeln();
    }

    if (config.modules.coreServices) {
      coreImports
        ..add(
          "import 'package:$pkg/core/services/connectivity_service.dart';",
        )
        ..add(
          "import 'package:$pkg/core/services/logger_service.dart';",
        );
      body
        ..writeln('  // ── Core services ────────────────────────────────────')
        ..writeln(
          '  Get.lazyPut<ConnectivityService>('
          'ConnectivityService.new, fenix: true);',
        )
        ..writeln(
          '  Get.lazyPut<LoggerService>('
          '() => LoggerService(Get.find()), fenix: true);',
        )
        ..writeln();
    }

    return '''
/// Application dependency injection (GetX).
///
/// Registers core services used across the app. Feature bindings live with
/// each feature when using GetX routing.
${_formatImports(packageImports, coreImports, const {})}
Future<void> configureDependencies() async {
${body.toString().trimRight()}
}
''';
  }

  String _getItInjection() {
    final packageImports = <String>{
      "import 'package:get_it/get_it.dart';",
      "import 'package:logger/logger.dart';",
    };
    final coreImports = <String>{
      "import 'package:$pkg/core/errors/error_handler.dart';",
      "import 'package:$pkg/core/session/session_service.dart';",
    };
    final featureImports = <String>{};

    final core = StringBuffer();
    final features = StringBuffer();

    core
      ..writeln('  // ── Logging & errors ───────────────────────────────────')
      ..writeln('  getIt.registerLazySingleton<Logger>(Logger.new);')
      ..writeln(
        '  getIt.registerLazySingleton<ErrorHandler>('
        '() => ErrorHandler(logger: getIt()));',
      )
      ..writeln();

    final hasPrefs = config.storage.contains(StorageType.sharedPreferences);
    final hasSecure = config.storage.contains(StorageType.secureStorage);
    if (hasPrefs || hasSecure) {
      core.writeln('  // ── Storage ─────────────────────────────────────────');
      if (hasPrefs) {
        coreImports.add("import 'package:$pkg/core/storage/shared_prefs.dart';");
        core
          ..writeln('  final prefs = await SharedPrefsService.create();')
          ..writeln('  getIt.registerSingleton<SharedPrefsService>(prefs);');
      }
      if (hasSecure) {
        coreImports
            .add("import 'package:$pkg/core/storage/secure_storage.dart';");
        core.writeln(
          '  getIt.registerLazySingleton<SecureStorageService>('
          'SecureStorageService.new);',
        );
      }
      core.writeln();
    }

    final sessionArgs = <String>[
      if (hasSecure) 'secure: getIt()',
      if (hasPrefs) 'prefs: getIt()',
    ];
    core
      ..writeln('  // ── Session ──────────────────────────────────────────')
      ..writeln(
        '  getIt.registerLazySingleton<SessionService>('
        '() => SessionService(${sessionArgs.join(', ')}));',
      )
      ..writeln();

    if (config.network == NetworkClient.dio) {
      coreImports
        ..add("import 'package:$pkg/core/network/api_client.dart';")
        ..add("import 'package:$pkg/core/network/dio_client.dart';");
      core
        ..writeln('  // ── Network ──────────────────────────────────────────')
        ..writeln('  getIt.registerLazySingleton<DioClient>(')
        ..writeln('    () => DioClient(')
        ..writeln(
          '      tokenProvider: () => getIt<SessionService>().accessToken,',
        )
        ..writeln(
          '      onUnauthorized: () => getIt<SessionService>().clear(),',
        )
        ..writeln('    ),')
        ..writeln('  );')
        ..writeln(
          '  getIt.registerLazySingleton<ApiClient>('
          '() => ApiClient(getIt<DioClient>()));',
        )
        ..writeln();
    }

    if (config.modules.coreServices) {
      coreImports
        ..add(
          "import 'package:$pkg/core/services/connectivity_service.dart';",
        )
        ..add(
          "import 'package:$pkg/core/services/logger_service.dart';",
        );
      core
        ..writeln('  // ── Core services ────────────────────────────────────')
        ..writeln(
          '  getIt.registerLazySingleton<ConnectivityService>('
          'ConnectivityService.new);',
        )
        ..writeln(
          '  getIt.registerLazySingleton<LoggerService>('
          '() => LoggerService(getIt()));',
        )
        ..writeln();
    }

    if (_layeredArch) {
      for (final f in config.features) {
        final pascal = _pascal(f);
        featureImports
          ..add(
            "import 'package:$pkg/features/$f/data/datasources/${f}_remote_datasource.dart';",
          )
          ..add(
            "import 'package:$pkg/features/$f/data/repositories/${f}_repository_impl.dart';",
          )
          ..add(
            "import 'package:$pkg/features/$f/domain/repositories/${f}_repository.dart';",
          )
          ..add(
            "import 'package:$pkg/features/$f/domain/usecases/get_$f.dart';",
          );

        features
          ..writeln('  // ── $f ─────────────────────────────────────────────')
          ..writeln(
            '  getIt.registerLazySingleton<${pascal}RemoteDataSource>('
            '${pascal}RemoteDataSourceImpl.new);',
          )
          ..writeln(
            '  getIt.registerLazySingleton<${pascal}Repository>('
            '() => ${pascal}RepositoryImpl(getIt()));',
          )
          ..writeln(
            '  getIt.registerLazySingleton<Get$pascal>('
            '() => Get$pascal(getIt()));',
          );

        if (config.stateManagement == StateManagement.bloc) {
          featureImports.add(
            "import 'package:$pkg/features/$f/presentation/bloc/${f}_bloc.dart';",
          );
          features.writeln(
            '  getIt.registerFactory<${pascal}Bloc>(${pascal}Bloc.new);',
          );
        } else if (config.stateManagement == StateManagement.cubit) {
          featureImports.add(
            "import 'package:$pkg/features/$f/presentation/cubit/${f}_cubit.dart';",
          );
          features.writeln(
            '  getIt.registerFactory<${pascal}Cubit>(${pascal}Cubit.new);',
          );
        } else if (config.stateManagement == StateManagement.rxdart) {
          featureImports.add(
            "import 'package:$pkg/features/$f/presentation/controllers/${f}_controller.dart';",
          );
          features.writeln(
            '  getIt.registerFactory<${pascal}Controller>('
            '${pascal}Controller.new);',
          );
        }
        features.writeln();
      }
    }

    return '''
${_diFileDoc(diName: 'GetIt')}
${_formatImports(packageImports, coreImports, featureImports)}
final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // <stackchain:core>
${core.toString().trimRight()}
  // </stackchain:core>

  // <stackchain:features>
${features.toString().trimRight()}
  // </stackchain:features>
}
''';
  }

  String _diFileDoc({required String diName}) => '''
// Application dependency injection ($diName).
//
// Owned by stackchain:
// - <stackchain:core> — logging, storage, session, network, services
// - <stackchain:features> — per-feature data + presentation bindings
//
// Re-run `dart run stackchain sync` after adding/removing features.
// Put hand-written registrations outside those markers.
''';

  String _formatImports(
    Set<String> packageImports,
    Set<String> coreImports,
    Set<String> featureImports,
  ) {
    final buf = StringBuffer();
    void writeGroup(Iterable<String> lines) {
      final sorted = lines.toList()..sort();
      if (sorted.isEmpty) return;
      if (buf.isNotEmpty) buf.writeln();
      for (final line in sorted) {
        buf.writeln(line);
      }
    }

    writeGroup(packageImports);
    writeGroup(coreImports);
    writeGroup(featureImports);
    buf.writeln();
    return buf.toString();
  }

  bool get _layeredArch =>
      config.architecture == Architecture.featureFirst ||
      config.architecture == Architecture.clean;

  Map<String, String> _network() {
    if (config.network == NetworkClient.http) {
      return {
        'lib/core/network/api_constants.dart': _apiConstants(),
        'lib/core/network/api_client.dart': '''
import 'package:http/http.dart' as http;

import 'package:$pkg/app/config/environment.dart';
import 'api_constants.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) =>
      Uri.parse('\${AppEnvironment.apiBaseUrl}\$path');

  Future<http.Response> get(String path) =>
      _client.get(_uri(path), headers: ApiConstants.jsonHeaders);

  Future<http.Response> post(String path, {Object? body}) =>
      _client.post(_uri(path), headers: ApiConstants.jsonHeaders, body: body);
}
''',
      };
    }

    return {
      'lib/core/network/api_constants.dart': _apiConstants(),
      'lib/core/network/network_info.dart': '''
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkInfo {
  NetworkInfo({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}
''',
      'lib/core/network/interceptors/auth_interceptor.dart': '''
import 'package:dio/dio.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({this.tokenProvider});

  final Future<String?> Function()? tokenProvider;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer \$token';
    }
    handler.next(options);
  }
}
''',
      'lib/core/network/interceptors/logger_interceptor.dart': '''
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

PrettyDioLogger createLoggerInterceptor() => PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: true,
      compact: true,
    );
''',
      'lib/core/network/interceptors/error_interceptor.dart': '''
import 'package:dio/dio.dart';

import 'package:$pkg/core/errors/app_exception.dart';

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final exception = switch (err.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        const NetworkException('Request timed out'),
      DioExceptionType.connectionError =>
        const NetworkException('No internet connection'),
      DioExceptionType.badResponse => ServerException(
          err.response?.statusMessage ?? 'Server error',
          code: '\${err.response?.statusCode}',
        ),
      _ => AppException(err.message ?? 'Unexpected network error'),
    };
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: exception,
        type: err.type,
        response: err.response,
      ),
    );
  }
}
''',
      'lib/core/network/interceptors/retry_interceptor.dart': '''
import 'package:dio/dio.dart';

class RetryInterceptor extends Interceptor {
  RetryInterceptor(this._dio, {this.maxRetries = 2});

  final Dio _dio;
  final int maxRetries;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final extra = err.requestOptions.extra;
    final retryCount = (extra['retryCount'] as int?) ?? 0;
    final retriable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (retriable && retryCount < maxRetries) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;
      try {
        // Reuse the same client so auth headers / baseUrl survive retries.
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (_) {/* fall through */}
    }
    handler.next(err);
  }
}
''',
      'lib/core/network/interceptors/unauthorized_interceptor.dart': '''
import 'package:dio/dio.dart';

/// Clears session on 401 so route guards bounce to login.
class UnauthorizedInterceptor extends Interceptor {
  UnauthorizedInterceptor({required this.onUnauthorized});

  final Future<void> Function() onUnauthorized;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      await onUnauthorized();
    }
    handler.next(err);
  }
}
''',
      'lib/core/network/dio_client.dart': '''
import 'package:dio/dio.dart';

import 'package:$pkg/app/config/constants.dart';
import 'package:$pkg/app/config/environment.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logger_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'interceptors/unauthorized_interceptor.dart';

class DioClient {
  DioClient({
    Dio? dio,
    Future<String?> Function()? tokenProvider,
    Future<void> Function()? onUnauthorized,
  }) : _dio = dio ?? Dio() {
    _dio
      ..options = BaseOptions(
        baseUrl: AppEnvironment.apiBaseUrl,
        connectTimeout: AppConstants.defaultTimeout,
        receiveTimeout: AppConstants.defaultTimeout,
        headers: {'Accept': 'application/json'},
      )
      ..interceptors.addAll([
        AuthInterceptor(tokenProvider: tokenProvider),
        if (onUnauthorized != null)
          UnauthorizedInterceptor(onUnauthorized: onUnauthorized),
        RetryInterceptor(_dio),
        ErrorInterceptor(),
        if (!AppEnvironment.isProduction) createLoggerInterceptor(),
      ]);
  }

  final Dio _dio;
  Dio get dio => _dio;
}
''',
      'lib/core/network/api_client.dart': '''
import 'package:dio/dio.dart';

import 'dio_client.dart';

class ApiClient {
  ApiClient(this._client);

  final DioClient _client;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _client.dio.get<T>(path, queryParameters: query);

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
  }) =>
      _client.dio.post<T>(path, data: data);

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
  }) =>
      _client.dio.put<T>(path, data: data);

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
  }) =>
      _client.dio.patch<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) =>
      _client.dio.delete<T>(path);

  Future<Response<T>> upload<T>(
    String path, {
    required FormData data,
  }) =>
      _client.dio.post<T>(path, data: data);
}
''',
    };
  }

  String _apiConstants() => '''
abstract final class ApiConstants {
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String profile = '/me';
}
''';

  Map<String, String> _storage() {
    final files = <String, String>{
      'lib/core/storage/storage_keys.dart': '''
abstract final class StorageKeys {
  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String themeMode = 'theme_mode';
  static const String locale = 'locale';
  static const String onboardingDone = 'onboarding_done';
}
''',
    };

    if (config.storage.contains(StorageType.sharedPreferences)) {
      files['lib/core/storage/shared_prefs.dart'] = '''
import 'package:shared_preferences/shared_preferences.dart';

class SharedPrefsService {
  SharedPrefsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPrefsService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsService(prefs);
  }

  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  String? getString(String key) => _prefs.getString(key);

  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool(key) ?? defaultValue;

  Future<bool> remove(String key) => _prefs.remove(key);

  Future<bool> clear() => _prefs.clear();
}
''';
    }

    if (config.storage.contains(StorageType.secureStorage)) {
      files['lib/core/storage/secure_storage.dart'] = '''
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> clear() => _storage.deleteAll();
}
''';
    }

    if (config.storage.contains(StorageType.hive)) {
      files['lib/core/storage/local_database.dart'] = '''
import 'package:hive_flutter/hive_flutter.dart';

class LocalDatabase {
  static const String defaultBox = 'app_box';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(defaultBox);
  }

  Box get box => Hive.box(defaultBox);

  Future<void> put(String key, dynamic value) => box.put(key, value);

  T? get<T>(String key) => box.get(key) as T?;

  Future<void> delete(String key) => box.delete(key);
}
''';
    }

    files['lib/core/storage/cache_manager.dart'] = '''
class CacheManager {
  CacheManager({Duration ttl = const Duration(minutes: 15)}) : _ttl = ttl;

  final Duration _ttl;
  final Map<String, _CacheEntry> _cache = {};

  void set(String key, Object value) {
    _cache[key] = _CacheEntry(value, DateTime.now().add(_ttl));
  }

  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    return entry.value as T?;
  }

  void invalidate(String key) => _cache.remove(key);

  void clear() => _cache.clear();
}

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAt);
  final Object value;
  final DateTime expiresAt;
}
''';

    return files;
  }

  Map<String, String> _services() {
    final files = <String, String>{
      'lib/core/services/logger_service.dart': '''
import 'package:logger/logger.dart';

class LoggerService {
  LoggerService(this._logger);

  final Logger _logger;

  void d(String message) => _logger.d(message);
  void i(String message) => _logger.i(message);
  void w(String message) => _logger.w(message);
  void e(String message, {Object? error, StackTrace? stack}) =>
      _logger.e(message, error: error, stackTrace: stack);
}
''',
      'lib/core/services/connectivity_service.dart': '''
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged;

  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
}
''',
      'lib/core/services/permission_service.dart': '''
import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> request(Permission permission) async {
    final status = await permission.request();
    return status.isGranted;
  }

  Future<bool> camera() => request(Permission.camera);
  Future<bool> photos() => request(Permission.photos);
  Future<bool> microphone() => request(Permission.microphone);
  Future<bool> location() => request(Permission.location);
  Future<bool> notification() => request(Permission.notification);
  Future<bool> contacts() => request(Permission.contacts);
  Future<bool> bluetooth() => request(Permission.bluetooth);
  Future<bool> storage() => request(Permission.storage);
}
''',
      'lib/core/services/analytics_service.dart': '''
class AnalyticsService {
  Future<void> logEvent(String name, {Map<String, Object>? params}) async {
    // Wire to Firebase Analytics / Segment / etc.
  }

  Future<void> setUserId(String? id) async {}

  Future<void> screenView(String screenName) async {
    await logEvent('screen_view', params: {'screen': screenName});
  }
}
''',
      'lib/core/services/notification_service.dart': '''
class NotificationService {
  Future<void> init() async {
    // Initialize FCM / local notifications here.
  }

  Future<String?> get token async => null;

  Future<void> showLocal({
    required String title,
    required String body,
  }) async {}
}
''',
      'lib/core/services/app_info_service.dart': '''
import 'package:package_info_plus/package_info_plus.dart';

class AppInfoService {
  PackageInfo? _info;

  Future<void> init() async {
    _info = await PackageInfo.fromPlatform();
  }

  String get appName => _info?.appName ?? '';
  String get version => _info?.version ?? '';
  String get buildNumber => _info?.buildNumber ?? '';
}
''',
      'lib/core/services/device_service.dart': '''
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceService {
  final DeviceInfoPlugin _plugin = DeviceInfoPlugin();

  Future<String> get deviceLabel async {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await _plugin.androidInfo;
        return '\${info.brand} \${info.model}';
      case TargetPlatform.iOS:
        final info = await _plugin.iosInfo;
        return '\${info.name} \${info.model}';
      default:
        return defaultTargetPlatform.name;
    }
  }
}
''',
      'lib/core/services/share_service.dart': '''
import 'package:share_plus/share_plus.dart';

class ShareService {
  Future<void> shareText(String text, {String? subject}) =>
      Share.share(text, subject: subject);
}
''',
      'lib/core/services/image_picker_service.dart': '''
import 'package:image_picker/image_picker.dart';

class ImagePickerService {
  ImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<XFile?> fromGallery() =>
      _picker.pickImage(source: ImageSource.gallery);

  Future<XFile?> fromCamera() =>
      _picker.pickImage(source: ImageSource.camera);
}
''',
    };

    if (config.modules.biometrics) {
      files['lib/core/services/biometric_service.dart'] = '''
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> get canCheck async => _auth.canCheckBiometrics;

  Future<bool> authenticate({String reason = 'Authenticate'}) async {
    return _auth.authenticate(localizedReason: reason);
  }
}
''';
    }

    return files;
  }

  Map<String, String> _widgets() => {
        'lib/core/widgets/app_button.dart': '''
import 'package:flutter/material.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);

    final button = FilledButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
''',
        'lib/core/widgets/app_text_field.dart': '''
import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.validator,
    this.keyboardType,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
''',
        'lib/core/widgets/app_loader.dart': '''
import 'package:flutter/material.dart';

class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!),
          ],
        ],
      ),
    );
  }
}
''',
        'lib/core/widgets/app_snackbar.dart': '''
import 'package:flutter/material.dart';

abstract final class AppSnackbar {
  static void show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}
''',
        'lib/core/widgets/app_empty_widget.dart': '''
import 'package:flutter/material.dart';

class AppEmptyWidget extends StatelessWidget {
  const AppEmptyWidget({
    super.key,
    this.title = 'Nothing here yet',
    this.subtitle,
    this.action,
  });

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
''',
        'lib/core/widgets/app_error_widget.dart': '''
import 'package:flutter/material.dart';

class AppErrorWidget extends StatelessWidget {
  const AppErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
''',
        'lib/core/widgets/app_scaffold.dart': '''
import 'package:flutter/material.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.title,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.actions,
  });

  final String? title;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: title == null
          ? null
          : AppBar(title: Text(title!), actions: actions),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
''',
        'lib/core/widgets/app_dialog.dart': '''
import 'package:flutter/material.dart';

abstract final class AppDialog {
  static Future<bool?> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
''',
      };

  static String _pascal(String snake) {
    return snake
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();
  }
}
