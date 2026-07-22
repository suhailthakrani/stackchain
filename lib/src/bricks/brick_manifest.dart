import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Mason-inspired brick manifest (`brick.yaml`).
class BrickManifest {
  BrickManifest({
    required this.name,
    required this.description,
    required this.vars,
    required this.root,
    this.hooks = const {},
  });

  final String name;
  final String description;
  final Map<String, BrickVar> vars;
  final String root;
  final Map<String, List<String>> hooks;

  String get brickDir => p.join(root, '__brick__');

  static Future<BrickManifest> load(String brickRoot) async {
    final file = File(p.join(brickRoot, 'brick.yaml'));
    if (!await file.exists()) {
      throw StateError('Missing brick.yaml in $brickRoot');
    }
    final doc = loadYaml(await file.readAsString());
    if (doc is! YamlMap) {
      throw const FormatException('brick.yaml must be a map');
    }

    final vars = <String, BrickVar>{};
    final varsRaw = doc['vars'];
    if (varsRaw is YamlMap) {
      for (final entry in varsRaw.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        if (value is YamlMap) {
          vars[key] = BrickVar(
            type: '${value['type'] ?? 'string'}',
            description: '${value['description'] ?? ''}',
            prompt: value['prompt'] as String?,
            defaultValue: value['default']?.toString(),
          );
        } else {
          vars[key] = BrickVar(type: 'string', description: '$value');
        }
      }
    }

    final hooks = <String, List<String>>{};
    final hooksRaw = doc['hooks'];
    if (hooksRaw is YamlMap) {
      for (final entry in hooksRaw.entries) {
        final list = entry.value;
        if (list is YamlList) {
          hooks['${entry.key}'] = list.map((e) => '$e').toList();
        }
      }
    }

    return BrickManifest(
      name: '${doc['name'] ?? p.basename(brickRoot)}',
      description: '${doc['description'] ?? ''}',
      vars: vars,
      root: brickRoot,
      hooks: hooks,
    );
  }
}

class BrickVar {
  const BrickVar({
    required this.type,
    this.description = '',
    this.prompt,
    this.defaultValue,
  });

  final String type;
  final String description;
  final String? prompt;
  final String? defaultValue;
}
