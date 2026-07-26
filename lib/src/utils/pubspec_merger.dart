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
