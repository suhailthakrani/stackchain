import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';
import 'package:yaml/yaml.dart';

import '../architecture/architecture_registry.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../templates/features/feature_templates.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';

/// Adds a single feature and updates stackchain.yaml.
class FeatureCommand {
  FeatureCommand({
    required this.root,
    required this.logger,
    this.overwrite = false,
  });

  final String root;
  final Logger logger;
  final bool overwrite;

  Future<void> add(String rawName) async {
    final name = ReCase(rawName).snakeCase;
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw FormatException('Invalid feature name "$rawName"');
    }

    final context = await ProjectContext.detect(root);
    var config = await _loadConfig(context.packageName);

    if (config.features.contains(name)) {
      logger.warn('Feature "$name" already listed in config — regenerating files.');
    } else {
      config = config.copyWith(features: [...config.features, name]);
      await _appendFeatureToYaml(name);
      logger.success('Added "$name" to stackchain.yaml');
    }

    // Generate only this feature's files, then remind to re-run init for router/DI.
    final single = config.copyWith(features: [name]);
    final registry = ArchitectureRegistry();
    final layout = registry.layoutFor(name, config);
    final writer = FileWriter(root: root, overwrite: overwrite);

    for (final dir in layout.directories) {
      await writer.ensureDir(dir);
    }

    final files = FeatureTemplates(single, registry: registry).generate();
    for (final entry in files.entries) {
      await writer.write(entry.key, entry.value);
    }

    logger.success('Generated feature "$name" (${files.length} files)');
    logger.info(
      'Re-run `dart run stackchain_flutter:init --overwrite` to refresh '
      'router and DI registrations.',
    );
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
    final yamlRoot = doc is YamlMap
        ? (doc['stackchain'] ??
            doc['stackchain_flutter'] ??
            doc['flutter_starter'])
        : null;
    if (yamlRoot is YamlMap) {
      final features = yamlRoot['features'];
      if (features is YamlList) {
        final existing = features.map((e) => '$e').toList();
        if (existing.contains(name)) return;
      }
    }

    // Simple append — keeps user formatting for the rest of the file.
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
