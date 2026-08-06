import 'dart:io';

import 'package:path/path.dart' as p;

import '../merge/owned_regions.dart';
import '../merge/region_merger.dart';
import '../migrate/stack_lock.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../presets/preset_registry.dart';
import '../sync/project_sync.dart';
import '../utils/logger.dart';
import '../utils/stack_paths.dart';
import '../version.dart';
import 'marker_integrity.dart';
import 'quality_gate.dart';

/// Extended diagnostics + optional auto-repair for `stackchain doctor`.
class DoctorEngine {
  DoctorEngine({
    required this.root,
    required this.config,
    Logger? logger,
    this.fix = false,
    this.skipAnalyze = false,
    this.packageVersion = stackchainPackageVersion,
  }) : logger = logger ?? Logger();

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool fix;
  final bool skipAnalyze;
  final String packageVersion;

  final List<String> suggestions = [];
  final List<String> fixed = [];

  Future<QualityReport> run() async {
    logger.banner('stackchain doctor${fix ? ' --fix' : ''}');
    logger.info(
      'Stack: ${config.architecture.yaml} / ${config.stateManagement.yaml} / '
      '${config.routing.yaml} / ${config.di.yaml}',
    );
    logger.info('Features: ${config.features.join(', ')}');

    final report = QualityReport();

    await _diagnose(report);

    if (fix) {
      await _applyFixes(report);
      // Re-diagnose so repaired orphans/lock drift don't keep exit code 1.
      report.errors.clear();
      report.warnings.clear();
      suggestions.clear();
      await _diagnose(report);
    }

    final gate = await QualityGate(
      root: root,
      config: config,
      logger: logger,
      runAnalyzer: !skipAnalyze,
    ).run();

    report.errors.addAll(gate.errors);
    report.warnings.addAll(gate.warnings);

    for (final s in suggestions) {
      logger.info('→ $s');
    }
    for (final f in fixed) {
      logger.success('Fixed: $f');
    }

    if (!report.passed) {
      logger.error('Doctor found ${report.errors.length} error(s)');
    } else if (suggestions.isNotEmpty && !fix) {
      logger.warn(
        'Doctor passed with suggestions — re-run with --fix to auto-repair '
        'what it can.',
      );
    }

    return report;
  }

  Future<void> _diagnose(QualityReport report) async {
    await _checkLock(report);
    await _checkFeatureMarkers(report);
    await _checkManagedRegionIntegrity(report);
    await _checkOrphans(report);
  }

  /// Fails when managed marker bodies were hand-edited.
  Future<void> _checkManagedRegionIntegrity(QualityReport report) async {
    final violations = await MarkerIntegrity(
      root: root,
      config: config,
    ).check();
    if (violations.isEmpty) return;

    report.errors.addAll(violations);

    final touchedRouterDi = violations.any(
      (v) =>
          v.contains('app_routes.dart') ||
          v.contains('app_router.dart') ||
          v.contains('injection.dart'),
    );
    final presentation = violations
        .where(
          (v) =>
              v.contains('/features/') ||
              v.contains('presentation') ||
              v.contains('_page.dart') ||
              v.contains('_bloc.dart') ||
              v.contains('_cubit.dart'),
        )
        .toList();

    if (touchedRouterDi) {
      suggestions.add(
        'dart run stackchain sync  # or doctor --fix — restores router/DI',
      );
    }
    for (final feature in config.features) {
      if (presentation.any((v) => v.contains('/$feature/') ||
          v.contains('${feature}_'))) {
        suggestions.add(
          'dart run stackchain feature $feature --overwrite  '
          '# restores managed regions (*.stackchain.bak backup)',
        );
      }
    }
  }

