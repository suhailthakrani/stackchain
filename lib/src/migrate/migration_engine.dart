import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../architecture/architecture_registry.dart';
import '../merge/preserving_file_writer.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../quality/quality_gate.dart';
import '../slices/slice_recipes.dart';
import '../sync/project_sync.dart';
import '../templates/app/app_templates.dart';
import '../templates/app/router_templates.dart';
import '../templates/core/core_templates.dart';
import '../templates/features/feature_templates.dart';
import '../testing/feature_test_templates.dart';
import '../testing/test_types.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../utils/pubspec_merger.dart';
import '../version.dart';
import 'stack_lock.dart';

/// Intentional stack evolution (e.g. bloc → cubit, go_router stays).
class MigrationEngine {
  MigrationEngine({
    required this.root,
    Logger? logger,
    this.dryRun = false,
    this.overwritePresentation = true,
    this.skipAnalyze = false,
    this.cleanup = true,
    this.packageVersion = stackchainPackageVersion,
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool dryRun;
  final bool overwritePresentation;
  final bool skipAnalyze;

  /// Delete files and packages the previous stack needed and the new one
  /// does not. Disable with `--keep-old` to review leftovers manually.
  final bool cleanup;
  final String packageVersion;

  /// Applies [patch] onto stackchain.yaml + regenerates stack shell + sync.
  Future<MigrationReport> run(MigrationPatch patch) async {
    final context = await ProjectContext.detect(root);
    final before = await _loadConfig(context.packageName);
    final after = patch.apply(before);

    logger.banner('stackchain migrate');
    logger.step(
      '${before.stateManagement.yaml}/${before.routing.yaml}/${before.di.yaml}'
      ' → '
      '${after.stateManagement.yaml}/${after.routing.yaml}/${after.di.yaml}',
    );

    if (!dryRun) {
      await _rewriteYaml(after);
      logger.success('Updated stackchain.yaml');
    }

    final registry = ArchitectureRegistry();
    final writer = FileWriter(
      root: root,
      dryRun: dryRun,
      overwrite: overwritePresentation,
    );
    final preserving = PreservingFileWriter(writer: writer, logger: logger);

    // App shell always follows the target stack (bootstrap ProviderScope, etc.).
    final shellCount = await _refreshStackShell(before, after, writer);
    if (shellCount > 0) {
      logger.success(
        '${dryRun ? "Would refresh" : "Refreshed"} $shellCount '
        'app shell file(s)',
      );
    }

    // Regenerate feature presentation/state (and full tree on architecture change).
    // Owned regions merge; `custom` regions are preserved / ported across stacks.
    var fileCount = 0;
    final architectureChanged = before.architecture != after.architecture;
    for (final feature in after.features) {
      final beforeFiles = FeatureTemplates(
        before.copyWith(features: [feature]),
        registry: registry,
      ).generate();
      final afterFiles = FeatureTemplates(
        after.copyWith(features: [feature]),
        registry: registry,
      ).generate();

      final previousController = _stateControllerPath(beforeFiles.keys);
      final nextController = _stateControllerPath(afterFiles.keys);

      for (final entry in afterFiles.entries) {
        if (architectureChanged) {
          // Full feature tree rewrite on architecture change.
        } else if (!_isStateRefreshPath(entry.key)) {
          continue;
        }

        String? previousPath;
        if (beforeFiles.containsKey(entry.key)) {
          previousPath = entry.key;
        } else if (entry.key == nextController) {
          previousPath = previousController;
        } else if (entry.key.endsWith('_page.dart')) {
          final pages = beforeFiles.keys
              .where((k) => k.endsWith('_page.dart'))
              .toList();
          previousPath = pages.isEmpty ? null : pages.first;
        }

        await preserving.writeOwned(
          relativePath: entry.key,
          fullGenerated: entry.value,
          previousPath: previousPath,
        );
        fileCount++;
      }
    }
    logger.success(
      'Migrated $fileCount '
      '${architectureChanged ? "feature" : "presentation"} file(s)',
    );
    if (preserving.preserved.isNotEmpty) {
      logger.success(
        'Preserved custom regions in ${preserving.preserved.length} file(s)',
      );
    }
    if (preserving.backedUp.isNotEmpty) {
      logger.warn(
        'Legacy files without markers backed up '
        '(${preserving.backedUp.length}): *.stackchain.bak',
      );
    }

    // State-management-specific feature tests must match the new stack.
    final testCount = await _refreshFeatureTests(before, after, preserving);
    if (testCount > 0) {
      logger.success(
        '${dryRun ? "Would refresh" : "Refreshed"} $testCount test file(s)',
      );
    }

    final removedFiles = cleanup
        ? await _removeStaleFiles(before, after, registry)
        : <String>[];
    if (removedFiles.isNotEmpty) {
      logger.success(
        '${dryRun ? "Would remove" : "Removed"} ${removedFiles.length} '
        'stale file(s) from the old stack',
      );
      for (final path in removedFiles) {
        logger.detail('  - $path');
      }
    }

    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    final existing = await pubspecFile.readAsString();
    var merged = PubspecMerger.merge(existing: existing, config: after);

    final removedPackages = <String>[];
    if (cleanup) {
      final obsolete = PubspecMerger.obsoletePackages(
        before: before,
        after: after,
      );
      removedPackages.addAll(
        obsolete.where((name) => _declaresPackage(existing, name)),
      );
      removedPackages.sort();
      if (removedPackages.isNotEmpty) {
        merged = PubspecMerger.prune(existing: merged, packages: obsolete);
      }
    }

    if (merged != existing && !dryRun) {
      await pubspecFile.writeAsString(merged);
      logger.success('Updated pubspec.yaml for new stack');
    }
    if (removedPackages.isNotEmpty) {
      logger.success(
        '${dryRun ? "Would drop" : "Dropped"} unused package(s): '
        '${removedPackages.join(", ")}',
      );
    }

    final sync = ProjectSync(
      root: root,
      config: after,
      logger: logger,
      dryRun: dryRun,
    );
    await sync.run();

    if (!dryRun) {
      await StackLock.write(root, after, packageVersion: packageVersion);
    }

    final gate = await QualityGate(
      root: root,
      config: after,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();

    return MigrationReport(
      before: before,
      after: after,
      quality: gate,
      removedFiles: removedFiles,
      removedPackages: removedPackages,
    );
  }

  /// Bootstraps, mains, app widget for the new stack.
  ///
  /// Router / DI seeds are refreshed only when routing or DI itself changes
  /// (full template swap). State-only migrates leave those files to
  /// [ProjectSync], which updates managed regions and preserves hand-written
  /// code outside markers.
  Future<int> _refreshStackShell(
    StackchainConfig before,
    StackchainConfig after,
    FileWriter writer,
  ) async {
    var count = 0;
    final appFiles = AppTemplates(after).generate();

    for (final path in const [
      'lib/bootstrap.dart',
      'lib/main.dart',
      'lib/app/app.dart',
      'lib/main_dev.dart',
      'lib/main_staging.dart',
      'lib/main_prod.dart',
    ]) {
      final next = appFiles[path];
      if (next == null) continue;
      final file = File(p.join(root, path));
      final isRequired = path == 'lib/bootstrap.dart' ||
          path == 'lib/main.dart' ||
          path == 'lib/app/app.dart';
      if (!isRequired && !await file.exists()) continue;
      await writer.write(path, next);
      count++;
    }

    final routingChanged = before.routing != after.routing;
    final diChanged = before.di != after.di;
    final archChanged = before.architecture != after.architecture;

    // Full router rewrite only when the routing engine (or architecture) changes.
    // State-only migrates rely on ProjectSync to refresh <stackchain:routes>.
    if (routingChanged || archChanged) {
      for (final entry in RouterTemplates(after).generate().entries) {
        await writer.write(entry.key, entry.value);
        count++;
      }
    }

    // Full DI seed rewrite only when DI type (or architecture) changes.
    if (diChanged || archChanged) {
      final di = CoreTemplates(after).generate()['lib/core/di/injection.dart'];
      if (di != null) {
        await writer.write('lib/core/di/injection.dart', di);
        count++;
      }
    }

    return count;
  }

  Future<int> _refreshFeatureTests(
    StackchainConfig before,
    StackchainConfig after,
    PreservingFileWriter preserving,
  ) async {
    if (before.stateManagement == after.stateManagement &&
        before.architecture == after.architecture) {
      return 0;
    }

    var count = 0;
    final templates = FeatureTestTemplates(after);
    for (final feature in after.features) {
      final unit = templates.generate(
        feature,
        types: const {TestType.unit},
      );
      for (final entry in unit.entries) {
        if (entry.key.endsWith('_custom_test.dart')) {
          await preserving.writeIfAbsent(entry.key, entry.value);
        } else {
          await preserving.writeScaffold(
            relativePath: entry.key,
            fullGenerated: entry.value,
          );
        }
        count++;
      }

      final types = <TestType>{};
      if (File(p.join(root, 'test/features/${feature}_page_test.dart'))
          .existsSync()) {
        types.add(TestType.widget);
      }
      if (File(p.join(root, 'integration_test/${feature}_flow_test.dart'))
          .existsSync()) {
        types.add(TestType.integration);
      }
      if (types.isEmpty) continue;
      final extras = templates.generate(feature, types: types);
      for (final entry in extras.entries) {
        if (entry.key.endsWith('_custom_test.dart')) {
          await preserving.writeIfAbsent(entry.key, entry.value);
        } else {
          await preserving.writeScaffold(
            relativePath: entry.key,
            fullGenerated: entry.value,
          );
        }
        count++;
      }
    }
    return count;
  }

  /// Primary state controller path for a feature template set.
  String? _stateControllerPath(Iterable<String> paths) {
    final ranked = paths.where((k) {
      return k.endsWith('_bloc.dart') ||
          k.endsWith('_cubit.dart') ||
          k.endsWith('_controller.dart') ||
          k.endsWith('_provider.dart') ||
          k.endsWith('_view_model.dart') ||
          k.endsWith('_viewmodel.dart');
    }).toList();
    if (ranked.isEmpty) return null;
    return ranked.first;
  }

  /// Files the old stack generated that the new stack no longer owns.
  Future<List<String>> _removeStaleFiles(
    StackchainConfig before,
    StackchainConfig after,
    ArchitectureRegistry registry,
  ) async {
    final keep = <String>{};
    for (final feature in after.features) {
      keep.addAll(
        FeatureTemplates(
          after.copyWith(features: [feature]),
          registry: registry,
        ).generate().keys,
      );
      keep.addAll(SliceRecipes.extras(feature, after).keys);
    }

    final stale = <String>{};
    for (final feature in before.features) {
      final generated = {
        ...FeatureTemplates(
          before.copyWith(features: [feature]),
          registry: registry,
        ).generate().keys,
        ...SliceRecipes.extras(feature, before).keys,
      };
      for (final path in generated) {
        final isPresentation = _isPresentationPath(path, before);
        final isTest = path.startsWith('test/');
        final architectureChanged = before.architecture != after.architecture;
        if (!architectureChanged && !isPresentation && !isTest) continue;
        if (keep.contains(path)) continue;
        stale.add(path);
      }
    }

    final removed = <String>[];
    final parents = <String>{};
    for (final rel in stale.toList()..sort()) {
      final file = File(p.join(root, rel));
      if (!file.existsSync()) continue;
      removed.add(rel);
      parents.add(p.dirname(file.path));
      if (!dryRun) await file.delete();
    }

    if (!dryRun) {
      for (final dir in parents) {
        await _pruneEmptyDirs(dir);
      }
    }
    return removed;
  }

  Future<void> _pruneEmptyDirs(String start) async {
    final libRoot = p.normalize(p.join(root, 'lib'));
    final testRoot = p.normalize(p.join(root, 'test'));
    var current = p.normalize(start);
    while (p.isWithin(libRoot, current) || p.isWithin(testRoot, current)) {
      final dir = Directory(current);
      if (!dir.existsSync()) {
        current = p.dirname(current);
        continue;
      }
      if (dir.listSync().isNotEmpty) return;
      await dir.delete();
      current = p.dirname(current);
    }
  }

  bool _declaresPackage(String pubspec, String name) {
    return RegExp(
      '^\\s+${RegExp.escape(name)}:',
      multiLine: true,
    ).hasMatch(pubspec);
  }

  bool _isPresentationPath(String path, StackchainConfig config) {
    if (path.contains('/presentation/') ||
        path.contains('/viewmodels/') ||
        path.contains('/views/') ||
        path.contains('/controllers/') ||
        path.contains('/bindings/') ||
        path.contains('/providers/')) {
      return true;
    }
    if (path.endsWith('_page.dart')) return true;
    return false;
  }

  /// Paths refreshed on state-management migrate (not static widgets/headers).
  bool _isStateRefreshPath(String path) {
    if (path.endsWith('_page.dart')) return true;
    if (path.contains('/bindings/')) return true;
    return path.endsWith('_bloc.dart') ||
        path.endsWith('_cubit.dart') ||
        path.endsWith('_event.dart') ||
        path.endsWith('_state.dart') ||
        path.endsWith('_controller.dart') ||
        path.endsWith('_provider.dart') ||
        path.endsWith('_view_model.dart') ||
        path.endsWith('_viewmodel.dart');
  }

  Future<void> _rewriteYaml(StackchainConfig config) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    final storage = config.storage.map((e) => e.yaml).toList();
    final storageYaml = storage.length == 1
        ? storage.first
        : '[${storage.join(', ')}]';

    String? preservePreset;
    if (await file.exists()) {
      final raw = loadYaml(await file.readAsString());
      if (raw is YamlMap) {
        final rootMap = raw['stackchain'] ?? raw['flutter_starter'];
        if (rootMap is YamlMap && rootMap['preset'] != null) {
          preservePreset = '${rootMap['preset']}';
        }
      }
    }

    final features = config.features.map((f) => '    - $f').join('\n');
    final presetLine =
        preservePreset == null ? '' : '  preset: $preservePreset\n';

    await file.writeAsString('''
# Updated by stackchain migrate
stackchain:
$presetLine  architecture: ${config.architecture.yaml}
  state_management: ${config.stateManagement.yaml}
  routing: ${config.routing.yaml}
  di: ${config.di.yaml}
  network: ${config.network.yaml}
  storage: $storageYaml
  localization: ${config.modules.localization}
  firebase: ${config.modules.firebase}
  features:
$features
''');
  }

  Future<StackchainConfig> _loadConfig(String packageName) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) {
      return StackchainConfig.defaults(packageName: packageName);
    }
    return YamlParser.parse(
      await file.readAsString(),
      packageName: packageName,
    );
  }
}

