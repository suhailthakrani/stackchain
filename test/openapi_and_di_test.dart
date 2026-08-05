import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stackchain/src/api/openapi_generator.dart';
import 'package:stackchain/src/api/openapi_parser.dart';
import 'package:stackchain/src/merge/owned_regions.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/templates/core/core_templates.dart';
import 'package:test/test.dart';

void main() {
  group('injection.dart structure', () {
    test('get_it groups related registrations with section comments', () {
      final config = YamlParser.parse('''
stackchain:
  architecture: feature_first
  state_management: bloc
  routing: go_router
  di: get_it
  network: dio
  storage: [secure_storage, shared_preferences]
  features: [auth, home]
''', packageName: 'di_app');

      final di = CoreTemplates(config).generate()['lib/core/di/injection.dart']!;

      expect(di, contains('Application dependency injection (GetIt)'));
      expect(di, contains('// ── Logging & errors'));
      expect(di, contains('// ── Storage'));
      expect(di, contains('// ── Session'));
      expect(di, contains('// ── Network'));
      expect(di, contains('// ── auth'));
      expect(di, contains('// ── home'));
      expect(RegionMerger.hasRegion(di, 'core'), isTrue);
      expect(RegionMerger.hasRegion(di, 'features'), isTrue);

      // Package imports before project imports (blank line between groups).
      final getIt = di.indexOf("import 'package:get_it/get_it.dart';");
      final coreErr = di.indexOf("import 'package:di_app/core/errors/");
      final feature = di.indexOf("import 'package:di_app/features/auth/");
      expect(getIt, lessThan(coreErr));
      expect(coreErr, lessThan(feature));
    });
  });

  group('openapi', () {
    test('parser reads schemas from yaml', () {
      final doc = OpenApiParser.parseMap({
        'info': {'title': 'Pets'},
        'components': {
          'schemas': {
            'Pet': {
              'type': 'object',
              'required': ['id', 'name'],
              'properties': {
                'id': {'type': 'integer'},
                'name': {'type': 'string'},
                'tag': {'type': 'string'},
              },
            },
          },
        },
      }, sourcePath: 'spec.yaml');

      expect(doc.title, 'Pets');
      expect(doc.schemas, hasLength(1));
      expect(doc.schemas.first.name, 'Pet');
      expect(doc.schemas.first.properties.map((p) => p.name),
          containsAll(['id', 'name', 'tag']));
    });

    test('generator writes models + repos and preserves custom', () async {
      final temp = await Directory.systemTemp.createTemp('stackchain_api_');
      addTearDown(() => temp.delete(recursive: true));

      await File(p.join(temp.path, 'pubspec.yaml')).writeAsString('''
name: api_app
environment:
  sdk: '>=3.0.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  dio: any
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
''');
      await File(p.join(temp.path, 'stackchain.yaml')).writeAsString('''
stackchain:
  network: dio
  features: [home]
''');
      await Directory(p.join(temp.path, 'lib')).create();

      final spec = File(p.join(temp.path, 'openapi.yaml'));
      await spec.writeAsString('''
openapi: 3.0.0
info:
  title: Demo API
  version: 1.0.0
components:
  schemas:
    Pet:
      type: object
      required: [id, name]
      properties:
        id:
          type: integer
        name:
          type: string
        tag:
          type: string
''');

      final config = YamlParser.parse(
        await File(p.join(temp.path, 'stackchain.yaml')).readAsString(),
        packageName: 'api_app',
      );

      await OpenApiGenerator(
        root: temp.path,
        config: config,
        skipAnalyze: true,
      ).run(specPath: spec.path);

      final modelPath =
          p.join(temp.path, 'lib/core/api/models/pet_model.dart');
      final model = await File(modelPath).readAsString();
      expect(model, contains('class PetModel'));
      expect(model, contains('fromJson'));
      expect(OwnedRegions.hasOwnedMarkers(model), isTrue);

      // Hand-edit custom region, regenerate, custom must survive.
      final withCustom = model.replaceFirst(
        OwnedRegions.customPlaceholder.trim(),
        '  String get label => name;',
      );
      await File(modelPath).writeAsString(withCustom);

      await OpenApiGenerator(
        root: temp.path,
        config: config,
        skipAnalyze: true,
      ).run(); // uses saved .stackchain/openapi.yaml

      final refreshed = await File(modelPath).readAsString();
      expect(refreshed, contains('String get label => name;'));
      expect(refreshed, contains('class PetModel'));

      final repo = await File(
        p.join(temp.path, 'lib/core/api/repositories/pet_api_repository.dart'),
      ).readAsString();
      expect(repo, contains('PetApiRepository'));
      expect(repo, contains('Future<List<PetModel>> list()'));

      expect(config.network, NetworkClient.dio);
    });
  });
}
