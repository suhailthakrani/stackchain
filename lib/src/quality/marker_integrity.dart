import 'dart:io';

import 'package:path/path.dart' as p;

import '../architecture/architecture_registry.dart';
import '../merge/owned_regions.dart';
import '../merge/region_merger.dart';
import '../models/enums.dart';
import '../models/stackchain_config.dart';
import '../templates/app/router_templates.dart';
import '../templates/core/core_templates.dart';
import '../templates/features/feature_templates.dart';

/// Detects hand-edits inside stackchain-managed marker regions.
///
/// Compares on-disk region bodies to what the current templates / sync would
/// emit. Mismatches are violations — put custom code in `custom` regions or
/// outside markers instead.
class MarkerIntegrity {
  MarkerIntegrity({
    required this.root,
    required this.config,
    ArchitectureRegistry? registry,
  }) : registry = registry ?? ArchitectureRegistry();

  final String root;
  final StackchainConfig config;
  final ArchitectureRegistry registry;

  /// Returns human-readable violation messages (empty if clean).
  Future<List<String>> check() async {
    final violations = <String>[];
    await _checkRouterDi(violations);
    await _checkPresentation(violations);
    return violations;
  }

  Future<void> _checkRouterDi(List<String> violations) async {
    final routerFiles = RouterTemplates(config).generate();

    for (final path in const [
      'lib/app/router/app_routes.dart',
      'lib/app/router/app_router.dart',
    ]) {
      final seed = routerFiles[path];
      if (seed == null) continue;
      await _compareFileRegion(
        violations,
        relativePath: path,
        expectedSource: seed,
        regionId: 'routes',
      );
    }

    if (config.di == DiType.getIt) {
      final di = CoreTemplates(config).generate()['lib/core/di/injection.dart'];
      if (di != null) {
        await _compareFileRegion(
          violations,
          relativePath: 'lib/core/di/injection.dart',
          expectedSource: di,
          regionId: 'core',
        );
        await _compareFileRegion(
          violations,
          relativePath: 'lib/core/di/injection.dart',
          expectedSource: di,
          regionId: 'features',
        );
      }
    }
  }

  Future<void> _checkPresentation(List<String> violations) async {
    for (final feature in config.features) {
      final files = FeatureTemplates(
        config.copyWith(features: [feature]),
        registry: registry,
      ).generate();

      for (final entry in files.entries) {
        if (!OwnedRegions.hasOwnedMarkers(entry.value)) continue;
        final file = File(p.join(root, entry.key));
        if (!await file.exists()) continue;

        final onDisk = await file.readAsString();
        if (!OwnedRegions.hasOwnedMarkers(onDisk)) continue;

        for (final id in OwnedRegions.mergeIds) {
          if (!RegionMerger.hasRegion(entry.value, id)) continue;
          if (!RegionMerger.hasRegion(onDisk, id)) continue;

          final expected = RegionMerger.readRegion(entry.value, id);
          final actual = RegionMerger.readRegion(onDisk, id);
          if (!_bodiesEqual(expected, actual)) {
            violations.add(
              'Managed <$id> region was hand-edited in ${entry.key}',
            );
          }
        }
      }
    }
  }

  Future<void> _compareFileRegion(
    List<String> violations, {
    required String relativePath,
    required String expectedSource,
    required String regionId,
  }) async {
    final file = File(p.join(root, relativePath));
    if (!await file.exists()) return;
    final onDisk = await file.readAsString();
    if (!RegionMerger.hasRegion(onDisk, regionId)) return;
    if (!RegionMerger.hasRegion(expectedSource, regionId)) return;

    final expected = RegionMerger.readRegion(expectedSource, regionId);
    final actual = RegionMerger.readRegion(onDisk, regionId);
    if (!_bodiesEqual(expected, actual)) {
      violations.add(
        'Managed <$regionId> region was hand-edited in $relativePath',
      );
    }
  }

  /// Whitespace-tolerant equality for region bodies.
  static bool bodiesEqual(String? a, String? b) => _bodiesEqual(a, b);

  static bool _bodiesEqual(String? a, String? b) {
    return _normalize(a) == _normalize(b);
  }

  static String _normalize(String? body) {
    if (body == null || body.isEmpty) return '';
    return body
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();
  }
}
