import 'dart:io';

import 'package:path/path.dart' as p;

import '../merge/region_merger.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../utils/logger.dart';
import '../utils/stack_paths.dart';

/// Result of a post-generate quality gate.
class QualityReport {
  QualityReport({
    List<String>? errors,
    List<String>? warnings,
  })  : errors = errors ?? [],
        warnings = warnings ?? [];

  final List<String> errors;
  final List<String> warnings;

  bool get passed => errors.isEmpty;

  void dump(Logger logger) {
    for (final w in warnings) {
      logger.warn(w);
    }
    for (final e in errors) {
      logger.error(e);
    }
    if (passed) {
      logger.success('Quality gate passed'
          '${warnings.isEmpty ? '' : ' (${warnings.length} warning(s))'}');
    } else {
      logger.error('Quality gate failed (${errors.length} error(s))');
    }
  }
}

/// Validates generated / synced project structure for production trust.
class QualityGate {
  QualityGate({
    required this.root,
    required this.config,
    Logger? logger,
    this.runAnalyzer = true,
    bool? strict,
  })  : logger = logger ?? Logger(),
        strict = strict ?? config.modules.strictQuality;

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool runAnalyzer;
  final bool strict;

  Future<QualityReport> run() async {
    final report = QualityReport();
    logger.step(
      'Running quality gate${strict ? ' (strict)' : ''}...',
    );

    _checkFeatures(report);
    await _checkManagedRegions(report);
    await _checkPubspec(report);
    await _checkSecurityBaseline(report);
    if (runAnalyzer) {
      await _maybeAnalyze(report);
    }

    report.dump(logger);
    return report;
  }

  void _checkFeatures(QualityReport report) {
    for (final f in config.features) {
      final page = StackPaths.pagePath(config, f);
      if (!File(p.join(root, page)).existsSync()) {
        report.errors.add('Missing page for feature "$f": $page');
      }

      if (StackPaths.layered(config)) {
        final entity =
            'lib/features/$f/domain/entities/${f}_entity.dart';
        if (!File(p.join(root, entity)).existsSync()) {
          report.warnings.add('Missing domain entity for "$f": $entity');
        }
      }

      if (config.routing == Routing.getx) {
        final binding =
            'lib/features/$f/bindings/${f}_binding.dart';
        if (!File(p.join(root, binding)).existsSync()) {
          report.errors.add('Missing GetX binding for "$f": $binding');
        }
      }
    }
  }

  Future<void> _checkManagedRegions(QualityReport report) async {
    final routes = File(p.join(root, 'lib/app/router/app_routes.dart'));
    if (await routes.exists()) {
      final content = await routes.readAsString();
      if (!RegionMerger.hasRegion(content, 'routes')) {
        report.warnings.add(
          'app_routes.dart has no <stackchain:routes> region — '
          'run `dart run stackchain sync` to upgrade markers.',
        );
      }
    } else {
      report.warnings.add('Missing lib/app/router/app_routes.dart');
    }

    if (config.routing != Routing.navigator) {
      final router = File(p.join(root, 'lib/app/router/app_router.dart'));
      if (await router.exists()) {
        final content = await router.readAsString();
        if (!RegionMerger.hasRegion(content, 'routes')) {
          report.warnings.add(
            'app_router.dart has no <stackchain:routes> region — '
            'run sync to enable safe merges.',
          );
        } else {
          for (final f in config.features) {
            if (!content.contains('AppRoutes.$f') &&
                !content.contains("name: '$f'")) {
              report.errors.add(
                'Feature "$f" is not wired into app_router.dart',
              );
            }
          }
        }
        if (config.features.contains('auth') &&
            config.routing == Routing.goRouter &&
            !content.contains('redirect:')) {
          report.warnings.add(
            'auth feature present but GoRouter has no redirect — '
            're-run init --overwrite or sync after regenerating router.',
          );
        }
      }
    }

    if (config.di == DiType.getIt) {
      final di = File(p.join(root, 'lib/core/di/injection.dart'));
      if (await di.exists()) {
        final content = await di.readAsString();
        if (!RegionMerger.hasRegion(content, 'features')) {
          report.warnings.add(
            'injection.dart has no <stackchain:features> region — '
            'run sync to enable safe DI merges.',
          );
        }
      }
    }
  }

