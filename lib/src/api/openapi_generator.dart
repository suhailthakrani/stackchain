import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:recase/recase.dart';
import 'package:yaml/yaml.dart';

import '../merge/owned_regions.dart';
import '../merge/preserving_file_writer.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../quality/quality_gate.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import 'openapi_parser.dart';

/// Generates Dart models (+ API repos) from an OpenAPI 3.x spec.
///
/// Re-run is safe: `// <stackchain:generated>` is refreshed;
/// `// <stackchain:custom>` is preserved.
class OpenApiGenerator {
  OpenApiGenerator({
    required this.root,
    required this.config,
    Logger? logger,
    this.overwrite = false,
    this.dryRun = false,
    this.skipAnalyze = false,
  }) : logger = logger ?? Logger();

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool overwrite;
  final bool dryRun;
  final bool skipAnalyze;

  static const lockRelative = '.stackchain/openapi.yaml';

  /// Generates from [specPath], or last path stored under [.stackchain/openapi.yaml].
  Future<QualityReport> run({String? specPath}) async {
    logger.banner('stackchain api');

    final resolved = specPath ?? await _readLastSpec();
    if (resolved == null) {
      throw StateError(
        'Usage: dart run stackchain api <openapi.yaml|json>\n'
        'Re-run without a path to refresh from the last spec.',
      );
    }

    final abs =
        p.isAbsolute(resolved) ? resolved : p.normalize(p.join(root, resolved));
    final doc = await OpenApiParser.parseFile(abs);
    logger.info('${doc.title}: ${doc.schemas.length} schema(s)');

    final writer = PreservingFileWriter(
      writer: FileWriter(root: root, overwrite: overwrite, dryRun: dryRun),
      logger: logger,
    );

    final pkg = config.packageName ?? 'app';
    final useDio = config.network == NetworkClient.dio;
    var written = 0;

    for (final schema in doc.schemas) {
      final snake = ReCase(schema.name).snakeCase;
      await writer.writeOwned(
        relativePath: 'lib/core/api/models/${snake}_model.dart',
        fullGenerated: _modelSource(schema),
      );
      written++;

      await writer.writeOwned(
        relativePath: 'lib/core/api/repositories/${snake}_api_repository.dart',
        fullGenerated: _repositorySource(schema, pkg, useDio: useDio),
      );
      written++;
    }

    await writer.writeOwned(
      relativePath: 'lib/core/api/api.dart',
      fullGenerated: _barrelSource(doc),
    );
    written++;

    if (!dryRun) {
      await _saveLastSpec(p.relative(abs, from: root));
    }

    logger.success(
      dryRun
          ? 'Would generate $written file(s) from ${p.basename(abs)}'
          : 'Generated $written file(s) under lib/core/api/',
    );
    logger.info('Re-run after API changes: dart run stackchain api');

    if (dryRun || skipAnalyze) {
      return QualityReport();
    }

    return QualityGate(
      root: root,
      config: config,
      logger: logger,
    ).run();
  }

  Future<String?> _readLastSpec() async {
    final file = File(p.join(root, lockRelative));
    if (!await file.exists()) return null;
    final doc = loadYaml(await file.readAsString());
    if (doc is Map && doc['spec'] != null) {
      return doc['spec'].toString();
    }
    return null;
  }

