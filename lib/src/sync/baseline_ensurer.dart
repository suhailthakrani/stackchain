import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../templates/app/app_templates.dart';
import '../templates/app/router_templates.dart';
import '../templates/core/core_templates.dart';
import '../utils/logger.dart';

/// Brings older scaffolds up to the current production baseline.
///
/// Writes missing files and upgrades known-legacy stubs without a full
/// `--overwrite` of the whole project.
class BaselineEnsurer {
  BaselineEnsurer({
    required this.root,
    required this.config,
    Logger? logger,
    this.dryRun = false,
  }) : logger = logger ?? Logger();

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool dryRun;

  final List<String> touched = [];

  Future<List<String>> ensure() async {
    logger.step('Ensuring production baseline...');
    final core = CoreTemplates(config).generate();
    final app = AppTemplates(config).generate();
    final router = RouterTemplates(config).generate();

    // Required by RouteGuards / Dio auth wiring.
    await _writeIfMissing(core, 'lib/core/session/session_service.dart');
    await _writeIfMissing(core, 'lib/core/storage/storage_keys.dart');
    if (config.storage.contains(StorageType.sharedPreferences)) {
      await _writeIfMissing(core, 'lib/core/storage/shared_prefs.dart');
    }
    if (config.storage.contains(StorageType.secureStorage)) {
      await _writeIfMissing(core, 'lib/core/storage/secure_storage.dart');
    }

    if (config.network == NetworkClient.dio) {
      await _writeIfMissing(
        core,
        'lib/core/network/interceptors/unauthorized_interceptor.dart',
      );
      await _upgradeIf(
        core,
        'lib/core/network/dio_client.dart',
        needsUpgrade: (c) => !c.contains('tokenProvider'),
      );
      await _upgradeIf(
        core,
        'lib/core/network/interceptors/retry_interceptor.dart',
        needsUpgrade: (c) => c.contains('Dio().fetch'),
      );
    }

    await _upgradeIf(
      app,
      'lib/app/config/environment.dart',
      needsUpgrade: (c) => !c.contains('String.fromEnvironment'),
    );

    await _upgradeIf(
      router,
      'lib/app/router/route_guards.dart',
      needsUpgrade: (c) =>
          !c.contains('SessionService') ||
          (c.contains('return true;') && !c.contains('hasSession')),
    );

    await _ensureInjectionHasSession(core);

    if (touched.isEmpty) {
      logger.detail('Production baseline already present');
    } else {
      logger.success('Baseline updated (${touched.length} file(s))');
    }
    return List.of(touched);
  }

  Future<void> _writeIfMissing(
    Map<String, String> generated,
    String relativePath,
  ) async {
    final content = generated[relativePath];
    if (content == null) return;
    final file = File(p.join(root, relativePath));
    if (await file.exists()) return;
    await _write(relativePath, content);
  }

  Future<void> _upgradeIf(
    Map<String, String> generated,
    String relativePath, {
    required bool Function(String content) needsUpgrade,
  }) async {
    final content = generated[relativePath];
    if (content == null) return;
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) {
      await _write(relativePath, content);
      return;
    }
    final existing = await file.readAsString();
    if (!needsUpgrade(existing)) return;
    await _write(relativePath, content);
  }

  Future<void> _ensureInjectionHasSession(Map<String, String> core) async {
    if (config.di != DiType.getIt) return;
    const path = 'lib/core/di/injection.dart';
    final generated = core[path];
    if (generated == null) return;

    final file = File(p.join(root, path));
    if (!await file.exists()) {
      await _write(path, generated);
      return;
    }

    final existing = await file.readAsString();
    if (existing.contains('SessionService')) return;

    // Legacy get_it injection from older scaffolds — adopt current template.
    // Feature registrations are re-applied by ProjectSync afterward.
    await _write(path, generated);
  }

  Future<void> _write(String relativePath, String content) async {
    touched.add(relativePath);
    if (dryRun) {
      logger.detail('Would ensure $relativePath');
      return;
    }
    final file = File(p.join(root, relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
    logger.detail('Ensured $relativePath');
  }
}
