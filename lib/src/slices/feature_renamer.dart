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

/// Renames a feature across yaml, files, tests, router, and DI.
class FeatureRenamer {
  FeatureRenamer({
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

  Future<FeatureRenameReport> rename(String rawFrom, String rawTo) async {
    final from = ReCase(rawFrom).snakeCase;
    final to = ReCase(rawTo).snakeCase;

    for (final name in [from, to]) {
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
        throw FormatException('Invalid feature name "$name"');
      }
    }
    if (from == to) {
      throw FormatException('Old and new feature names are the same ("$from").');
    }

    final context = await ProjectContext.detect(root);
    final before = await _loadConfig(context.packageName);

    final listed = before.features.contains(from);
    final fromDir = Directory(p.join(root, 'lib', 'features', from));
    final toDir = Directory(p.join(root, 'lib', 'features', to));
    final fromExists = await fromDir.exists();
    final toExists = await toDir.exists();

    if (!listed && !fromExists) {
      throw StateError(
        'Feature "$from" is not in stackchain.yaml and '
        'lib/features/$from/ does not exist.',
      );
    }
    if (before.features.contains(to) || toExists) {
      throw StateError(
        'Cannot rename to "$to" — that feature already exists.',
      );
    }

    logger.banner('stackchain rename');
    logger.step('Renaming feature "$from" → "$to"');

    final afterFeatures = before.features
        .map((f) => f == from ? to : f)
        .toList(growable: false);
    final after = before.copyWith(features: afterFeatures);

    if (!dryRun) {
      await _renameInYaml(from, to);
      logger.success('Updated stackchain.yaml');
    } else {
      logger.success('Would update stackchain.yaml');
    }

    final moved = await _relocateFeature(from, to, before, after);
    logger.success(
      '${dryRun ? "Would rewrite" : "Rewrote"} ${moved.length} '
      'feature path(s)',
    );

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

    return FeatureRenameReport(
      from: from,
      to: to,
      touchedPaths: moved,
      quality: gate,
    );
  }

  Future<List<String>> _relocateFeature(
    String from,
    String to,
    StackchainConfig before,
    StackchainConfig after,
  ) async {
    final touched = <String>[];
    final registry = ArchitectureRegistry();
    final writer = FileWriter(root: root, dryRun: dryRun, overwrite: true);

    final oldOwned = <String>{
      ...FeatureTemplates(
        before.copyWith(features: [from]),
        registry: registry,
      ).generate().keys,
      ...SliceRecipes.extras(from, before).keys,
    };
    final newFiles = <String, String>{
      ...FeatureTemplates(
        after.copyWith(features: [to]),
        registry: registry,
      ).generate(),
      ...SliceRecipes.extras(to, after),
    };

    // Preserve hand-written files under the old feature tree.
    final fromRoot = Directory(p.join(root, 'lib', 'features', from));
    if (await fromRoot.exists()) {
      await for (final entity in fromRoot.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: root);
        if (oldOwned.contains(rel)) continue;
        final rewrittenRel = _rewritePath(rel, from, to);
        var content = await entity.readAsString();
        content = _rewriteContent(content, from, to);
        await writer.write(rewrittenRel, content);
        touched.add(rewrittenRel);
      }
    }

    for (final entry in newFiles.entries) {
      await writer.write(entry.key, entry.value);
      touched.add(entry.key);
    }

    // Drop old generated tests / leftover old tree.
    for (final rel in oldOwned) {
      final file = File(p.join(root, rel));
      if (await file.exists() && !dryRun) {
        await file.delete();
      }
    }
    if (await fromRoot.exists() && !dryRun) {
      await fromRoot.delete(recursive: true);
    }

    final testDir = Directory(p.join(root, 'test', 'features'));
    if (await testDir.exists()) {
      for (final entity in testDir.listSync()) {
        if (entity is! File) continue;
        final base = p.basename(entity.path);
        if (base == '${from}_test.dart' ||
            (base.startsWith('${from}_') && base.endsWith('_test.dart'))) {
          if (!dryRun) await entity.delete();
        }
      }
    }

    final oldIntegration =
        File(p.join(root, 'integration_test', '${from}_flow_test.dart'));
    if (await oldIntegration.exists() && !dryRun) {
      await oldIntegration.delete();
    }

    return touched.toSet().toList()..sort();
  }

  String _rewritePath(String path, String from, String to) {
    return path
        .replaceAll('/features/$from/', '/features/$to/')
        .replaceAll('/$from/', '/$to/')
        .replaceAll('/${from}_', '/${to}_')
        .replaceAll('${from}_', '${to}_');
  }

  String _rewriteContent(String source, String from, String to) {
    final fromPascal = ReCase(from).pascalCase;
    final toPascal = ReCase(to).pascalCase;
    return source
        .replaceAll('/features/$from/', '/features/$to/')
        .replaceAll("features/$from/", "features/$to/")
        .replaceAll(fromPascal, toPascal)
        .replaceAll('${from}_', '${to}_')
        .replaceAll("'$from'", "'$to'")
        .replaceAll('"$from"', '"$to"');
  }

  Future<void> _renameInYaml(String from, String to) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) return;

    final lines = await file.readAsLines();
    final out = <String>[];
    var inFeatures = false;
    var replaced = false;

    for (final line in lines) {
      if (RegExp(r'^\s*features:\s*$').hasMatch(line)) {
        inFeatures = true;
        out.add(line);
        continue;
      }
      if (inFeatures) {
        if (RegExp(r'^\s*-\s+\S').hasMatch(line)) {
          final value = line.replaceFirst(RegExp(r'^\s*-\s+'), '').trim();
          if (value == from && !replaced) {
            final indent = RegExp(r'^(\s*-\s+)').firstMatch(line)!.group(1)!;
            out.add('$indent$to');
            replaced = true;
            continue;
          }
          out.add(line);
          continue;
        }
        inFeatures = false;
      }
      out.add(line);
    }

    if (!replaced) {
      // Feature existed on disk only — append.
      out.add('    - $to');
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

class FeatureRenameReport {
  FeatureRenameReport({
    required this.from,
    required this.to,
    required this.touchedPaths,
    required this.quality,
  });

  final String from;
  final String to;
  final List<String> touchedPaths;
  final QualityReport quality;
}