  Future<void> _saveLastSpec(String relativeSpec) async {
    final file = File(p.join(root, lockRelative));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '# Last OpenAPI spec used by `stackchain api`.\n'
      'spec: $relativeSpec\n',
    );
  }

  String _modelSource(OpenApiSchema schema) {
    final pascal = ReCase(schema.name).pascalCase;
    final fields = StringBuffer();
    final ctorParams = StringBuffer();
    final fromJson = StringBuffer();
    final toJson = StringBuffer();

    for (final prop in schema.properties) {
      final required = schema.required.contains(prop.jsonKey);
      final type = required ? prop.dartType : '${prop.dartType}?';
      fields.writeln('  final $type ${prop.name};');
      ctorParams.writeln(
        required ? '    required this.${prop.name},' : '    this.${prop.name},',
      );
      fromJson.writeln(
        '      ${prop.name}: ${_fromJsonExpr(prop, required)},',
      );
      toJson.writeln(
        required
            ? "      '${prop.jsonKey}': ${prop.name},"
            : "      if (${prop.name} != null) '${prop.jsonKey}': ${prop.name},",
      );
    }

    return '''
/// ${schema.name} — generated from OpenAPI.
///
/// Re-run: `dart run stackchain api`
/// Edit only inside `// <stackchain:custom>`.

class ${pascal}Model {
  // <stackchain:generated>
  const ${pascal}Model({
${ctorParams.toString().trimRight()}
  });

${fields.toString().trimRight()}

  factory ${pascal}Model.fromJson(Map<String, dynamic> json) {
    return ${pascal}Model(
${fromJson.toString().trimRight()}
    );
  }

  Map<String, dynamic> toJson() => {
${toJson.toString().trimRight()}
  };
  // </stackchain:generated>

${OwnedRegions.customRegionBlock()}
}
''';
  }

  String _fromJsonExpr(OpenApiProperty prop, bool required) {
    final key = prop.jsonKey;
    if (prop.isList) {
      final inner = prop.dartType.replaceFirst('List<', '').replaceAll('>', '');
      final mapExpr = inner.endsWith('Model')
          ? '(e) => $inner.fromJson(e as Map<String, dynamic>)'
          : '(e) => e as $inner';
      if (required) {
        return "(json['$key'] as List<dynamic>? ?? const [])\n"
            '          .map($mapExpr)\n'
            '          .toList()';
      }
      return "json['$key'] == null\n"
          '          ? null\n'
          "          : (json['$key'] as List<dynamic>)\n"
          '              .map($mapExpr)\n'
          '              .toList()';
    }

    if (prop.dartType.endsWith('Model')) {
      if (required) {
        return "${prop.dartType}.fromJson("
            "json['$key'] as Map<String, dynamic>? ?? const {})";
      }
      return "json['$key'] == null\n"
          '          ? null\n'
          '          : ${prop.dartType}.fromJson('
          "json['$key'] as Map<String, dynamic>)";
    }

    switch (prop.dartType) {
      case 'int':
        return required ? "json['$key'] as int? ?? 0" : "json['$key'] as int?";
      case 'double':
        return required
            ? "(json['$key'] as num?)?.toDouble() ?? 0"
            : "(json['$key'] as num?)?.toDouble()";
      case 'bool':
        return required
            ? "json['$key'] as bool? ?? false"
            : "json['$key'] as bool?";
      case 'Map<String, dynamic>':
        return required
            ? "json['$key'] as Map<String, dynamic>? ?? const {}"
            : "json['$key'] as Map<String, dynamic>?";
      default:
        return required
            ? "json['$key'] as String? ?? ''"
            : "json['$key'] as String?";
    }
  }

  String _repositorySource(
    OpenApiSchema schema,
    String pkg, {
    required bool useDio,
  }) {
    final pascal = ReCase(schema.name).pascalCase;
    final snake = ReCase(schema.name).snakeCase;
    final pathHint = '/$snake';

    final imports = useDio
        ? '''
import 'package:$pkg/core/api/models/${snake}_model.dart';
import 'package:$pkg/core/network/api_client.dart';
'''
        : '''
import 'dart:convert';

import 'package:$pkg/core/api/models/${snake}_model.dart';
import 'package:$pkg/core/network/api_client.dart';
''';

    final listBody = useDio
        ? '''
    final response = await _client.get('$pathHint');
    final data = response.data;
    final list = data is List
        ? data
        : (data is Map && data['data'] is List)
            ? data['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => ${pascal}Model.fromJson(Map<String, dynamic>.from(e)))
        .toList();'''
        : '''
    final response = await _client.get('$pathHint');
    final decoded = jsonDecode(response.body);
    final list = decoded is List
        ? decoded
        : (decoded is Map && decoded['data'] is List)
            ? decoded['data'] as List
            : const [];
    return list
        .whereType<Map>()
        .map((e) => ${pascal}Model.fromJson(Map<String, dynamic>.from(e)))
        .toList();''';

    final getBody = useDio
        ? '''
    final response = await _client.get('$pathHint/\$id');
    final data = response.data;
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return ${pascal}Model.fromJson(map);'''
        : '''
    final response = await _client.get('$pathHint/\$id');
    final decoded = jsonDecode(response.body);
    final map = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    return ${pascal}Model.fromJson(map);''';

    return '''
/// $pascal API repository — generated from OpenAPI.
///
/// Default path: `$pathHint`. Adjust in custom or after refining the spec.
$imports
class ${pascal}ApiRepository {
  ${pascal}ApiRepository(this._client);

  final ApiClient _client;

  // <stackchain:generated>
  Future<List<${pascal}Model>> list() async {$listBody
  }

  Future<${pascal}Model> getById(String id) async {$getBody
  }
  // </stackchain:generated>

${OwnedRegions.customRegionBlock()}
}
''';
  }

  String _barrelSource(OpenApiDocument doc) {
    final body = StringBuffer();
    for (final schema in doc.schemas) {
      final snake = ReCase(schema.name).snakeCase;
      body
        ..writeln("export 'models/${snake}_model.dart';")
        ..writeln("export 'repositories/${snake}_api_repository.dart';");
    }

    return '''
/// OpenAPI-generated API surface.
///
/// Re-run: `dart run stackchain api`
// <stackchain:generated>
${body.toString().trimRight()}
// </stackchain:generated>
''';
  }
}