  Future<void> _checkPubspec(QualityReport report) async {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!await pubspec.exists()) {
      report.errors.add('Missing pubspec.yaml');
      return;
    }
    final content = await pubspec.readAsString();
    final required = config.inferredDependencies().keys;
    for (final pkg in required) {
      if (!RegExp('^\\s*${RegExp.escape(pkg)}:', multiLine: true)
          .hasMatch(content)) {
        report.warnings.add(
          'pubspec.yaml missing inferred dependency "$pkg" — '
          'run `dart run stackchain upgrade`',
        );
      }
    }
  }

  Future<void> _checkSecurityBaseline(QualityReport report) async {
    final session =
        File(p.join(root, 'lib/core/session/session_service.dart'));
    if (!await session.exists()) {
      report.errors.add(
        'Missing SessionService — required for production auth tokens',
      );
    }

    final guards = File(p.join(root, 'lib/app/router/route_guards.dart'));
    if (await guards.exists()) {
      final content = await guards.readAsString();
      if (content.contains('return true;') &&
          !content.contains('hasSession')) {
        report.errors.add(
          'RouteGuards still hardcodes authenticated=true — insecure',
        );
      }
      if (!content.contains('SessionService')) {
        report.warnings.add(
          'RouteGuards is not wired to SessionService',
        );
      }
    }

    if (config.network == NetworkClient.dio) {
      final dio = File(p.join(root, 'lib/core/network/dio_client.dart'));
      if (await dio.exists()) {
        final content = await dio.readAsString();
        if (!content.contains('tokenProvider')) {
          report.warnings.add(
            'DioClient missing tokenProvider wiring for AuthInterceptor',
          );
        }
        if (content.contains('Dio().fetch')) {
          report.errors.add(
            'RetryInterceptor must not create a bare Dio() — '
            'auth headers would be dropped',
          );
        }
      }
    }

    if (config.features.contains('auth') &&
        !config.storage.contains(StorageType.secureStorage)) {
      report.warnings.add(
        'auth feature without secure_storage — tokens may be at risk',
      );
    }

    final env = File(p.join(root, 'lib/app/config/environment.dart'));
    if (await env.exists()) {
      final content = await env.readAsString();
      if (!content.contains('String.fromEnvironment')) {
        report.warnings.add(
          'AppEnvironment should use --dart-define for production flavors',
        );
      }
    }
  }

  Future<void> _maybeAnalyze(QualityReport report) async {
    final dart = await _which('dart');
    if (dart == null) {
      report.warnings.add('dart SDK not on PATH — skipped analyzer pass');
      return;
    }

    final targets = <String>[
      if (Directory(p.join(root, 'lib/app')).existsSync()) 'lib/app',
      if (Directory(p.join(root, 'lib/core')).existsSync()) 'lib/core',
      if (Directory(p.join(root, 'lib/features')).existsSync()) 'lib/features',
    ];
    if (targets.isEmpty) return;

    try {
      final result = await Process.run(
        dart,
        [
          'analyze',
          if (strict) '--fatal-infos',
          ...targets,
        ],
        workingDirectory: root,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        final out = '${result.stdout}\n${result.stderr}'.trim();
        final snippet = out.length > 800 ? '${out.substring(0, 800)}…' : out;
        if (strict) {
          report.errors.add('dart analyze failed (strict):\n$snippet');
        } else {
          report.warnings.add(
            'dart analyze reported issues (non-blocking):\n$snippet',
          );
        }
      }
    } catch (e) {
      report.warnings.add('Could not run dart analyze: $e');
    }
  }

  Future<String?> _which(String cmd) async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [cmd],
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final line = '${result.stdout}'.trim().split('\n').first.trim();
      return line.isEmpty ? null : line;
    } catch (_) {
      return null;
    }
  }
}