/// Declarative migration patch from CLI flags.
class MigrationPatch {
  const MigrationPatch({
    this.architecture,
    this.stateManagement,
    this.routing,
    this.di,
    this.network,
    this.preset,
  });

  final Architecture? architecture;
  final StateManagement? stateManagement;
  final Routing? routing;
  final DiType? di;
  final NetworkClient? network;
  final String? preset;

  StackchainConfig apply(StackchainConfig current) {
    var next = current;
    if (preset != null) {
      final yaml = '''
stackchain:
  preset: $preset
  features:
${current.features.map((f) => '    - $f').join('\n')}
''';
      next = YamlParser.parse(yaml, packageName: current.packageName);
    }
    return next.copyWith(
      architecture: architecture,
      stateManagement: stateManagement,
      routing: routing,
      di: di,
      network: network,
    );
  }

  bool get isEmpty =>
      architecture == null &&
      stateManagement == null &&
      routing == null &&
      di == null &&
      network == null &&
      (preset == null || preset!.isEmpty);
}

class MigrationReport {
  MigrationReport({
    required this.before,
    required this.after,
    required this.quality,
    this.removedFiles = const [],
    this.removedPackages = const [],
  });

  final StackchainConfig before;
  final StackchainConfig after;
  final QualityReport quality;
  final List<String> removedFiles;
  final List<String> removedPackages;
}
