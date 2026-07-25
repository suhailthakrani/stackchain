import 'dart:io';

import 'package:path/path.dart' as p;

import '../architecture/architecture_registry.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../parser/config_validator.dart';
import '../parser/yaml_parser.dart';
import '../templates/app/app_templates.dart';
import '../templates/app/router_templates.dart';
import '../templates/core/core_templates.dart';
import '../templates/features/feature_templates.dart';
import '../templates/test/module_templates.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../utils/pubspec_merger.dart';

/// Orchestrates full project generation.
class ProjectGenerator {
  ProjectGenerator({
    required this.root,
    Logger? logger,
    ArchitectureRegistry? architectureRegistry,
    this.dryRun = false,
    this.overwrite = false,
  })  : logger = logger ?? Logger(),
        architectureRegistry = architectureRegistry ?? ArchitectureRegistry();

  final String root;
  final Logger logger;
  final ArchitectureRegistry architectureRegistry;
  final bool dryRun;
  final bool overwrite;

  Future<StackchainConfig> run() async {
    final context = await ProjectContext.detect(root);
    logger.step('Detected Flutter app: ${context.packageName}');

    final config = await _loadConfig(context.packageName);
    final warnings = const ConfigValidator().validate(config);
    for (final w in warnings) {
      logger.warn(w);
    }

    logger.step(
      'Architecture=${config.architecture.yaml}, '
      'state=${config.stateManagement.yaml}, '
      'routing=${config.routing.yaml}, '
      'di=${config.di.yaml}',
    );
    logger.step('Features: ${config.features.join(', ')}');

    final writer = FileWriter(
      root: root,
      dryRun: dryRun,
      overwrite: overwrite,
    );

    for (final feature in config.features) {
      final layout = architectureRegistry.layoutFor(feature, config);
      for (final dir in layout.directories) {
        await writer.ensureDir(dir);
      }
    }

    final files = <String, String>{
      ...AppTemplates(config).generate(),
      ...RouterTemplates(config).generate(),
      ...CoreTemplates(config).generate(),
      ...FeatureTemplates(config, registry: architectureRegistry).generate(),
      ...ModuleTemplates(config).generate(),
    };

    final forceMain = await _shouldReplaceMainDart();
    logger.step('Writing ${files.length} files...');
    for (final entry in files.entries) {
      final force = entry.key == 'lib/main.dart' && forceMain;
      await writer.write(entry.key, entry.value, force: force);
      logger.detail(entry.key);
    }

    await _mergePubspec(config);
    await writeDefaultConfig(root);
    await _removeStockCounterApp();

    _printSummary(writer, config);
    return config;
  }

  /// Replace Flutter's default counter `main.dart` (or missing entrypoint).
  Future<bool> _shouldReplaceMainDart() async {
    final mainFile = File(p.join(root, 'lib/main.dart'));
    if (!await mainFile.exists()) return true;
    final content = await mainFile.readAsString();
    if (_isStockFlutterCounterMain(content)) {
      logger.step('Replacing Flutter default counter main.dart');
      return true;
    }
    // Already a stackchain entrypoint — refresh when --overwrite is set.
    if (content.contains('configureDependencies') &&
        content.contains('package:') &&
        content.contains('/app/app.dart')) {
      return overwrite;
    }
    // Unknown / custom main — only touch with --overwrite.
    if (!overwrite) {
      logger.warn(
        'lib/main.dart looks customized — pass --overwrite to replace it',
      );
    }
    return overwrite;
  }

  /// Detects Flutter create templates (counter or minimal MyApp).
  static bool _isStockFlutterCounterMain(String content) {
    if (content.contains('configureDependencies') &&
        content.contains('/app/app.dart')) {
      return false;
    }

    final hasCounter = content.contains('_counter') ||
        content.contains('_incrementCounter') ||
        content.contains('Increment the counter');
    final hasStockHome = content.contains('MyHomePage') ||
        (content.contains('class MyApp') &&
            content.contains('FloatingActionButton'));
    if (hasCounter && hasStockHome) return true;

    // `flutter create --empty` / minimal demo shell
    return content.contains('class MyApp') &&
        !content.contains('/app/app.dart') &&
        (content.contains('Hello World') || content.contains('MyHomePage'));
  }

  Future<StackchainConfig> _loadConfig(String packageName) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) {
      logger.info('No stackchain.yaml — using sensible defaults.');
      return StackchainConfig.defaults(packageName: packageName);
    }
    final content = await file.readAsString();
    return YamlParser.parse(content, packageName: packageName);
  }

  Future<void> _mergePubspec(StackchainConfig config) async {
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    final existing = await pubspecFile.readAsString();
    final merged = PubspecMerger.merge(existing: existing, config: config);
    if (merged == existing) {
      logger.detail('pubspec.yaml already up to date');
      return;
    }
    if (dryRun) {
      logger.step('Would update pubspec.yaml dependencies');
      return;
    }
    await pubspecFile.writeAsString(merged);
    logger.success('Updated pubspec.yaml dependencies');
  }

  Future<void> _removeStockCounterApp() async {
    final stockTest = File(p.join(root, 'test/widget_test.dart'));
    if (await stockTest.exists() && !dryRun) {
      await stockTest.delete();
      logger.detail('Removed stock test/widget_test.dart');
    }
  }

  void _printSummary(FileWriter writer, StackchainConfig config) {
    logger.banner('stackchain');
    logger.success('Created ${writer.created.length} files');
    if (writer.updated.isNotEmpty) {
      logger.info('Updated ${writer.updated.length} files');
    }
    if (writer.skipped.isNotEmpty) {
      logger.warn(
        'Skipped ${writer.skipped.length} existing files '
        '(pass --overwrite to replace)',
      );
    }
    logger.info('');
    logger.info('Next steps:');
    logger.info('  1. flutter pub get');
    if (config.di == DiType.injectable ||
        config.routing == Routing.autoRoute) {
      logger.info(
        '  2. dart run build_runner build --delete-conflicting-outputs',
      );
      logger.info('  3. flutter run');
    } else {
      logger.info('  2. flutter run');
    }
    logger.info('');
  }
}
