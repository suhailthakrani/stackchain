import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/stackchain_config.dart';
import '../parser/yaml_parser.dart';
import '../presets/preset_registry.dart';
import '../quality/quality_gate.dart';
import '../sync/project_sync.dart';
import '../utils/file_writer.dart';
import '../utils/logger.dart';
import '../utils/pubspec_merger.dart';
import 'stack_lock.dart';

/// Evolves an existing Stackchain project: deps, sync, lockfile, quality gate.
///
/// This is the strongest differentiator vs one-shot generators.
class UpgradeEngine {
  UpgradeEngine({
    required this.root,
    Logger? logger,
    this.dryRun = false,
    this.skipAnalyze = false,
    this.packageVersion = '1.1.1',
  }) : logger = logger ?? Logger();

  final String root;
  final Logger logger;
  final bool dryRun;
  final bool skipAnalyze;
  final String packageVersion;

  Future<UpgradeReport> run() async {
    final context = await ProjectContext.detect(root);
    final config = await _loadConfig(context.packageName);
    final previous = await StackLock.read(root);

    logger.banner('stackchain upgrade');
    if (previous == null) {
      logger.info('No lockfile yet — establishing baseline.');
    } else if (previous.fingerprint == config.stackFingerprint()) {
      logger.info('Stack fingerprint unchanged — refreshing deps + sync.');
    } else {
      logger.warn(
        'Stack changed since last lock '
        '(${previous.architecture}/${previous.stateManagement} → '
        '${config.architecture.yaml}/${config.stateManagement.yaml}). '
        'Prefer `dart run stackchain migrate` for intentional migrations.',
      );
    }

    final pubChanges = await _upgradePubspec(config);
    final sync = ProjectSync(
      root: root,
      config: config,
      logger: logger,
      dryRun: dryRun,
    );
    await sync.run();

    if (!dryRun) {
      await StackLock.write(
        root,
        config,
        packageVersion: packageVersion,
      );
      logger.success('Updated ${StackLock.relativePath}');
    }

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();

    return UpgradeReport(
      pubspecChanged: pubChanges,
      syncedFiles: sync.touched,
      quality: gate,
      previousFingerprint: previous?.fingerprint,
      currentFingerprint: config.stackFingerprint(),
    );
  }

  Future<bool> _upgradePubspec(StackchainConfig config) async {
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    final existing = await pubspecFile.readAsString();
    final merged = PubspecMerger.merge(existing: existing, config: config);
    if (merged == existing) {
      logger.detail('pubspec.yaml already aligned');
      return false;
    }
    if (dryRun) {
      logger.step('Would update pubspec.yaml');
      return true;
    }
    await pubspecFile.writeAsString(merged);
    logger.success('Upgraded pubspec.yaml dependencies');
    return true;
  }

  Future<StackchainConfig> _loadConfig(String packageName) async {
    final file = File(p.join(root, 'stackchain.yaml'));
    if (!await file.exists()) {
      return StackchainConfig.defaults(packageName: packageName);
    }
    return YamlParser.parse(
      await file.readAsString(),
      packageName: packageName,
    );
  }
}

class UpgradeReport {
  UpgradeReport({
    required this.pubspecChanged,
    required this.syncedFiles,
    required this.quality,
    this.previousFingerprint,
    required this.currentFingerprint,
  });

  final bool pubspecChanged;
  final List<String> syncedFiles;
  final QualityReport quality;
  final String? previousFingerprint;
  final String currentFingerprint;
}
