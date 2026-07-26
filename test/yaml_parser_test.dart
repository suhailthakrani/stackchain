import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/models/stackchain_config.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:test/test.dart';

void main() {
  group('YamlParser', () {
    test('empty content uses defaults', () {
      final config = YamlParser.parse('', packageName: 'demo');
      expect(config.architecture, Architecture.featureFirst);
      expect(config.stateManagement, StateManagement.bloc);
      expect(config.routing, Routing.goRouter);
      expect(config.di, DiType.getIt);
      expect(config.features, ['home']);
      expect(config.packageName, 'demo');
    });

    test('minimal features-only config', () {
      const yaml = '''
stackchain:
  features:
    - auth
    - home
    - profile
''';
      final config = YamlParser.parse(yaml);
      expect(config.features, ['auth', 'home', 'profile']);
      expect(config.stateManagement, StateManagement.bloc);
    });

    test('cubit is a first-class state option', () {
      const yaml = '''
stackchain:
  state_management: cubit
  features:
    - home
''';
      final config = YamlParser.parse(yaml);
      expect(config.stateManagement, StateManagement.cubit);
      expect(config.stateManagement.usesFlutterBloc, isTrue);
      expect(config.inferredDependencies().keys, contains('flutter_bloc'));
    });

    test('rxdart is a first-class state option', () {
      const yaml = '''
stackchain:
  state_management: rxdart
  features:
    - home
''';
      final config = YamlParser.parse(yaml);
      expect(config.stateManagement, StateManagement.rxdart);
      expect(config.stateManagement.usesRxDart, isTrue);
      expect(config.inferredDependencies().keys, contains('rxdart'));
    });

    test('getx smart-defaults routing and di', () {
      const yaml = '''
stackchain:
  architecture: mvc
  state_management: getx
  features:
    - home
''';
      final config = YamlParser.parse(yaml);
      expect(config.stateManagement, StateManagement.getx);
      expect(config.routing, Routing.getx);
      expect(config.di, DiType.getx);
      expect(config.architecture, Architecture.mvc);
    });

    test('standard flat toggles', () {
      const yaml = '''
stackchain:
  architecture: clean
  state_management: riverpod
  localization: true
  firebase: true
  features:
    - home
''';
      final config = YamlParser.parse(yaml);
      expect(config.architecture, Architecture.clean);
      expect(config.stateManagement, StateManagement.riverpod);
      expect(config.modules.localization, isTrue);
      expect(config.modules.firebase, isTrue);
    });

    test('rejects unknown architecture', () {
      expect(
        () => YamlParser.parse('''
stackchain:
  architecture: hexagonal
'''),
        throwsFormatException,
      );
    });
  });

  group('StackchainConfig inference', () {
    test('getx pulls get package', () {
      final deps = StackchainConfig(
        stateManagement: StateManagement.getx,
        routing: Routing.getx,
        di: DiType.getx,
      ).inferredDependencies();
      expect(deps.keys, contains('get'));
    });

    test('bloc + dio + get_it deps', () {
      final deps = StackchainConfig.defaults().inferredDependencies();
      expect(deps.keys, containsAll(['flutter_bloc', 'dio', 'get_it']));
    });
  });
}