  Future<void> _checkLock(QualityReport report) async {
    final lockFile = File(StackLock.pathFor(root));
    if (!await lockFile.exists()) {
      report.warnings.add('Missing .stackchain/lock.yaml');
      suggestions.add('dart run stackchain sync  # writes lockfile');
      return;
    }
    try {
      final lock = StackLock.fromYaml(await lockFile.readAsString());
      if (lock.packageVersion != packageVersion) {
        report.warnings.add(
          'Lock package_version ${lock.packageVersion} != CLI $packageVersion',
        );
        suggestions.add('dart run stackchain upgrade');
      }
      final current = config.stackFingerprint();
      if (lock.fingerprint.isNotEmpty && lock.fingerprint != current) {
        report.warnings.add(
          'stackchain.yaml fingerprint drifted from lock — migrate or upgrade',
        );
        suggestions.add(
          'dart run stackchain migrate --dry-run  # review stack drift',
        );
      }
      final missing = config.features
          .where((f) => !lock.features.contains(f))
          .toList();
      if (missing.isNotEmpty) {
        report.warnings.add(
          'Features in yaml but not lock: ${missing.join(', ')}',
        );
        suggestions.add('dart run stackchain sync');
      }
    } catch (e) {
      report.warnings.add('Could not parse lockfile: $e');
    }
  }

  Future<void> _checkFeatureMarkers(QualityReport report) async {
    for (final feature in config.features) {
      final dir = Directory(p.join(root, 'lib', 'features', feature));
      if (!await dir.exists()) {
        report.errors.add('Missing lib/features/$feature');
        suggestions.add('dart run stackchain feature $feature');
        continue;
      }

      var sawPresentation = false;
      var unmarked = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final rel = p.relative(entity.path, from: root);
        final isPresentation = rel.contains('/presentation/') ||
            rel.contains('/viewmodels/') ||
            rel.contains('/controllers/') ||
            rel.endsWith('_page.dart');
        if (!isPresentation) continue;
        sawPresentation = true;
        final content = await entity.readAsString();
        if (!OwnedRegions.hasOwnedMarkers(content) &&
            (rel.contains('/bloc/') ||
                rel.contains('/cubit/') ||
                rel.endsWith('_page.dart') ||
                rel.contains('/providers/') ||
                rel.contains('/controllers/'))) {
          unmarked++;
          report.warnings.add(
            'No stackchain markers in $rel — custom code may be lost on migrate',
          );
        }
      }
      if (sawPresentation && unmarked > 0) {
        suggestions.add(
          'dart run stackchain feature $feature --overwrite  '
          '# upgrades markers (creates *.stackchain.bak)',
        );
      }

      final customTest =
          File(p.join(root, 'test', 'features', '${feature}_custom_test.dart'));
      if (!await customTest.exists()) {
        report.warnings.add('Missing ${feature}_custom_test.dart');
        suggestions.add('dart run stackchain test $feature --type unit');
      }
    }
  }

  Future<void> _checkOrphans(QualityReport report) async {
    if (config.routing == Routing.navigator) return;

    final router = File(p.join(root, 'lib/app/router/app_router.dart'));
    if (!await router.exists()) return;
    final content = await router.readAsString();
    if (!RegionMerger.hasRegion(content, 'routes')) return;

    for (final feature in config.features) {
      final wired = content.contains('AppRoutes.$feature') ||
          content.contains("name: '$feature'") ||
          content.contains(StackPaths.pascal(feature));
      if (!wired) {
        report.errors.add('Orphan feature "$feature" — not in app_router');
        suggestions.add('dart run stackchain sync');
      }
    }

    // Routes referencing removed features (heuristic).
    final routeNames = RegExp(r"name:\s*'([a-z][a-z0-9_]*)'")
        .allMatches(content)
        .map((m) => m.group(1)!)
        .toSet();
    for (final name in routeNames) {
      if (name == 'home' || config.features.contains(name)) continue;
      report.warnings.add(
        'Router mentions "$name" but it is not in stackchain.yaml features',
      );
      suggestions.add('dart run stackchain sync  # or remove leftover route');
    }
  }

  Future<void> _applyFixes(QualityReport report) async {
    logger.step('Applying safe fixes...');
    await ProjectSync(
      root: root,
      config: config,
      logger: logger,
      dryRun: false,
    ).run();
    fixed.add('Synced router / DI managed regions');

    await StackLock.write(
      root,
      config,
      packageVersion: packageVersion,
    );
    fixed.add('Refreshed .stackchain/lock.yaml');
  }
}
