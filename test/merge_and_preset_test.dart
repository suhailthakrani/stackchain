import 'package:stackchain/src/merge/dart_import_merger.dart';
import 'package:stackchain/src/merge/region_merger.dart';
import 'package:stackchain/src/merge/smart_file_merger.dart';
import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/presets/preset_registry.dart';
import 'package:test/test.dart';

void main() {
  group('RegionMerger', () {
    test('replaces existing region body', () {
      const source = '''
class A {
  // <stackchain:routes>
  old();
  // </stackchain:routes>
}
''';
      final next = RegionMerger.replaceRegion(
        source: source,
        id: 'routes',
        body: '  new();\n',
      );
      expect(next, contains('new();'));
      expect(next, isNot(contains('old();')));
      expect(RegionMerger.hasRegion(next, 'routes'), isTrue);
    });

    test('appends region when missing', () {
      const source = 'class A {}\n';
      final next = RegionMerger.replaceRegion(
        source: source,
        id: 'routes',
        body: '  x();\n',
      );
      expect(RegionMerger.hasRegion(next, 'routes'), isTrue);
      expect(next, contains('x();'));
    });

    test('ignores marker-like text inside doc comments', () {
      const source = '''
// Owned by stackchain:
// - // <stackchain:core> — do not match this
Future<void> configureDependencies() async {
  // <stackchain:core>
  real();
  // </stackchain:core>
}
''';
      expect(RegionMerger.readRegion(source, 'core')?.trim(), 'real();');
      final next = RegionMerger.replaceRegion(
        source: source,
        id: 'core',
        body: '  replaced();\n',
      );
      expect(next, contains('// - // <stackchain:core> — do not match this'));
      expect(next, contains('replaced();'));
      expect(next, isNot(contains('real();')));
    });
  });

  group('DartImportMerger', () {
    test('adds missing imports after existing ones', () {
      const source = '''
import 'package:a/a.dart';

class Foo {}
''';
      final next = DartImportMerger.mergeImports(source, [
        'package:b/b.dart',
        'package:a/a.dart',
      ]);
      expect(next, contains("import 'package:b/b.dart';"));
      expect(
        RegExp(r"import 'package:a/a.dart';").allMatches(next).length,
        1,
      );
    });
  });

  group('SmartFileMerger', () {
    test('merges imports and region together', () {
      const existing = '''
import 'package:a/a.dart';

abstract final class AppRouter {
  static final routes = [
    // <stackchain:routes>
    // </stackchain:routes>
  ];
}
''';
      final next = const SmartFileMerger().merge(
        existing: existing,
        regionId: 'routes',
        regionBody: '    GoRoute(path: "/"),\n',
        imports: ['package:demo/features/home/presentation/pages/home_page.dart'],
      );
      expect(next, contains('GoRoute'));
      expect(next, contains('home_page.dart'));
      expect(next, contains("import 'package:a/a.dart';"));
    });
  });

  group('presets', () {
    test('production_bloc expands with user features winning', () {
      final config = YamlParser.parse('''
stackchain:
  preset: production_bloc
  features:
    - auth
    - home
''', packageName: 'demo');

      expect(config.preset, 'production_bloc');
      expect(config.stateManagement, StateManagement.bloc);
      expect(config.routing, Routing.goRouter);
      expect(config.modules.localization, isTrue);
      expect(config.storage, contains(StorageType.secureStorage));
      expect(config.features, ['auth', 'home']);
    });

    test('explicit keys override preset', () {
      final config = YamlParser.parse('''
stackchain:
  preset: production_bloc
  state_management: cubit
  localization: false
  features: [home]
''', packageName: 'demo');

      expect(config.stateManagement, StateManagement.cubit);
      expect(config.modules.localization, isFalse);
    });

    test('unknown preset throws', () {
      expect(
        () => YamlParser.parse('''
stackchain:
  preset: not_a_real_preset
  features: [home]
'''),
        throwsFormatException,
      );
    });

    test('registry lists blueprints', () {
      final ids = const PresetRegistry().ids;
      expect(ids, contains('production_bloc'));
      expect(ids, contains('firebase_bloc'));
      expect(ids, contains('production_rxdart'));
    });
  });
}
