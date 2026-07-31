import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/stackchain_config.dart';

/// Merges inferred dependencies into the host app's pubspec.yaml.
class PubspecMerger {
  /// Returns updated pubspec content.
  static String merge({
    required String existing,
    required StackchainConfig config,
  }) {
    final deps = config.inferredDependencies();
    final devDeps = Map<String, String>.from(config.inferredDevDependencies())
      ..remove('flutter_lints');

    var result = existing;
    result = _ensureDependencyBlock(result, 'dependencies', deps);
    result = _ensureDependencyBlock(result, 'dev_dependencies', devDeps);

    if (config.modules.localization && !_hasFlutterGenL10n(result)) {
      result = _ensureFlutterGenerate(result);
    }

    return result;
  }

  /// Removes [packages] from `dependencies` / `dev_dependencies`.
  ///
  /// Used by `migrate` to drop packages the old stack needed and the new one
  /// does not (e.g. `flutter_bloc` after bloc → riverpod).
  static String prune({
    required String existing,
    required Iterable<String> packages,
  }) {
    final names = packages.toSet();
    if (names.isEmpty) return existing;

    var result = existing;
    result = _removeFromBlock(result, 'dependencies', names);
    result = _removeFromBlock(result, 'dev_dependencies', names);
    return result;
  }

  /// Packages required by [before] but no longer required by [after].
  static Set<String> obsoletePackages({
    required StackchainConfig before,
    required StackchainConfig after,
  }) {
    final keep = {
      ...after.inferredDependencies().keys,
      ...after.inferredDevDependencies().keys,
    };
    return {
      ...before.inferredDependencies().keys,
      ...before.inferredDevDependencies().keys,
    }.where((name) => !keep.contains(name)).toSet();
  }

  static String _removeFromBlock(
    String content,
    String section,
    Set<String> names,
  ) {
    final match = RegExp('^$section:\\s*\$', multiLine: true)
        .firstMatch(content);
    if (match == null) return content;

    final after = content.substring(match.end);
    final nextTop = RegExp(
      r'^[a-zA-Z_][a-zA-Z0-9_]*:',
      multiLine: true,
    ).firstMatch(after);
    final blockEnd = nextTop == null ? after.length : nextTop.start;
    final block = after.substring(0, blockEnd);

    final lines = block.split('\n');
    final kept = <String>[];
    var skippingChildrenOf = -1;
    for (final line in lines) {
      final indent = line.length - line.trimLeft().length;
      if (skippingChildrenOf >= 0) {
        // Drop nested config (e.g. `sdk:` / `version:`) under a removed key.
        if (line.trim().isEmpty || indent > skippingChildrenOf) continue;
        skippingChildrenOf = -1;
      }
      final key = RegExp(r'^(\s+)([a-zA-Z0-9_]+):').firstMatch(line);
      if (key != null && names.contains(key.group(2))) {
        skippingChildrenOf = indent;
        continue;
      }
      kept.add(line);
    }

    if (kept.length == lines.length) return content;
    return content.substring(0, match.end) +
        kept.join('\n') +
        after.substring(blockEnd);
  }

  static bool _hasFlutterGenL10n(String content) {
    return content.contains('generate: true');
  }

  static String _ensureFlutterGenerate(String content) {
    if (content.contains(RegExp(r'generate:\s*true'))) return content;
    final flutterMatch =
        RegExp(r'^flutter:\s*$', multiLine: true).firstMatch(content);
    if (flutterMatch == null) return content;
    final insertAt = flutterMatch.end;
    return '${content.substring(0, insertAt)}\n  generate: true'
        '${content.substring(insertAt)}';
  }

