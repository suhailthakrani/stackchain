import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../bricks/brick_engine.dart';
import '../generators/project_generator.dart';
import '../migrate/migration_engine.dart';
import '../migrate/upgrade_engine.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../presets/preset_registry.dart';
import '../quality/quality_gate.dart';
import '../sync/project_sync.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../version.dart';
import 'feature_command.dart';

/// Entry for `dart run stackchain` / `dart run stackchain:init`.
Future<void> run(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag(
      'overwrite',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite existing generated files.',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print actions without writing files.',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose logging.')
    ..addFlag(
      'skip-analyze',
      negatable: false,
      help: 'Skip dart analyze in the quality gate.',
    )
    ..addOption(
      'path',
      abbr: 'p',
      help: 'Flutter project root (defaults to current directory).',
    );

  parser.addCommand(
    'init',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('overwrite', abbr: 'f', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('verbose', abbr: 'v', negatable: false)
      ..addFlag('skip-analyze', negatable: false),
  );
  parser.addCommand(
    'sync',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false),
  );
  parser.addCommand(
    'upgrade',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false),
  );
  parser.addCommand(
    'migrate',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false)
      ..addFlag(
        'keep-old',
        negatable: false,
        help: 'Keep files/packages the previous stack needed',
      )
      ..addOption('architecture', help: 'Target architecture')
      ..addOption('state', help: 'Target state_management')
      ..addOption('routing', help: 'Target routing')
      ..addOption('di', help: 'Target DI')
      ..addOption('network', help: 'Target network client')
      ..addOption('preset', help: 'Apply a named preset blueprint'),
  );
  parser.addCommand(
    'doctor',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('skip-analyze', negatable: false),
  );
  parser.addCommand(
    'presets',
    ArgParser()..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'make',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('overwrite', abbr: 'f', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false)
      ..addOption('name', abbr: 'n', help: 'Name (or pass as positional).')
      ..addMultiOption('var', abbr: 'V', help: 'Extra vars as key=value.'),
  );
  parser.addCommand(
    'list',
    ArgParser()..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'feature',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('overwrite', abbr: 'f', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false)
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Feature name (or pass as positional).',
      ),
  );
  parser.addCommand(
    'add',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('overwrite', abbr: 'f', negatable: false)
      ..addFlag('dry-run', negatable: false)
      ..addFlag('skip-analyze', negatable: false)
      ..addOption(
        'name',
        abbr: 'n',
        help: 'Feature name (or pass as positional).',
      ),
  );
  parser.addCommand(
    'new',
    ArgParser()..addFlag('help', abbr: 'h', negatable: false),
  );
  parser.addCommand(
    'help',
    ArgParser()..addFlag('help', abbr: 'h', negatable: false),
  );

  late ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    _printUsage(parser);
    exitCode = 64;
    return;
  }

  if (results['help'] == true && results.command == null) {
    _printUsage(parser);
    return;
  }

  final command = results.command;
  final logger = Logger(
    verbose: results['verbose'] == true ||
        (command != null &&
            command.options.contains('verbose') &&
            command['verbose'] == true),
  );
  final root = p.normalize(
    p.absolute(results['path'] as String? ?? Directory.current.path),
  );
  bool flag(String name) =>
      results[name] == true ||
      (command != null &&
          command.options.contains(name) &&
          command[name] == true);
  final overwrite = flag('overwrite');
  final dryRun = flag('dry-run');
  final skipAnalyze = flag('skip-analyze');

  if (command == null) {
    await _initProject(
      root,
      logger,
      dryRun: dryRun,
      overwrite: overwrite,
      skipAnalyze: skipAnalyze,
    );
    return;
  }

  switch (command.name) {
    case 'help':
      _printHelp(parser, command.rest);
      return;
    case 'init':
      if (command['help'] == true) {
        _printHelp(parser, const ['init']);
        return;
      }
      await _initProject(
        root,
        logger,
        dryRun: dryRun,
        overwrite: overwrite,
        skipAnalyze: skipAnalyze,
      );
    case 'sync':
      if (command['help'] == true) {
        _printHelp(parser, const ['sync']);
        return;
      }
      await _sync(root, logger, dryRun: dryRun, skipAnalyze: skipAnalyze);
    case 'upgrade':
      if (command['help'] == true) {
        _printHelp(parser, const ['upgrade']);
        return;
      }
      await _upgrade(root, logger, dryRun: dryRun, skipAnalyze: skipAnalyze);
    case 'migrate':
      if (command['help'] == true) {
        _printHelp(parser, const ['migrate']);
        return;
      }
      await _migrate(
        command,
        root,
        logger,
        dryRun: dryRun,
        skipAnalyze: skipAnalyze,
      );
    case 'doctor':
      if (command['help'] == true) {
        _printHelp(parser, const ['doctor']);
        return;
      }
      await _doctor(root, logger, skipAnalyze: skipAnalyze);
    case 'presets':
      if (command['help'] == true) {
        _printHelp(parser, const ['presets']);
        return;
      }
      _printPresets(logger);
    case 'list':
      if (command['help'] == true) {
        _printHelp(parser, const ['list']);
        return;
      }
      await _listBricks(root, logger);
    case 'make':
      if (command['help'] == true) {
        _printHelp(parser, const ['make']);
        return;
      }
      await _makeBrick(
        command,
        root,
        logger,
        overwrite: overwrite,
        dryRun: dryRun,
        skipAnalyze: skipAnalyze,
      );
    case 'feature':
    case 'add':
      final cmdName = command.name ?? 'feature';
      final name = _resolveName(command);
      if (command['help'] == true) {
        _printHelp(parser, [cmdName]);
        return;
      }
      if (name == null) {
        _printHelp(parser, [cmdName]);
        return;
      }
      try {
        await FeatureCommand(
          root: root,
          logger: logger,
          overwrite: overwrite,
          dryRun: dryRun,
          skipAnalyze: skipAnalyze,
        ).add(name);
      } catch (e, st) {
        logger.error(e.toString());
        if (logger.verbose) logger.detail(st.toString());
        exitCode = 1;
      }
    case 'new':
      if (command['help'] == true) {
        _printHelp(parser, const ['new']);
        return;
      }
      await _scaffoldBrick(root, logger, command.rest);
    default:
      _printUsage(parser);
  }
}

