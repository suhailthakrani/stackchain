import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../architecture/architecture_registry.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../quality/quality_gate.dart';
import '../sync/project_sync.dart';
import '../templates/features/feature_templates.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../utils/pubspec_merger.dart';
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
    this.packageVersion = '1.1.1',
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

  /// Applies [patch] onto stackchain.yaml + regenerates presentation + sync.
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

    // Regenerate feature presentation/state for each feature.
    final registry = ArchitectureRegistry();
    final writer = FileWriter(
      root: root,
      dryRun: dryRun,
      overwrite: overwritePresentation,
    );
    var fileCount = 0;
    for (final feature in after.features) {
      final single = after.copyWith(features: [feature]);
      final files = FeatureTemplates(single, registry: registry).generate();
      for (final entry in files.entries) {
        // Only regenerate presentation / state / bindings on migrate.
        if (!_isPresentationPath(entry.key, after)) continue;
        await writer.write(entry.key, entry.value);
        fileCount++;
      }
    }
    logger.success('Migrated $fileCount presentation file(s)');

    final removedFiles =
        cleanup ? await _removeStaleFiles(before, after, registry) : <String>[];
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

  /// Files the old stack generated that the new stack no longer owns.
  ///
  /// Derived by diffing the generated file sets, so hand-written files are
  /// never candidates — only scaffolding Stackchain itself produced.
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
    }

    final stale = <String>{};
    for (final feature in before.features) {
      final generated = FeatureTemplates(
        before.copyWith(features: [feature]),
        registry: registry,
      ).generate().keys;
      for (final path in generated) {
        if (!_isPresentationPath(path, before)) continue;
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

  /// Walks up from [start] deleting empty directories, stopping at `lib/`.
  Future<void> _pruneEmptyDirs(String start) async {
    final libRoot = p.normalize(p.join(root, 'lib'));
    var current = p.normalize(start);
    while (p.isWithin(libRoot, current)) {
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
    // MVVM/MVC pages
    if (path.endsWith('_page.dart')) return true;
    return false;
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
      // Re-parse via synthetic yaml for preset expansion.
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