  static String _ensureDependencyBlock(
    String content,
    String section,
    Map<String, String> packages,
  ) {
    if (packages.isEmpty) return content;

    final sectionRegex = RegExp('^$section:\\s*\$', multiLine: true);
    final match = sectionRegex.firstMatch(content);
    if (match == null) {
      final suffix = content.endsWith('\n') ? '' : '\n';
      return '$content$suffix\n$section:\n${_formatDeps(packages)}\n';
    }

    final after = content.substring(match.end);
    // Next top-level key (e.g. dev_dependencies / flutter), ignoring blanks/comments.
    final nextTop = RegExp(
      r'^[a-zA-Z_][a-zA-Z0-9_]*:',
      multiLine: true,
    ).firstMatch(after);
    final blockEnd = nextTop == null ? after.length : nextTop.start;
    final block = after.substring(0, blockEnd);

    final missing = <String, String>{};
    for (final entry in packages.entries) {
      final already = RegExp(
        '^\\s*${RegExp.escape(entry.key)}:',
        multiLine: true,
      ).hasMatch(block);
      if (!already) missing[entry.key] = entry.value;
    }
    if (missing.isEmpty) return content;

    // Insert after the last non-empty line of the section.
    var insertOffset = blockEnd;
    while (insertOffset > 0 &&
        (after[insertOffset - 1] == '\n' || after[insertOffset - 1] == ' ')) {
      insertOffset--;
    }

    final insertion = '\n${_formatDeps(missing)}\n';
    final absoluteInsert = match.end + insertOffset;
    return content.substring(0, absoluteInsert) +
        insertion +
        content.substring(absoluteInsert);
  }

  static String _formatDeps(Map<String, String> deps) {
    final keys = deps.keys.toList()..sort();
    return keys.map((k) => '  $k: ${deps[k]}').join('\n');
  }

  /// Ensures a Flutter-SDK package under `dev_dependencies` (e.g. integration_test).
  ///
  /// Writes:
  /// ```yaml
  ///   integration_test:
  ///     sdk: flutter
  /// ```
  static String ensureSdkDevDependency(String existing, String packageName) {
    final already = RegExp(
      '^\\s*${RegExp.escape(packageName)}:\\s*\$',
      multiLine: true,
    ).hasMatch(existing);
    if (already) return existing;

    final section = RegExp(r'^dev_dependencies:\s*$', multiLine: true)
        .firstMatch(existing);
    final block = '''
  $packageName:
    sdk: flutter
''';

    if (section == null) {
      final suffix = existing.endsWith('\n') ? '' : '\n';
      return '$existing$suffix\ndev_dependencies:\n$block';
    }

    final after = existing.substring(section.end);
    final nextTop = RegExp(
      r'^[a-zA-Z_][a-zA-Z0-9_]*:',
      multiLine: true,
    ).firstMatch(after);
    final blockEnd = nextTop == null ? after.length : nextTop.start;

    var insertOffset = blockEnd;
    while (insertOffset > 0 &&
        (after[insertOffset - 1] == '\n' || after[insertOffset - 1] == ' ')) {
      insertOffset--;
    }

    final absoluteInsert = section.end + insertOffset;
    return '${existing.substring(0, absoluteInsert)}\n$block'
        '${existing.substring(absoluteInsert)}';
  }
}

/// Writes a default stackchain.yaml when missing.
Future<void> writeDefaultConfig(String root) async {
  final file = File(p.join(root, 'stackchain.yaml'));
  if (await file.exists()) return;
  await file.writeAsString(_defaultYaml);
}

const _defaultYaml = '''
# stackchain configuration
# Docs: https://pub.dev/packages/stackchain
#
# Most settings are optional — defaults are production-ready.

stackchain:
  # preset: production_bloc       # production_riverpod | clean_cubit | firebase_bloc | ...
  # architecture: feature_first   # feature_first | clean | mvvm | mvc
  # state_management: bloc        # bloc | cubit | riverpod | provider | getx | rxdart
  # routing: go_router            # go_router | auto_route | navigator | getx
  # di: get_it                    # get_it | injectable | getx
  # network: dio
  # localization: false
  # firebase: false

  features:
    - home
''';
