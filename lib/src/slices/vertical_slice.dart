import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';
import 'package:yaml/yaml.dart';

import '../architecture/architecture_registry.dart';
import '../merge/preserving_file_writer.dart';
import '../migrate/stack_lock.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../quality/quality_gate.dart';
import '../sync/project_sync.dart';
import '../templates/features/feature_templates.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../version.dart';
import 'slice_recipes.dart';

/// Adds a feature as a full vertical slice: files + router + DI + tests.
class VerticalSliceGenerator {
  VerticalSliceGenerator({
    required this.root,
    Logger? logger,
    this.overwrite = false,
    this.dryRun = false,
    this.skipAnalyze = false,
    this.packageVersion = stackchainPackageVersion,
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool overwrite;
  final bool dryRun;
  final bool skipAnalyze;
  final String packageVersion;

  Future<QualityReport> add(String rawName) async {
    final name = ReCase(rawName).snakeCase;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw FormatException('Invalid feature name "$rawName"');
    }

    final context = await ProjectContext.detect(root);
    var config = await _loadConfig(context.packageName);

    if (config.features.contains(name)) {
      logger.warn(
        'Feature "$name" already listed — regenerating vertical slice.',
      );
    } else {
      config = config.copyWith(features: [...config.features, name]);
      if (!dryRun) await _appendFeatureToYaml(name);
      logger.success('Added "$name" to stackchain.yaml');
    }

    final registry = ArchitectureRegistry();
    final layout = registry.layoutFor(name, config);
    final writer = FileWriter(
      root: root,
      overwrite: overwrite,
      dryRun: dryRun,
    );
    final preserving = PreservingFileWriter(writer: writer, logger: logger);

    for (final dir in layout.directories) {
      await writer.ensureDir(dir);
    }

    final single = config.copyWith(features: [name]);
    final files = <String, String>{
      ...FeatureTemplates(single, registry: registry).generate(),
      ...SliceRecipes.extras(name, config),
    };

    for (final entry in files.entries) {
      if (entry.key.endsWith('_custom_test.dart')) {
        await preserving.writeIfAbsent(entry.key, entry.value);
      } else {
        await preserving.writeOwned(
          relativePath: entry.key,
          fullGenerated: entry.value,
        );
      }
    }
    logger.success(
      'Generated vertical slice "$name" (${files.length} files)',
    );

    // Wire the whole stack — no manual init --overwrite needed.
    final sync = ProjectSync(
      root: root,
      config: config,
      logger: logger,
      dryRun: dryRun,
    );
    await sync.run();

    if (!dryRun) {
      await StackLock.write(root, config, packageVersion: packageVersion);
    }

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();

    if (!gate.passed) {
      throw StateError(
        'Vertical slice "$name" generated but quality gate failed.',
      );
    }
    return gate;
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

  Future<void> _appendFeatureToYaml(String name) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) {
      await file.writeAsString('''
stackchain:
  features:
    - home
    - $name
''');
      return;
    }

    final content = await file.readAsString();
    final doc = loadYaml(content);
    final yamlRoot =
        doc is YamlMap ? (doc['stackchain'] ?? doc['flutter_starter']) : null;
    if (yamlRoot is YamlMap) {
      final features = yamlRoot['features'];
      if (features is YamlList) {
        final existing = features.map((e) => '$e').toList();
        if (existing.contains(name)) return;
      }
    }

    if (content.contains(RegExp(r'features:\s*$', multiLine: true)) ||
        content.contains(RegExp(r'features:\s*\n'))) {
      final updated = content.replaceFirstMapped(
        RegExp(r'(features:\s*\n(?:\s*-\s*.+\n)*)'),
        (m) => '${m[1]}    - $name\n',
      );
      if (updated != content) {
        await file.writeAsString(updated);
        return;
      }
    }

    await file.writeAsString('$content\n  features:\n    - $name\n');
  }
}
