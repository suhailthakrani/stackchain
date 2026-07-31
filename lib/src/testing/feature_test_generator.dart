import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';

import '../merge/preserving_file_writer.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../quality/quality_gate.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../utils/pubspec_merger.dart';
import 'feature_test_templates.dart';
import 'test_types.dart';

/// Result of `stackchain test`.
class FeatureTestReport {
  FeatureTestReport({
    required this.features,
    required this.types,
    required this.created,
    required this.updated,
    required this.skipped,
    required this.preserved,
    required this.quality,
  });

  final List<String> features;
  final Set<TestType> types;
  final List<String> created;
  final List<String> updated;
  final List<String> skipped;
  final List<String> preserved;
  final QualityReport quality;
}

/// Generates unit / widget / integration tests for one or more features.
class FeatureTestGenerator {
  FeatureTestGenerator({
    required this.root,
    Logger? logger,
    this.overwrite = false,
    this.dryRun = false,
    this.skipAnalyze = false,
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool overwrite;
  final bool dryRun;
  final bool skipAnalyze;

  Future<FeatureTestReport> run({
    String? featureName,
    bool all = false,
    Set<TestType> types = TestType.all,
  }) async {
    if (!all && (featureName == null || featureName.trim().isEmpty)) {
      throw const FormatException(
        'Pass a feature name or --all.\n'
        'Examples: dart run stackchain test auth\n'
        '          dart run stackchain test --all',
      );
    }

    final context = await ProjectContext.detect(root);
    final config = await _loadConfig(context.packageName);

    final targets = <String>[];
    if (all) {
      if (config.features.isEmpty) {
        throw StateError('No features in stackchain.yaml');
      }
      targets.addAll(config.features);
    } else {
      final name = ReCase(featureName!.trim()).snakeCase;
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
        throw FormatException('Invalid feature name "$featureName"');
      }
      if (!config.features.contains(name)) {
        throw StateError(
          'Feature "$name" is not in stackchain.yaml.\n'
          'Add it first: dart run stackchain feature $name',
        );
      }
      final featureDir = Directory(p.join(root, 'lib', 'features', name));
      if (!await featureDir.exists()) {
        throw StateError(
          'Feature "$name" is listed but lib/features/$name is missing.\n'
          'Regenerate with: dart run stackchain feature $name',
        );
      }
      targets.add(name);
    }

    final writer = FileWriter(
      root: root,
      overwrite: overwrite,
      dryRun: dryRun,
    );
    final preserving = PreservingFileWriter(writer: writer, logger: logger);
    final templates = FeatureTestTemplates(config);

    for (final feature in targets) {
      final files = templates.generate(feature, types: types);
      for (final entry in files.entries) {
        if (entry.key.endsWith('_custom_test.dart')) {
          await preserving.writeIfAbsent(entry.key, entry.value);
        } else {
          await preserving.writeScaffold(
            relativePath: entry.key,
            fullGenerated: entry.value,
          );
        }
      }
      logger.success(
        '${dryRun ? 'Would generate' : 'Generated'} '
        '${types.map((t) => t.name).join('+')} tests for "$feature" '
        '(${files.length} file(s); custom tests are never overwritten)',
      );
      for (final path in files.keys) {
        logger.detail('  → $path');
      }
    }

    if (preserving.preserved.isNotEmpty) {
      logger.info(
        'Preserved ${preserving.preserved.length} existing custom/scaffold '
        'file(s)',
      );
    }
    if (preserving.backedUp.isNotEmpty) {
      logger.warn(
        'Backed up ${preserving.backedUp.length} unmarked customized '
        'file(s) as *.stackchain.bak',
      );
    }

    if (types.contains(TestType.integration) && !dryRun) {
      await _ensureIntegrationTestDep();
    }

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();

    return FeatureTestReport(
      features: targets,
      types: types,
      created: List.of(writer.created),
      updated: List.of(writer.updated),
      skipped: List.of(writer.skipped),
      preserved: List.of(preserving.preserved),
      quality: gate,
    );
  }

  Future<StackchainConfig> _loadConfig(String packageName) async {
    final configFile = File(p.join(root, 'stackchain.yaml'));
    if (!await configFile.exists()) {
      return StackchainConfig.defaults(packageName: packageName);
    }
    return YamlParser.parse(
      await configFile.readAsString(),
      packageName: packageName,
    );
  }

  Future<void> _ensureIntegrationTestDep() async {
    final pubspec = File(p.join(root, 'pubspec.yaml'));
    if (!await pubspec.exists()) return;
    final existing = await pubspec.readAsString();
    final updated = PubspecMerger.ensureSdkDevDependency(
      existing,
      'integration_test',
    );
    if (updated != existing) {
      await pubspec.writeAsString(updated);
      logger.success('Added integration_test (sdk: flutter) to pubspec.yaml');
    }
  }
}
