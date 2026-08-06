import 'package:stackchain/src/models/enums.dart';
import 'package:stackchain/src/parser/yaml_parser.dart';
import 'package:stackchain/src/templates/app/app_templates.dart';
import 'package:stackchain/src/templates/app/router_templates.dart';
import 'package:stackchain/src/templates/core/core_templates.dart';
import 'package:stackchain/src/templates/test/module_templates.dart';
import 'package:test/test.dart';

void main() {
  group('production baseline', () {
    test('secure session + dio + guards + flavors + ci', () {
      final config = YamlParser.parse('''
stackchain:
  preset: production_bloc
  features: [splash, auth, home]
''', packageName: 'prod_app');

      expect(config.modules.strictQuality, isTrue);
      expect(config.modules.flavors, isTrue);
      expect(config.modules.ci, isTrue);
      expect(config.storage, contains(StorageType.secureStorage));

      final files = {
        ...AppTemplates(config).generate(),
        ...RouterTemplates(config).generate(),
        ...CoreTemplates(config).generate(),
        ...ModuleTemplates(config).generate(),
      };

      expect(files['lib/app/config/environment.dart'],
          contains('String.fromEnvironment'));
      expect(files.keys, contains('lib/main_prod.dart'));
      expect(files.keys, contains('.github/workflows/stackchain_ci.yml'));
      expect(
        files['.github/workflows/stackchain_ci.yml'],
        contains('dart run stackchain doctor --skip-analyze'),
      );
      expect(files['lib/core/session/session_service.dart'],
          contains('saveSession'));
      expect(files['lib/core/network/dio_client.dart'],
          contains('UnauthorizedInterceptor'));
      expect(files['lib/core/network/interceptors/retry_interceptor.dart'],
          isNot(contains('Dio().fetch')));
      expect(files['lib/app/router/route_guards.dart'],
          contains('hasSession'));
      expect(files['lib/app/router/app_router.dart'], contains('redirect:'));
      expect(files['lib/core/di/injection.dart'], contains('SessionService'));
    });
  });
}
