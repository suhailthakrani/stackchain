import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Parsed OpenAPI 3.x document — schemas only (MVP).
class OpenApiDocument {
  OpenApiDocument({
    required this.title,
    required this.schemas,
    required this.sourcePath,
  });

  final String title;
  final String sourcePath;
  final List<OpenApiSchema> schemas;
}

class OpenApiSchema {
  OpenApiSchema({
    required this.name,
    required this.properties,
    required this.required,
  });

  final String name;
  final List<OpenApiProperty> properties;
  final Set<String> required;
}

class OpenApiProperty {
  OpenApiProperty({
    required this.name,
    required this.dartType,
    required this.jsonKey,
    this.isList = false,
  });

  final String name;
  final String dartType;
  final String jsonKey;
  final bool isList;
}

/// Minimal OpenAPI 3 parser: `components.schemas` → Dart-friendly models.
class OpenApiParser {
  /// Reads YAML or JSON OpenAPI from [path].
  static Future<OpenApiDocument> parseFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('OpenAPI file not found: $path');
    }
    final raw = await file.readAsString();
    final ext = p.extension(path).toLowerCase();
    final Object? root;
    if (ext == '.json') {
      root = jsonDecode(raw);
    } else {
      root = loadYaml(raw);
    }
    if (root is! Map) {
      throw StateError('OpenAPI root must be a map/object');
    }
    return parseMap(_deepToMap(root), sourcePath: path);
  }

  static OpenApiDocument parseMap(
    Map<String, dynamic> root, {
    required String sourcePath,
  }) {
    final info = root['info'];
    final title = info is Map
        ? (info['title']?.toString() ?? 'API')
        : 'API';

    final components = root['components'];
    final schemasNode = components is Map ? components['schemas'] : null;
    if (schemasNode is! Map || schemasNode.isEmpty) {
      throw StateError(
        'No components.schemas found. stackchain api needs OpenAPI schemas.',
      );
    }

    final schemas = <OpenApiSchema>[];
    for (final entry in schemasNode.entries) {
      final name = entry.key.toString();
      final value = entry.value;
      if (value is! Map) continue;
      final schemaMap = _deepToMap(value);
      if (schemaMap['type'] == 'array') continue; // skip top-level arrays
      final propsNode = schemaMap['properties'];
      if (propsNode is! Map) continue;

      final required = <String>{};
      final req = schemaMap['required'];
      if (req is List) {
        for (final r in req) {
          required.add(r.toString());
        }
      }

      final properties = <OpenApiProperty>[];
      for (final prop in propsNode.entries) {
        final propName = prop.key.toString();
        final propSchema =
            prop.value is Map ? _deepToMap(prop.value as Map) : <String, dynamic>{};
        final resolved = _resolveType(propSchema, schemasNode);
        properties.add(
          OpenApiProperty(
            name: _dartFieldName(propName),
            dartType: resolved.type,
            jsonKey: propName,
            isList: resolved.isList,
          ),
        );
      }

      if (properties.isEmpty) continue;
      schemas.add(
        OpenApiSchema(
          name: name,
          properties: properties,
          required: required,
        ),
      );
    }

    if (schemas.isEmpty) {
      throw StateError('No object schemas with properties to generate.');
    }

    return OpenApiDocument(
      title: title,
      schemas: schemas,
      sourcePath: sourcePath,
    );
  }

  static ({String type, bool isList}) _resolveType(
    Map<String, dynamic> schema,
    Map schemasNode,
  ) {
    final ref = schema[r'$ref']?.toString();
    if (ref != null) {
      final name = ref.split('/').last;
      return (type: '${_pascal(name)}Model', isList: false);
    }

    final type = schema['type']?.toString() ?? 'string';
    if (type == 'array') {
      final items = schema['items'];
      if (items is Map) {
        final inner = _resolveType(_deepToMap(items), schemasNode);
        return (type: 'List<${inner.type}>', isList: true);
      }
      return (type: 'List<dynamic>', isList: true);
    }

    switch (type) {
      case 'integer':
        return (type: 'int', isList: false);
      case 'number':
        return (type: 'double', isList: false);
      case 'boolean':
        return (type: 'bool', isList: false);
      case 'object':
        return (type: 'Map<String, dynamic>', isList: false);
      default:
        return (type: 'String', isList: false);
    }
  }

  static String _dartFieldName(String jsonKey) {
    final snake = jsonKey
        .replaceAllMapped(
          RegExp(r'[A-Z]'),
          (m) => '_${m[0]!.toLowerCase()}',
        )
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (snake.isEmpty) return 'value';
    final parts = snake.split('_').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'value';
    final camel = StringBuffer(parts.first.toLowerCase());
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i];
      camel.write(p[0].toUpperCase());
      if (p.length > 1) camel.write(p.substring(1).toLowerCase());
    }
    final name = camel.toString();
    const reserved = {
      'class',
      'enum',
      'extends',
      'with',
      'new',
      'default',
      'is',
      'as',
      'in',
    };
    if (reserved.contains(name)) return '${name}_';
    return name;
  }

  static String _pascal(String name) {
    return name
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .split('_')
        .where((s) => s.isNotEmpty)
        .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
        .join();
  }

  static Map<String, dynamic> _deepToMap(Map map) {
    return map.map((key, value) {
      final k = key.toString();
      if (value is Map) return MapEntry(k, _deepToMap(value));
      if (value is List) {
        return MapEntry(
          k,
          value.map((e) => e is Map ? _deepToMap(e) : e).toList(),
        );
      }
      return MapEntry(k, value);
    });
  }
}
