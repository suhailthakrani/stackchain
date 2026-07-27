import 'dart:io';

import 'package:path/path.dart' as p;

import '../merge/dart_import_merger.dart';
import '../merge/region_merger.dart';
import '../merge/smart_file_merger.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../templates/app/router_templates.dart';
import '../templates/core/core_templates.dart';
import '../utils/logger.dart';
import '../utils/stack_paths.dart';
import 'baseline_ensurer.dart';

/// Incrementally wires router + DI from [StackchainConfig] using smart merges.
///
/// Prefer this over full `--overwrite` after the first init.
class ProjectSync {
  ProjectSync({
    required this.root,
    required this.config,
    Logger? logger,
    this.dryRun = false,
    SmartFileMerger? merger,
  })  : logger = logger ?? Logger(),
        merger = merger ?? const SmartFileMerger();

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool dryRun;
  final SmartFileMerger merger;

  final List<String> touched = [];

  Future<void> run() async {
    final baseline = await BaselineEnsurer(
      root: root,
      config: config,
      logger: logger,
      dryRun: dryRun,
    ).ensure();
    touched.addAll(baseline);

    logger.step('Syncing managed regions (router + DI)...');
    await _syncRoutes();
    await _syncRouter();
    await _syncDi();
    await _ensureGetxBindings();
    // Always keep guards aligned with SessionService once baseline exists.
    await _ensureRouteGuards();
    // Drop imports for features no longer in config (after remove / yaml edit).
    await _pruneStaleFeatureImports('lib/app/router/app_router.dart');
    await _pruneStaleFeatureImports('lib/core/di/injection.dart');
    if (touched.isEmpty) {
      final router = File(p.join(root, 'lib/app/router/app_routes.dart'));
      if (!await router.exists()) {
        logger.info('Nothing to sync — run `dart run stackchain init` first.');
      } else {
        logger.success('Managed regions already up to date');
      }
    } else {
      logger.success('Synced ${touched.length} file(s)');
    }
  }

  Future<void> _syncRoutes() async {
    const path = 'lib/app/router/app_routes.dart';
    final generated = RouterTemplates(config).generate()[path];
    if (generated == null) return;

    final body = _routesRegionBody();
    await _writeMerged(
      path,
      seed: generated,
      regionId: 'routes',
      regionBody: body,
      regionIds: const ['routes'],
    );
  }

  String _routesRegionBody() {
    final buffer = StringBuffer();
    for (final f in config.features) {
      buffer.writeln(
        "  static const String $f = '${StackPaths.routePath(f)}';",
      );
    }
    return buffer.toString();
  }

  Future<void> _syncRouter() async {
    if (config.routing == Routing.navigator) return;
    const path = 'lib/app/router/app_router.dart';
    final generated = RouterTemplates(config).generate()[path];
    if (generated == null) return;

    final imports = <String>[
      for (final f in config.features)
        'package:${config.packageName}/${StackPaths.pageImport(config, f)}',
      if (config.routing == Routing.getx)
        for (final f in config.features)
          'package:${config.packageName}/${StackPaths.bindingImport(f)}',
    ];

    await _writeMerged(
      path,
      seed: generated,
      regionId: 'routes',
      regionBody: _routerRoutesBody(),
      imports: imports,
      regionIds: const ['routes'],
    );

    if (config.routing == Routing.goRouter) {
      if (config.features.contains('auth')) {
        await _ensureGoRouterAuthRedirect(path);
      } else {
        await _stripGoRouterAuthRedirect(path);
      }
    }
  }

  /// Ensures GoRouter has auth redirect + guards import after feature add.
  Future<void> _ensureGoRouterAuthRedirect(String relativePath) async {
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) return;
    var content = await file.readAsString();
    var changed = false;

    if (!content.contains("import 'route_guards.dart';")) {
      content = content.replaceFirst(
        "import 'app_routes.dart';",
        "import 'app_routes.dart';\nimport 'route_guards.dart';",
      );
      changed = true;
    }

    if (!content.contains('redirect:')) {
      final homeTarget = config.features.contains('home')
          ? 'AppRoutes.home'
          : 'AppRoutes.${config.features.firstWhere((f) => f != 'auth', orElse: () => config.features.first)}';
      const needle = 'initialLocation:';
      final idx = content.indexOf(needle);
      if (idx >= 0) {
        final lineEnd = content.indexOf('\n', idx);
        if (lineEnd > 0) {
          final redirect = '''
    redirect: (context, state) async {
      final loggedIn = await RouteGuards.isAuthenticated;
      final loc = state.matchedLocation;
      final onAuth = loc == AppRoutes.auth || loc.startsWith('\${AppRoutes.auth}/');
      if (!loggedIn && !RouteGuards.isPublicLocation(loc) && !onAuth) {
        return AppRoutes.auth;
      }
      if (loggedIn && onAuth) {
        return $homeTarget;
      }
      return null;
    },''';
          content =
              '${content.substring(0, lineEnd + 1)}$redirect\n${content.substring(lineEnd + 1)}';
          changed = true;
        }
      }
    }

