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
    this.packageVersion = '1.1.0',
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool dryRun;
  final bool overwritePresentation;
  final bool skipAnalyze;
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

    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    final existing = await pubspecFile.readAsString();
    final merged = PubspecMerger.merge(existing: existing, config: after);
    if (merged != existing && !dryRun) {
      await pubspecFile.writeAsString(merged);
      logger.success('Updated pubspec.yaml for new stack');
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
    );
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
  });

  final StackchainConfig before;
  final StackchainConfig after;
  final QualityReport quality;
}