String? _resolveName(ArgResults command) {
  final named = command['name'] as String?;
  if (named != null && named.trim().isNotEmpty) return named.trim();
  if (command.rest.isNotEmpty) return command.rest.first.trim();
  return null;
}

Future<void> _initProject(
  String root,
  Logger logger, {
  required bool dryRun,
  required bool overwrite,
  required bool skipAnalyze,
}) async {
  try {
    await ProjectGenerator(
      root: root,
      logger: logger,
      dryRun: dryRun,
      overwrite: overwrite,
      skipAnalyze: skipAnalyze,
    ).run();
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
}

Future<StackchainConfig> _loadConfig(String root, String packageName) async {
  final configFile = File(p.join(root, 'stackchain.yaml'));
  if (!await configFile.exists()) {
    return StackchainConfig.defaults(packageName: packageName);
  }
  return YamlParser.parse(
    await configFile.readAsString(),
    packageName: packageName,
  );
}

Future<void> _sync(
  String root,
  Logger logger, {
  required bool dryRun,
  required bool skipAnalyze,
}) async {
  try {
    final context = await ProjectContext.detect(root);
    final config = await _loadConfig(root, context.packageName);

    await ProjectSync(
      root: root,
      config: config,
      logger: logger,
      dryRun: dryRun,
    ).run();

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();
    if (!gate.passed) exitCode = 1;
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
}

Future<void> _upgrade(
  String root,
  Logger logger, {
  required bool dryRun,
  required bool skipAnalyze,
}) async {
  try {
    final report = await UpgradeEngine(
      root: root,
      logger: logger,
      dryRun: dryRun,
      skipAnalyze: skipAnalyze,
      packageVersion: stackchainPackageVersion,
    ).run();
    if (!report.quality.passed) exitCode = 1;
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
}

Future<void> _migrate(
  ArgResults command,
  String root,
  Logger logger, {
  required bool dryRun,
  required bool skipAnalyze,
}) async {
  try {
    final patch = MigrationPatch(
      architecture: command['architecture'] != null
          ? Architecture.fromYaml(command['architecture'] as String)
          : null,
      stateManagement: command['state'] != null
          ? StateManagement.fromYaml(command['state'] as String)
          : null,
      routing: command['routing'] != null
          ? Routing.fromYaml(command['routing'] as String)
          : null,
      di: command['di'] != null
          ? DiType.fromYaml(command['di'] as String)
          : null,
      network: command['network'] != null
          ? NetworkClient.fromYaml(command['network'] as String)
          : null,
      preset: command['preset'] as String?,
    );
    if (patch.isEmpty) {
      logger.error(
        'Nothing to migrate. Pass --state, --architecture, --routing, '
        '--di, --network, and/or --preset.',
      );
      exitCode = 64;
      return;
    }
    final report = await MigrationEngine(
      root: root,
      logger: logger,
      dryRun: dryRun,
      skipAnalyze: skipAnalyze,
      cleanup: command['keep-old'] != true,
      packageVersion: stackchainPackageVersion,
    ).run(patch);
    if (!report.quality.passed) exitCode = 1;
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
}

Future<void> _doctor(
  String root,
  Logger logger, {
  required bool skipAnalyze,
}) async {
  try {
    final context = await ProjectContext.detect(root);
    final config = await _loadConfig(root, context.packageName);

    logger.banner('stackchain doctor');
    logger.info('Package: ${context.packageName}');
    logger.info(
      'Stack: ${config.architecture.yaml} / ${config.stateManagement.yaml} / '
      '${config.routing.yaml} / ${config.di.yaml}',
    );
    if (config.preset != null) logger.info('Preset: ${config.preset}');
    logger.info('Features: ${config.features.join(', ')}');

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();
    if (!gate.passed) exitCode = 1;
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
}

void _printPresets(Logger logger) {
  const registry = PresetRegistry();
  logger.banner('Presets / blueprints');
  for (final id in registry.ids) {
    logger.info('  ${registry.describe(id)}');
  }
  logger.info('');
  logger.info('Use in stackchain.yaml:');
  logger.info('  stackchain:');
  logger.info('    preset: production_bloc');
  logger.info('    features: [auth, home]');
}

Future<void> _listBricks(String root, Logger logger) async {
  final engine = BrickEngine(projectRoot: root, logger: logger);
  final bricks = await engine.discoverBricks();
  if (bricks.isEmpty) {
    logger.warn('No bricks found.');
    return;
  }
  logger.banner('Generators');
  for (final entry in bricks.entries) {
    final manifest = await engine.load(entry.key);
    logger.info('  ${entry.key.padRight(16)} ${manifest.description}');
  }
  logger.info('');
  logger.info('Use: dart run stackchain make <name> <value>');
}

Future<void> _makeBrick(
  ArgResults command,
  String root,
  Logger logger, {
  required bool overwrite,
  required bool dryRun,
  required bool skipAnalyze,
}) async {
  if (command['help'] == true || command.rest.isEmpty) {
    stdout.writeln('''
Usage: dart run stackchain make <type> <name>

Examples:
  dart run stackchain make feature chat
  dart run stackchain make page onboarding
  dart run stackchain make widget app_chip
  dart run stackchain make service sync
''');
    return;
  }

  final brickName = command.rest.first;
  final vars = <String, dynamic>{};

  final named = command['name'] as String?;
  if (named != null && named.trim().isNotEmpty) {
    vars['name'] = named.trim();
  } else if (command.rest.length > 1) {
    vars['name'] = command.rest[1].trim();
  }

  for (final raw in command['var'] as List<String>) {
    final i = raw.indexOf('=');
    if (i <= 0) {
      logger.warn('Ignoring invalid --var "$raw" (expected key=value)');
      continue;
    }
    vars[raw.substring(0, i)] = raw.substring(i + 1);
  }

  if (!vars.containsKey('name')) {
    logger.error(
      'Missing name. Try: dart run stackchain make $brickName <name>',
    );
    exitCode = 64;
    return;
  }

  try {
    if (brickName == 'feature') {
      await FeatureCommand(
        root: root,
        logger: logger,
        overwrite: overwrite,
        dryRun: dryRun,
        skipAnalyze: skipAnalyze,
      ).add(vars['name'] as String);
      return;
    }

    await BrickEngine(
      projectRoot: root,
      logger: logger,
      overwrite: overwrite,
      dryRun: dryRun,
    ).make(brickName, vars: vars);

    if (brickName == 'page') {
      await _sync(root, logger, dryRun: dryRun, skipAnalyze: true);
    }
  } catch (e) {
    logger.error(e.toString());
    exitCode = 1;
  }
}

Future<void> _scaffoldBrick(
  String root,
  Logger logger,
  List<String> rest,
) async {
  if (rest.isEmpty) {
    stdout.writeln('Usage: dart run stackchain new <brick_name>');
    return;
  }
  final name = rest.first;
  final brickRoot = Directory(p.join(root, '.stackchain', 'bricks', name));
  final brickDir = Directory(p.join(brickRoot.path, '__brick__'));
  await brickDir.create(recursive: true);
  await File(p.join(brickRoot.path, 'brick.yaml')).writeAsString('''
name: $name
description: Custom $name brick
vars:
  name:
    type: string
    description: Name
    prompt: Name?
''');
  final template = File(
    p.join(brickDir.path, 'lib', '{{name.snakeCase}}.dart$templateSuffix'),
  );
  await template.create(recursive: true);
  await template.writeAsString('''
// Custom brick: $name
class {{name.pascalCase}} {
  const {{name.pascalCase}}();
}
''');
  logger.success('Created custom brick at .stackchain/bricks/$name');
  logger.info(
    'Edit __brick__/ templates, then: dart run stackchain make $name demo',
  );
}

void _printHelp(ArgParser parser, List<String> topics) {
  if (topics.isEmpty) {
    _printUsage(parser);
    return;
  }

  final topic = topics.first.trim().toLowerCase();
  switch (topic) {
    case 'help':
      stdout.writeln('''
Usage: dart run stackchain help [command]

Show Stackchain usage, or detailed help for one command.

Examples:
  dart run stackchain help
  dart run stackchain help init
  dart run stackchain help migrate
  dart run stackchain help feature
''');
    case 'init':
      stdout.writeln('''
Usage: dart run stackchain init [options]

Scaffold a production Flutter app from stackchain.yaml (or defaults).
Replaces the stock counter main.dart, writes app/core/features, merges
pubspec deps, writes .stackchain/lock.yaml, and runs the quality gate.

Options:
  --overwrite, -f     Replace existing generated files
  --dry-run           Print actions without writing
  --skip-analyze      Skip dart analyze in the quality gate
  --verbose, -v       Verbose logging
  --path, -p <dir>    Flutter project root

Examples:
  dart run stackchain init
  dart run stackchain init --overwrite
''');
    case 'feature':
    case 'add':
      stdout.writeln('''
Usage: dart run stackchain feature <name>
       dart run stackchain add <name>

Add a vertical slice: feature files + router + DI + tests + quality gate.
Recipes: auth, settings, profile get richer wiring.

Options:
  --overwrite, -f
  --dry-run
  --skip-analyze
  --name, -n <name>   Alternative to positional name

Examples:
  dart run stackchain feature auth
  dart run stackchain add notifications
''');
    case 'sync':
      stdout.writeln('''
Usage: dart run stackchain sync [options]

Smart-merge managed <stackchain:…> regions (router + DI) without a full
overwrite. Hand-written code outside markers is preserved.

Options:
  --dry-run
  --skip-analyze
''');
    case 'upgrade':
      stdout.writeln('''
Usage: dart run stackchain upgrade [options]

Refresh inferred pubspec deps, sync managed regions, update lockfile,
and re-run the quality gate.

Options:
  --dry-run
  --skip-analyze
''');
    case 'migrate':
      stdout.writeln('''
Usage: dart run stackchain migrate [options]

Evolve the stack intentionally (e.g. bloc → cubit, or apply a preset).
Regenerates presentation layers, deletes the old stack's generated files,
drops packages it no longer needs, updates pubspec, syncs, runs the gate.
Domain and data layers are never touched.

Options:
  --state bloc|cubit|riverpod|provider|getx|rxdart
  --architecture feature_first|clean|mvvm|mvc
  --routing go_router|auto_route|navigator|getx
  --di get_it|injectable|getx
  --network dio|http
  --preset production_bloc|production_riverpod|production_rxdart|...
  --keep-old          Leave old generated files and packages in place
  --dry-run
  --skip-analyze

Examples:
  dart run stackchain migrate --state rxdart --dry-run
  dart run stackchain migrate --state rxdart
  dart run stackchain migrate --preset production_riverpod
''');
    case 'doctor':
      stdout.writeln('''
Usage: dart run stackchain doctor [options]

Run the quality gate (structure + security baseline + optional analyze)
on the current project without generating files.

Options:
  --skip-analyze
''');
    case 'presets':
      stdout.writeln('''
Usage: dart run stackchain presets

List production blueprints (e.g. production_bloc, production_rxdart).

Use in stackchain.yaml:
  stackchain:
    preset: production_bloc
    features: [auth, home]
''');
    case 'make':
      stdout.writeln('''
Usage: dart run stackchain make <type> <name>

Generate a brick. Types: feature | page | widget | service
(feature routes through the vertical-slice generator).

Options:
  --overwrite, -f
  --dry-run
  --skip-analyze
  --name, -n <name>
  --var, -V key=value

Examples:
  dart run stackchain make feature chat
  dart run stackchain make page onboarding
  dart run stackchain make widget app_chip
  dart run stackchain make service sync
''');
    case 'list':
      stdout.writeln('''
Usage: dart run stackchain list

List built-in and project-local generators (.stackchain/bricks).
''');
    case 'new':
      stdout.writeln('''
Usage: dart run stackchain new <brick_name>

Scaffold a custom generator under .stackchain/bricks/<name>/.

Example:
  dart run stackchain new my_generator
  dart run stackchain make my_generator demo
''');
    default:
      stderr.writeln('Unknown help topic "$topic".');
      stdout.writeln('');
      _printUsage(parser);
      exitCode = 64;
  }
}

void _printUsage(ArgParser parser) {
  stdout.writeln('''
stackchain $stackchainPackageVersion — Flutter scaffolding that evolves with your app

Configure stackchain.yaml, generate a runnable app, add vertical slices,
then upgrade / migrate as the stack changes.

Usage:
  dart run stackchain <command> [options]
  dart run stackchain help [command]
  dart run stackchain:init

Commands:
  help [command]        Show this help, or help for one command
  init                  Scaffold project (replaces default counter main.dart)
  feature <name>        Vertical slice: files + router + DI + tests
  add <name>            Alias for feature
  sync                  Smart-merge router/DI managed regions
  upgrade               Refresh deps, sync, lockfile, quality gate
  migrate               Evolve stack (e.g. --state cubit --preset ...)
  doctor                Run quality gate on the current project
  presets               List production blueprints
  make <type> <name>    Generate feature | page | widget | service
  list                  List generators
  new <name>            Create a custom generator

Examples:
  dart run stackchain help
  dart run stackchain help migrate
  dart run stackchain init
  dart run stackchain feature auth
  dart run stackchain sync
  dart run stackchain upgrade
  dart run stackchain migrate --state rxdart
  dart run stackchain doctor

Options:
${parser.usage}

Config: stackchain.yaml
  preset: production_bloc | production_riverpod | production_rxdart | ...
  architecture: feature_first | clean | mvvm | mvc
  state_management: bloc | cubit | riverpod | provider | getx | rxdart
  routing: go_router | auto_route | navigator | getx
  di: get_it | injectable | getx
  network: dio | http
''');
}