    await _ensureRouteGuards();

    if (!changed) return;
    if (dryRun) {
      logger.detail('Would patch auth redirect into $relativePath');
      return;
    }
    await file.writeAsString(content);
    if (!touched.contains(relativePath)) touched.add(relativePath);
    logger.detail('Ensured auth redirect in $relativePath');
  }

  /// Removes GoRouter auth redirect (and unused guards import) after `remove auth`.
  Future<void> _stripGoRouterAuthRedirect(String relativePath) async {
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) return;
    var content = await file.readAsString();
    final before = content;

    content = content.replaceAll(
      RegExp(
        r'\n\s*redirect:\s*\(context,\s*state\)\s*async\s*\{[\s\S]*?\n\s*\},',
      ),
      '',
    );
    if (!content.contains('RouteGuards')) {
      content = DartImportMerger.removeImports(content, [
        'route_guards.dart',
        'package:${config.packageName}/app/router/route_guards.dart',
      ]);
      content = content.replaceAll(
        RegExp(r"^import 'route_guards\.dart';\s*\n", multiLine: true),
        '',
      );
    }

    if (content == before) return;
    if (dryRun) {
      logger.detail('Would strip auth redirect from $relativePath');
      if (!touched.contains(relativePath)) touched.add(relativePath);
      return;
    }
    await file.writeAsString(content);
    if (!touched.contains(relativePath)) touched.add(relativePath);
    logger.detail('Stripped auth redirect from $relativePath');
  }

  /// Removes imports under `/features/<name>/` when [name] is no longer configured.
  Future<void> _pruneStaleFeatureImports(String relativePath) async {
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final stale = <String>[];
    for (final uri in DartImportMerger.readImports(content)) {
      final match = RegExp(r'/features/([a-z0-9_]+)/').firstMatch(uri);
      if (match == null) continue;
      final feature = match.group(1)!;
      if (!config.features.contains(feature)) stale.add(uri);
    }
    if (stale.isEmpty) return;

    final next = DartImportMerger.removeImports(content, stale);
    if (next == content) return;
    if (dryRun) {
      logger.detail('Would prune ${stale.length} import(s) in $relativePath');
      if (!touched.contains(relativePath)) touched.add(relativePath);
      return;
    }
    await file.writeAsString(next);
    if (!touched.contains(relativePath)) touched.add(relativePath);
    logger.detail('Pruned stale feature imports in $relativePath');
  }

  /// Ensures GetX feature bindings exist whenever routing is GetX.
  Future<void> _ensureGetxBindings() async {
    if (config.routing != Routing.getx) return;

    for (final f in config.features) {
      final relative = 'lib/features/$f/bindings/${f}_binding.dart';
      final file = File(p.join(root, relative));
      if (await file.exists()) continue;

      final pascal = StackPaths.pascal(f);
      final pkg = config.packageName ?? 'app';
      late final String importLine;
      late final String registerLine;

      switch (config.stateManagement) {
        case StateManagement.bloc:
          importLine =
              "import 'package:$pkg/features/$f/presentation/bloc/${f}_bloc.dart';";
          registerLine =
              '    Get.lazyPut<${pascal}Bloc>(${pascal}Bloc.new);';
        case StateManagement.cubit:
          importLine =
              "import 'package:$pkg/features/$f/presentation/cubit/${f}_cubit.dart';";
          registerLine =
              '    Get.lazyPut<${pascal}Cubit>(${pascal}Cubit.new);';
        case StateManagement.rxdart:
        case StateManagement.getx:
          importLine =
              "import 'package:$pkg/features/$f/presentation/controllers/${f}_controller.dart';";
          registerLine =
              '    Get.lazyPut<${pascal}Controller>(${pascal}Controller.new);';
        case StateManagement.riverpod:
        case StateManagement.provider:
          importLine = '';
          registerLine =
              '    // ${config.stateManagement.yaml} owns feature state; '
              'binding satisfies GetPage wiring.';
      }

      final content = '''
import 'package:get/get.dart';
${importLine.isEmpty ? '' : '\n$importLine\n'}
class ${pascal}Binding extends Bindings {
  @override
  void dependencies() {
$registerLine
  }
}
''';

      if (dryRun) {
        logger.detail('Would create $relative');
        if (!touched.contains(relative)) touched.add(relative);
        continue;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      if (!touched.contains(relative)) touched.add(relative);
      logger.detail('Ensured $relative');
    }
  }

  Future<void> _ensureRouteGuards() async {
    const path = 'lib/app/router/route_guards.dart';
    final guardsGenerated = RouterTemplates(config).generate()[path];
    if (guardsGenerated == null) return;
    final guardsFile = File(p.join(root, path));
    final existing =
        await guardsFile.exists() ? await guardsFile.readAsString() : null;
    if (existing != null &&
        existing.contains('SessionService') &&
        existing.contains('hasSession')) {
      return;
    }
    if (dryRun) {
      logger.detail('Would ensure $path');
      if (!touched.contains(path)) touched.add(path);
      return;
    }
    await guardsFile.parent.create(recursive: true);
    await guardsFile.writeAsString(guardsGenerated);
    if (!touched.contains(path)) touched.add(path);
    logger.detail('Ensured $path');
  }

  String _routerRoutesBody() {
    if (config.routing == Routing.getx) {
      final pages = StringBuffer();
      for (final f in config.features) {
        final pascal = StackPaths.pascal(f);
        pages.writeln('''
      GetPage(
        name: AppRoutes.$f,
        page: ${pascal}Page.new,
        binding: ${pascal}Binding(),
      ),''');
      }
      return pages.toString();
    }
    if (config.routing == Routing.autoRoute) {
      final routes = StringBuffer();
      for (final f in config.features) {
        final pascal = StackPaths.pascal(f);
        routes.writeln(
          '        AutoRoute(page: ${pascal}Route.page, path: AppRoutes.$f),',
        );
      }
      return routes.toString();
    }
    // go_router
    final routes = StringBuffer();
    for (final f in config.features) {
      final pascal = StackPaths.pascal(f);
      routes.writeln('''
      GoRoute(
        path: AppRoutes.$f,
        name: '$f',
        builder: (context, state) => const ${pascal}Page(),
      ),''');
    }
    return routes.toString();
  }

  Future<void> _syncDi() async {
    if (config.di == DiType.injectable || config.di == DiType.getx) {
      // Injectable uses codegen; GetX uses bindings — skip feature DI region.
      return;
    }
    const path = 'lib/core/di/injection.dart';
    final generated = CoreTemplates(config).generate()[path];
    if (generated == null) return;

    final file = File(p.join(root, path));
    final exists = await file.exists();
    final existing = exists ? await file.readAsString() : null;

    var next = merger.mergeGeneratedFile(
      existing: existing,
      fullGenerated: generated,
      regionIds: const ['core', 'features'],
    );

    // Drop feature imports that are no longer part of the generated DI file.
    final keep = DartImportMerger.readImports(generated);
    final current = DartImportMerger.readImports(next);
    final stale = current.where((uri) {
      if (!uri.contains('/features/')) return false;
      return !keep.contains(uri);
    });
    if (stale.isNotEmpty) {
      next = DartImportMerger.removeImports(next, stale);
    }

    if (existing == next) return;
    touched.add(path);
    if (dryRun) {
      logger.detail('Would sync $path');
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(next);
    logger.detail('Synced $path');
  }

  Future<void> _writeMerged(
    String relativePath, {
    required String seed,
    required String regionId,
    required String regionBody,
    required List<String> regionIds,
    Iterable<String> imports = const [],
  }) async {
    final file = File(p.join(root, relativePath));
    final exists = await file.exists();
    final existing = exists ? await file.readAsString() : null;

    late final String next;
    if (existing == null) {
      next = seed;
    } else if (regionIds.every((id) => !RegionMerger.hasRegion(existing, id))) {
      // Legacy file without markers — adopt seeded template with markers.
      next = merger.merge(
        existing: _injectRegionsIntoLegacy(existing, seed, regionIds),
        regionId: regionId,
        regionBody: regionBody,
        imports: imports,
      );
    } else {
      next = merger.merge(
        existing: existing,
        regionId: regionId,
        regionBody: regionBody,
        imports: imports,
      );
    }

    if (existing == next) return;
    touched.add(relativePath);
    if (dryRun) {
      logger.detail('Would sync $relativePath');
      return;
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(next);
    logger.detail('Synced $relativePath');
  }

  /// Best-effort: if legacy file lacks markers, replace with seeded template
  /// that includes markers (user should review). Prefer seed when structure
  /// matches Stackchain output.
  String _injectRegionsIntoLegacy(
    String existing,
    String seed,
    List<String> regionIds,
  ) {
    final looksLikeStackchain = existing.contains('AppRouter') ||
        existing.contains('configureDependencies') ||
        existing.contains('AppRoutes');
    if (looksLikeStackchain) {
      // Use seed (with markers) as base — sync will fill regions.
      return seed;
    }
    return merger.mergeGeneratedFile(
      existing: existing,
      fullGenerated: seed,
      regionIds: regionIds,
    );
  }
}
