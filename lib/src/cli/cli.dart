import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../bricks/brick_engine.dart';
import '../generators/project_generator.dart';
import '../utils/logger.dart';
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
      ..addFlag('verbose', abbr: 'v', negatable: false),
  );
  parser.addCommand(
    'make',
    ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('overwrite', abbr: 'f', negatable: false)
      ..addFlag('dry-run', negatable: false)
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

  // Bare invocation with no subcommand → project init
  if (command == null) {
    await _initProject(root, logger, dryRun: dryRun, overwrite: overwrite);
    return;
  }

  switch (command.name) {
    case 'init':
      if (command['help'] == true) {
        stdout.writeln('Usage: dart run stackchain init [--overwrite] [--dry-run]');
        return;
      }
      await _initProject(root, logger, dryRun: dryRun, overwrite: overwrite);
    case 'list':
      await _listBricks(root, logger);
    case 'make':
      await _makeBrick(
        command,
        root,
        logger,
        overwrite: overwrite,
        dryRun: dryRun,
      );
    case 'feature':
    case 'add':
      final name = _resolveName(command);
      if (command['help'] == true || name == null) {
        stdout.writeln('''
Usage: dart run stackchain feature <name>
       dart run stackchain add <name>

Examples:
  dart run stackchain feature auth
  dart run stackchain add notifications
''');
        return;
      }
      await FeatureCommand(
        root: root,
        logger: logger,
        overwrite: overwrite,
      ).add(name);
    case 'new':
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
}) async {
  try {
    await ProjectGenerator(
      root: root,
      logger: logger,
      dryRun: dryRun,
      overwrite: overwrite,
    ).run();
  } catch (e, st) {
    logger.error(e.toString());
    if (logger.verbose) logger.detail(st.toString());
    exitCode = 1;
  }
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
    await BrickEngine(
      projectRoot: root,
      logger: logger,
      overwrite: overwrite,
      dryRun: dryRun,
    ).make(brickName, vars: vars);
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
  await File(
    p.join(brickDir.path, 'lib', '{{name.snakeCase}}.dart'),
  ).create(recursive: true);
  await File(
    p.join(brickDir.path, 'lib', '{{name.snakeCase}}.dart'),
  ).writeAsString('''
// Custom brick: $name
class {{name.pascalCase}} {
  const {{name.pascalCase}}();
}
''');
  logger.success('Created custom brick at .stackchain/bricks/$name');
  logger.info('Edit __brick__/ templates, then: dart run stackchain make $name demo');
}

void _printUsage(ArgParser parser) {
  stdout.writeln('''
stackchain — Flutter scaffolding you keep using

Configure stackchain.yaml, then generate a runnable app and keep adding
features as you build.

Usage:
  dart run stackchain <command> [options]
  dart run stackchain:init              # shortcut for init

Commands:
  init                  Scaffold project (replaces default counter main.dart)
  feature <name>        Add a feature  (alias: add)
  make <type> <name>    Generate feature | page | widget | service
  list                  List generators
  new <name>            Create a custom generator

Examples:
  dart run stackchain init
  dart run stackchain feature auth
  dart run stackchain make page onboarding
  dart run stackchain make widget app_chip

Options:
${parser.usage}

Config: stackchain.yaml
  architecture: feature_first | clean | mvvm | mvc
  state_management: bloc | cubit | riverpod | provider | getx
  routing: go_router | auto_route | navigator | getx
  di: get_it | injectable | getx
  network: dio | http
''');
}
