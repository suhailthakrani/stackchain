import 'dart:io';

import 'package:path/path.dart' as p;

import '../merge/owned_regions.dart';
import '../merge/region_merger.dart';
import '../models/stackchain_config.dart';
import '../utils/logger.dart';
import '../utils/stack_paths.dart';
import 'feature_test_templates.dart';

/// Scans `// <stackchain:custom>` for methods and stubs tests in `*_custom_test.dart`.
class CustomMethodStubber {
  CustomMethodStubber({
    required this.root,
    required this.config,
    Logger? logger,
    this.dryRun = false,
  }) : logger = logger ?? Logger();

  final String root;
  final StackchainConfig config;
  final Logger logger;
  final bool dryRun;

  /// Lifecycle / framework methods that should never become stub tests.
  static const _ignoredMethods = {
    'build',
    'createState',
    'initState',
    'dispose',
    'didUpdateWidget',
    'didChangeDependencies',
    'deactivate',
    'activate',
    'reassemble',
    'Function', // `void Function(` typedef / callback noise
  };

  /// Public instance methods declared inside a custom region.
  ///
  /// Supports one level of nested generics (`Future<Map<String, dynamic>>`).
  static final _methodPattern = RegExp(
    r'(?:'
    r'(?:Future|List|Map|Set)(?:<(?:[^<>\n]|<[^<>\n]*>)+>)?|'
    r'void|bool|int|double|num|String|dynamic'
    r')\s+'
    r'([a-zA-Z_]\w*)\s*\(',
  );

  Future<List<String>> stubFeature(String feature) async {
    final methods = await _collectCustomMethods(feature);
    if (methods.isEmpty) {
      logger.info('No custom methods found for "$feature"');
      return const [];
    }

    final customPath = FeatureTestTemplates.customTestPath(feature);
    final file = File(p.join(root, customPath));
    var content = await file.exists()
        ? await file.readAsString()
        : FeatureTestTemplates(config).generate(
            feature,
            types: const {},
          )[customPath]!;

    final added = <String>[];
    for (final method in methods) {
      final testName = '$method is implemented';
      if (content.contains("'$testName'") ||
          content.contains('"$testName"')) {
        continue;
      }
      final stub = '''
    test('$testName', () async {
      // TODO: assert behavior of $method()
      fail('Implement test for $method');
    });
''';
      content = _insertBeforeGroupClose(content, stub);
      added.add(method);
    }

    if (added.isEmpty) {
      logger.info('Custom tests already cover ${methods.length} method(s)');
      return const [];
    }

    if (!dryRun) {
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }
    logger.success(
      '${dryRun ? 'Would stub' : 'Stubbed'} ${added.length} method(s) in $customPath: '
      '${added.join(', ')}',
    );
    return added;
  }

  Future<List<String>> stubAll() async {
    final all = <String>[];
    for (final feature in config.features) {
      all.addAll(await stubFeature(feature));
    }
    return all;
  }

  Future<Set<String>> _collectCustomMethods(String feature) async {
    final found = <String>{};
    final featureRoot = Directory(p.join(root, 'lib', 'features', feature));
    if (!await featureRoot.exists()) return found;

    await for (final entity in featureRoot.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = await entity.readAsString();
      if (!OwnedRegions.hasOwnedMarkers(source)) continue;
      final custom = RegionMerger.readRegion(source, OwnedRegions.custom);
      if (custom == null || custom.trim().isEmpty) continue;
      // Skip placeholder-only regions.
      if (custom.contains('Add custom methods here') &&
          !_methodPattern.hasMatch(custom)) {
        continue;
      }
      for (final match in _methodPattern.allMatches(custom)) {
        final name = match.group(1);
        if (name == null) continue;
        if (name.startsWith('_')) continue; // skip private helpers
        if (_ignoredMethods.contains(name)) continue;
        found.add(name);
      }
    }
    return found;
  }

  String _insertBeforeGroupClose(String source, String stub) {
    // Insert before the last `});` that closes the group in main.
    final marker = RegExp(r'\n  \}\);\n\}\s*$');
    final match = marker.firstMatch(source);
    if (match != null) {
      return source.replaceFirst(marker, '\n$stub  });\n}\n');
    }
    // Fallback: append before final closing braces.
    final last = source.lastIndexOf('});');
    if (last >= 0) {
      return '${source.substring(0, last)}$stub${source.substring(last)}';
    }
    return '$source\n$stub';
  }
}

/// Convenience for callers that only have a feature name.
String customTestPathFor(String feature) =>
    'test/features/${feature}_custom_test.dart';

/// Expose pascal for tests.
String featurePascal(String feature) => StackPaths.pascal(feature);
