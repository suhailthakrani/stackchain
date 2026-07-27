import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';

import '../architecture/architecture_registry.dart';
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

/// Removes a feature that was added via `feature` / `add`.
///
/// Deletes the feature tree + tests, drops it from `stackchain.yaml`, then
/// syncs router/DI so managed regions and imports no longer reference it.
class FeatureRemover {
  FeatureRemover({
    required this.root,
    Logger? logger,
    this.dryRun = false,
    this.skipAnalyze = false,
    this.packageVersion = stackchainPackageVersion,
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool dryRun;
  final bool skipAnalyze;
  final String packageVersion;

  Future<FeatureRemoveReport> remove(String rawName) async {
    final name = ReCase(rawName).snakeCase;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw FormatException('Invalid feature name "$rawName"');
    }

    final context = await ProjectContext.detect(root);
    final before = await _loadConfig(context.packageName);

    final listed = before.features.contains(name);
    final featureDir = Directory(p.join(root, 'lib', 'features', name));
    final dirExists = await featureDir.exists();

    if (!listed && !dirExists) {
      throw StateError(
        'Feature "$name" is not in stackchain.yaml and '
        'lib/features/$name/ does not exist.',
      );
    }

    if (listed && before.features.length <= 1) {
      throw StateError(
        'Cannot remove "$name" — it is the only feature. '
        'Add another feature first.',
      );
    }

    logger.banner('stackchain remove');
    logger.step('Removing feature "$name"');

    final after = before.copyWith(
      features: before.features.where((f) => f != name).toList(),
    );

    if (listed && !dryRun) {
      await _removeFeatureFromYaml(name);
      logger.success('Removed "$name" from stackchain.yaml');
    } else if (listed && dryRun) {
      logger.success('Would remove "$name" from stackchain.yaml');
    }

    final deleted = await _deleteFeatureArtifacts(name, before);
    if (deleted.isNotEmpty) {
      logger.success(
        '${dryRun ? "Would delete" : "Deleted"} ${deleted.length} '
        'file(s) / folder(s)',
      );
      for (final path in deleted) {
        logger.detail('  - $path');
      }
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

    return FeatureRemoveReport(
      name: name,
      deletedPaths: deleted,
      quality: gate,
    );
  }

  /// Deletes the feature directory and any Stackchain-owned test / recipe files.
  Future<List<String>> _deleteFeatureArtifacts(
    String name,
    StackchainConfig config,
  ) async {
    final deleted = <String>[];
    final registry = ArchitectureRegistry();
    final owned = <String>{
      ...FeatureTemplates(
        config.copyWith(features: [name]),
        registry: registry,
      ).generate().keys,
      ...SliceRecipes.extras(name, config).keys,
    };

    for (final rel in owned.toList()..sort()) {
      final file = File(p.join(root, rel));
      if (!await file.exists()) continue;
      deleted.add(rel);
      if (!dryRun) await file.delete();
    }

    // Catch recipe/test variants and any leftover generated files under the
    // feature root that templates no longer list (older scaffolds).
    final testDir = Directory(p.join(root, 'test', 'features'));
    if (await testDir.exists()) {
      for (final entity in testDir.listSync()) {
        if (entity is! File) continue;
        final base = p.basename(entity.path);
        if (base == '${name}_test.dart' ||
            (base.startsWith('${name}_') && base.endsWith('_test.dart'))) {
          final rel = p.relative(entity.path, from: root);
          if (!deleted.contains(rel)) deleted.add(rel);
          if (!dryRun) await entity.delete();
        }
      }
    }

    final featureRoot = Directory(p.join(root, 'lib', 'features', name));
    if (await featureRoot.exists()) {
      deleted.add('lib/features/$name/');
      if (!dryRun) await featureRoot.delete(recursive: true);
    }

    return deleted;
  }

  Future<void> _removeFeatureFromYaml(String name) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    final out = <String>[];
    var inFeatures = false;

    for (final line in lines) {
      if (RegExp(r'^\s*features:\s*$').hasMatch(line)) {
        inFeatures = true;
        out.add(line);
        continue;
      }
      if (inFeatures) {
        if (RegExp(r'^\s*-\s+\S').hasMatch(line)) {
          final value = line.replaceFirst(RegExp(r'^\s*-\s+'), '').trim();
          if (value == name) continue;
          out.add(line);
          continue;
        }
        inFeatures = false;
      }
      out.add(line);
    }

    var text = out.join('\n');
    if (!text.endsWith('\n')) text = '$text\n';
    await file.writeAsString(text);
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

class FeatureRemoveReport {
  FeatureRemoveReport({
    required this.name,
    required this.deletedPaths,
    required this.quality,
  });

  final String name;
  final List<String> deletedPaths;
  final QualityReport quality;
}
