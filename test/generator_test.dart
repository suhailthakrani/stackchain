import 'package:stackchain_flutter/src/architecture/architecture_registry.dart';
import 'package:stackchain_flutter/src/models/enums.dart';
import 'package:stackchain_flutter/src/models/stackchain_config.dart';
import 'package:stackchain_flutter/src/templates/app/app_templates.dart';
import 'package:stackchain_flutter/src/templates/core/core_templates.dart';
import 'package:stackchain_flutter/src/templates/features/feature_templates.dart';
import 'package:test/test.dart';

void main() {
  group('ArchitectureRegistry', () {
    final registry = ArchitectureRegistry();

    test('feature_first layout has data/domain/presentation', () {
      final layout = registry.layoutFor(
        'auth',
        StackchainConfig.defaults(packageName: 'demo'),
      );
      expect(layout.root, 'lib/features/auth');
      expect(layout.directories.any((d) => d.contains('domain')), isTrue);
      expect(layout.pagesDir, contains('presentation/pages'));
    });

    test('mvvm layout uses viewmodels/views', () {
      final layout = registry.layoutFor(
        'home',
        StackchainConfig(
          architecture: Architecture.mvvm,
          packageName: 'demo',
        ),
      );
      expect(layout.stateDir, 'lib/features/home/viewmodels');
      expect(layout.pagesDir, 'lib/features/home/views');
    });
  });

  group('templates', () {
    test('app + core + feature produce expected paths', () {
      final config = StackchainConfig(
        packageName: 'demo',
        features: const ['home', 'auth'],
      );
      final files = {
        ...AppTemplates(config).generate(),
        ...CoreTemplates(config).generate(),
        ...FeatureTemplates(config).generate(),
      };

      expect(files.keys, contains('lib/main.dart'));
      expect(files.keys, contains('lib/app/app.dart'));
      expect(files.keys, contains('lib/core/network/dio_client.dart'));
      expect(
        files.keys,
        contains('lib/features/home/presentation/pages/home_page.dart'),
      );
      expect(
        files.keys,
        contains('lib/features/auth/presentation/bloc/auth_bloc.dart'),
      );
      expect(files['lib/main.dart'], contains('configureDependencies'));
    });
    test('cubit feature generates cubit files', () {
      final config = StackchainConfig(
        packageName: 'demo',
        stateManagement: StateManagement.cubit,
        features: const ['home'],
      );
      final files = FeatureTemplates(config).generate();
      expect(
        files.keys,
        contains('lib/features/home/presentation/cubit/home_cubit.dart'),
      );
      expect(
        files['lib/features/home/presentation/pages/home_page.dart'],
        contains('Cubit'),
      );
    });
  });
}
